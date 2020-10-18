#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    Deploys Web App ASP.NET artifacts
 
.DESCRIPTION 
    This scripts pulls a pre-created ZipDeploy package from Pipeline artifacts and publishes it to the App Service Web App.
    It eliminates the need for a release pipeline just to test the Web App.
#> 
#Requires -Version 7
param (    
    [parameter(Mandatory=$false)][switch]$Database,
    [parameter(Mandatory=$false)][switch]$Website,
    [parameter(Mandatory=$false)][switch]$Restart,
    [parameter(Mandatory=$false)][switch]$Test,
    [parameter(Mandatory=$false)][switch]$All,

    # These parameters are either provided or their values retrieved from Terraform
    [parameter(Mandatory=$false)][object]$AppResourceGroup,
    [parameter(Mandatory=$false)][object]$AppAppServiceName=$null,
    [parameter(Mandatory=$false)][object]$AppAppServiceIdentity,
    [parameter(Mandatory=$false)][object]$AppAppServiceClientID,
    [parameter(Mandatory=$false)][object]$DBAName,
    [parameter(Mandatory=$false)][object]$DBAObjectId,
    [parameter(Mandatory=$false)][object]$AppUrl,
    [parameter(Mandatory=$false)][object]$DevOpsOrgUrl,
    [parameter(Mandatory=$false)][object]$DevOpsProject,
    [parameter(Mandatory=$false)][object]$SqlServer,
    [parameter(Mandatory=$false)][object]$SqlServerFQDN,
    [parameter(Mandatory=$false)][object]$SqlDatabase,

    [parameter(Mandatory=$false,HelpMessage="The Terraform workspace to use")][string]$Workspace=$env:TF_WORKSPACE,
    [parameter(Mandatory=$false)][int]$MaxTests=600,
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "terraform")
) 
Write-Host $MyInvocation.line

function DeployContainerWebApp () {
    $slot = "staging"
    # This step assumes a container has already been deployed
    # We merely have to toggle ASPNETCORE_ENVIRONMENT to 'Online' using a deployment slot swap

    $productionMode = $(az webapp config appsettings list -n $AppAppServiceName -g $AppResourceGroup --query "[?name=='ASPNETCORE_ENVIRONMENT'].value" -o tsv)
    # Create staging deployment slot, if it does not exist yet
    if (!(az webapp deployment slot list -n $AppAppServiceName -g $AppResourceGroup --query "[?name=='$slot']" -o tsv)) {
        az webapp deployment slot create -n $AppAppServiceName --configuration-source $AppAppServiceName -s $slot -g $AppResourceGroup --query "hostNames"
        $stagingMode = ($productionMode -eq "Offline" ? "Online" : "Offline")
        az webapp config appsettings set --settings ASPNETCORE_ENVIRONMENT=$stagingMode -s $slot -n $AppAppServiceName -g $AppResourceGroup --query "[?name=='ASPNETCORE_ENVIRONMENT']"
    }

    if ($productionMode -eq "Offline") {
        Write-Host "Swapping slots..."
        # Swap slots
        az webapp deployment slot swap -s $slot -n $AppAppServiceName -g $AppResourceGroup
    } else {
        Write-Host "Production slot is already online, no swap needed"
    }
}

function DeployWebApp () {
    if (!$devOpsOrgUrl) {
        Write-Warning "DevOps Organization is not set, quiting"
        exit
    }
    if (!$devOpsProject) {
        Write-Warning "DevOps Project is not set, quiting"
        exit
    }
    # Variables taken from from pipeline yaml
    $buildDefinitionName = "asp.net-core-sql-ci" 
    $artifactName = "aspnetcoresql"
    $packageName = "publish.zip" 
    $configuration = "Release"
    $dotnetVersion = "3.1"

    # We need this for Azure DevOps
    az extension add --name azure-devops 

    # Set defaults
    AzLogin
    az devops configure --defaults organization=$devOpsOrgUrl project=$devOpsProject

    $runid = $(az pipelines runs list --result succeeded --top 1 --query "[?definition.name == '$buildDefinitionName'].id | [0]")
    if (!$runid) {
        Write-Error "No successful run found for build '$buildDefinitionName''"
        exit
    }
    Write-Information "Last successful run of $buildDefinitionName is $runid"

    # Determine & create download directory
    $tmpDir = [System.IO.Path]::GetTempPath()
    $downloadDir = Join-Path $tmpDir $runid 
    if (!(Test-Path $downloadDir)) {
        $null = New-Item -Path $tmpDir -Name $runid -ItemType "Directory"
    }
    $packagePath = Join-Path $downloadDir "s" "bin" $configuration "netcoreapp${dotnetVersion}" $packageName

    # Download pipeline artifact (build artifact won't work)
    Write-Host "Downloading artifacts from $buildDefinitionName build $runid to $downloadDir..."
    az pipelines runs artifact download --run-id $runid --artifact-name $artifactName --path $downloadDir

    if (!(Test-Path $packagePath)) {
        Write-Error "Package $packagePath not found"
        exit 1
    }

    # Publish web app
    Write-Host "Publishing $packageName to web app $appAppServiceName..."
    az webapp deployment source config-zip -g $appResourceGroup -n $appAppServiceName --src $packagePath -o none

    Write-Host "Web app $appAppServiceName published at $appUrl"
}
function ImportDatabase (
    [parameter(Mandatory=$true)][string]$SqlDatabaseName,
    [parameter(Mandatory=$false)][string]$SqlServer=$SqlServerFQDN.Split(".")[0],
    [parameter(Mandatory=$true)][string]$SqlServerFQDN,
    [parameter(Mandatory=$true)][string]$ResourceGroup,
    [parameter(Mandatory=$true)][string]$MSIName,
    [parameter(Mandatory=$true)][string]$MSIClientId,
    [parameter(Mandatory=$true)][string]$UserName,
    [parameter(Mandatory=$true)][SecureString]$SecurePassword
) {
    if ([string]::IsNullOrEmpty($SqlServerFQDN)) {
        Write-Error "No SQL Server specified" -ForeGroundColor Red
        return 
    }
    $sqlQueryFile = "check-database-contents.sql"
    $sqlFWRuleName = "AllowAllWindowsAzureIPs"
    # This is no secret
    $storageSAS = "?st=2020-03-20T13%3A57%3A32Z&se=2023-04-12T13%3A57%3A00Z&sp=r&sv=2018-03-28&sr=c&sig=qGpAjJlpDQsq2SB6ev27VbwOtgCwh2qu2l3G8kYX4rU%3D"
    $storageUrl = "https://ewimages.blob.core.windows.net/databasetemplates/vdcdevpaasappsqldb-2020-1-18-15-13.bacpac"
    $userName = "vdcadmin"
 
    # https://aka.ms/azuresqlconnectivitysettings
    # Enable Public Network Access
    $sqlPublicNetworkAccess = $(az sql server show -n $SqlServer -g $ResourceGroup --query "publicNetworkAccess" -o tsv)
    Write-Information "Enabling Public Network Access for ${SqlServer} ..."
    Write-Verbose "az sql server update -n $SqlServer -g $ResourceGroup --set publicNetworkAccess=`"Enabled`" --query `"publicNetworkAccess`""
    az sql server update -n $SqlServer -g $ResourceGroup --set publicNetworkAccess="Enabled" --query "publicNetworkAccess" -o tsv

    # Create SQL Firewall rule for query
    $ipAddress=$(Invoke-RestMethod -Uri https://ipinfo.io/ip -MaximumRetryCount 9).Trim()
    az sql server firewall-rule create -g $ResourceGroup -s $SqlServer -n "ImportQuery $ipAddress" --start-ip-address $ipAddress --end-ip-address $ipAddress -o none

    # Create SQL Firewall rule for import
    $allAzureRuleIDs = $(az sql server firewall-rule list -g $ResourceGroup -s $SqlServer --query "[?startIpAddress=='0.0.0.0'].id" -o tsv)
    if (!$allAzureRuleIDs) {
        Write-Information "Creating SQL Server ${SqlServer} Firewall rule '${sqlFWRuleName}' ..."
        $sqlFWRule = $(az sql server firewall-rule create -g $ResourceGroup -s $SqlServer -n $sqlFWRuleName --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0)
    } else {
        Write-Verbose "SQL Server ${SqlServer} Firewall rule $sqlFWRuleName already exists"
    }

    # Check whether we need to import
    $schemaExists = Execute-Sql -QueryFile $sqlQueryFile -SqlDatabaseName $SqlDatabaseName -SqlServerFQDN $SqlServerFQDN -UserName $UserName -SecurePassword $SecurePassword

    if ($schemaExists -eq 0) {
        Write-Host "Database ${SqlServer}/${SqlDatabaseName} is empty"
  
        # Perform import
        Write-Information "Database ${SqlServer}/${SqlDatabaseName}: importing from ${storageUrl} ..."
        $password = ConvertFrom-SecureString $SecurePassword -AsPlainText
        #az sql db import -s $SqlServer -n $SqlDatabaseName -g $ResourceGroup -p $password -u $UserName --storage-key-type SharedAccessKey --storage-uri $storageUrl --storage-key "${storageSAS}"
        az sql db import -s $SqlServer -n $SqlDatabaseName -g $ResourceGroup -p $password -u $UserName --storage-key-type SharedAccessKey --storage-uri $storageUrl --storage-key --% "?st=2020-03-20T13%3A57%3A32Z&se=2023-04-12T13%3A57%3A00Z&sp=r&sv=2018-03-28&sr=c&sig=qGpAjJlpDQsq2SB6ev27VbwOtgCwh2qu2l3G8kYX4rU%3D"
    } else {
        Write-Host "Database ${SqlServer}/${SqlDatabaseName} is not empty, skipping import"
    }

    # Fix permissions on database, so App Service MSI and DBA (e.g. current user) have access
    # Try to fetch user we grant access to (import hase erased database level users)
    if (!($DBAName) -or !($DBAObjectId)) {
        if ($(az account show --query "user.type" -o tsv) -ieq "user") {
            $loggedInUser = (az ad signed-in-user show --query "{ObjectId:objectId,UserName:userPrincipalName}" | ConvertFrom-Json)
        }
        if ($loggedInUser) {
            $DBAName = $loggedInUser.UserName
            $DBAObjectId = $loggedInUser.ObjectId
        }
    }
    # Execute DB script
    if ($DBAName -and $DBAObjectId) {
        Write-Verbose "./grant_database_access.ps1 -DBAName $DBAName -DBAObjectId $DBAObjectId -MSIName $MSIName -MSIClientId $MSIClientId -SqlDatabaseName $SqlDatabaseName -SqlServerFQDN $SqlServerFQDN -UserName $UserName -SecurePassword $SecurePassword"
        ./grant_database_access.ps1 -DBAName $DBAName -DBAObjectId $DBAObjectId `
                                    -MSIName $MSIName -MSIClientId $MSIClientId `
                                    -SqlDatabaseName $SqlDatabaseName -SqlServerFQDN $SqlServerFQDN `
                                    -UserName $UserName -SecurePassword $SecurePassword
    } else {
        Write-Verbose "./grant_database_access.ps1 -MSIName $MSIName -MSIClientId $MSIClientId -SqlDatabaseName $SqlDatabaseName -SqlServerFQDN $SqlServerFQDN -UserName $UserName -SecurePassword $SecurePassword"
        ./grant_database_access.ps1 -MSIName $MSIName -MSIClientId $MSIClientId `
                                    -SqlDatabaseName $SqlDatabaseName -SqlServerFQDN $SqlServerFQDN `
                                    -UserName $UserName -SecurePassword $SecurePassword
    }


    # Reset Public Network Access to what it was before
    az sql server update -n $SqlServer -g $ResourceGroup --set publicNetworkAccess="$sqlPublicNetworkAccess" -o none

    if ($sqlPublicNetworkAccess -ieq "Disabled") {
        # Clean up all FW rules
        $sqlFWIds = $(az sql server firewall-rule list -g $ResourceGroup -s $SqlServer --query "[].id" -o tsv)
    } else {
        # Clean up just the all Azure rule
        $sqlFWIds = $(az sql server firewall-rule list -g $ResourceGroup -s $SqlServer --query "[?startIpAddress=='0.0.0.0'].id" -o tsv)
    }
    if ($sqlFWIds) {
        Write-Verbose "Removing SQL Server ${SqlServer} Firewall rules $sqlFWIds ..."
        az sql server firewall-rule delete --ids $sqlFWIds -o none
    }

}
function ResetDatabasePassword (
    [parameter(Mandatory=$false)][string]$SqlServer=$SqlServerFQDN.Split(".")[0],
    [parameter(Mandatory=$true)][string]$SqlServerFQDN,
    [parameter(Mandatory=$true)][string]$SqlDatabaseName,
    [parameter(Mandatory=$true)][string]$ResourceGroup
) {
    # Reset admin password
    Write-Information "Database ${SqlServer}/${SqlDatabaseName}: resetting admin password"
    $dbaPassword = New-Guid | Select-Object -ExpandProperty Guid
    az sql server update --admin-password $dbaPassword --resource-group $ResourceGroup --name $SqlServer -o none
    
    $securePassword = ConvertTo-SecureString $dbaPassword -AsPlainText -Force
    $securePassword.MakeReadOnly()
    return $securePassword
}
function RestartApp () {
    # HACK: Creating and removing a bogus IP Access Restriction sometime get's rid of 500.79 errors with AAD authentication
    #$ruleName = "Bogusrule"
    #Write-Information "Adding App Service '$appAppServiceName' Access Restriction '$ruleName'..."
    #az webapp config access-restriction add -p 999 -r $ruleName --ip-address 1.2.3.4/32 -g $appResourceGroup -n $appAppServiceName -o none
    $authEnabled = $(az webapp auth show -g $appResourceGroup -n $appAppServiceName --query "enabled" -o tsv)
    Write-Information "Authentication for App Service '$appAppServiceName' is set to '$authEnabled'"
    Write-Information "Disabling authentication for App Service '$appAppServiceName'..."
    az webapp auth update --enabled false -g $appResourceGroup -n $appAppServiceName -o none

    Write-Information "Restarting App Service '$appAppServiceName'..."
    az webapp restart -g $appResourceGroup -n $appAppServiceName 

    #Write-Information "Removing App Service '$appAppServiceName' Access Restriction '$ruleName'..."
    #az webapp config access-restriction remove -r $ruleName -g $appResourceGroup -n $appAppServiceName -o none
    Write-Information "Setting authentication for App Service '$appAppServiceName' to '$authEnabled'..."
    az webapp auth update --enabled $authEnabled -g $appResourceGroup -n $appAppServiceName -o none

    Write-Information "Restarting App Service '$appAppServiceName'..."
    az webapp restart -g $appResourceGroup -n $appAppServiceName 

    # Sleep to prevent false positive testing
    $appStartupWaitTime = 15
    Write-Host "Sleeping $appStartupWaitTime seconds for application to start up..."
    Start-Sleep -Seconds $appStartupWaitTime
}
function TestApp (
    [parameter(Mandatory=$true)][string]$AppUrl
) {
    $test = 0
    Write-Host "Testing $AppUrl (max $MaxTests times)" -NoNewLine
    while (!$responseOK -and ($test -lt $MaxTests)) {
        try {
            $test++
            Write-Host "." -NoNewLine
            $homePageResponse = Invoke-WebRequest -UseBasicParsing -Uri $AppUrl
            if ($homePageResponse.StatusCode -lt 400) {
                $responseOK = $true
            } else {
                $responseOK = $false
            }
        }
        catch {
            $responseOK = $false
            if ($test -ge $MaxTests) {
                throw
            } else {
                Start-Sleep -Milliseconds 500
            }
        }
    }
    Write-Host "✓" # Force NewLine
    Write-Host "Request to $AppUrl completed with HTTP Status Code $($homePageResponse.StatusCode)"
}

# Provide at least one argument
if (!($All -or $Database -or $Website -or $Restart -or $Test)) {
    Write-Host "Please indicate what to do by using a command-line switch"
    Get-Help $MyInvocation.MyCommand.Definition
    exit
}

. (Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) functions.ps1)


if (($All -or $Database) -and (!$SqlDatabase -or !$SqlServerFQDN -or !$AppResourceGroup -or !$SqlDatabase -or !$AppAppServiceIdentity -or !$AppAppServiceClientID)) {
    $useTerraform = $true
}
if (($All -or $Website) -and (!$AppUrl -or !$DevOpsOrgUrl -or !$DevOpsProject -or !$AppAppServiceName -or !$AppResourceGroup)) {
    $useTerraform = $true
}
if (($All -or $Restart) -and (!$AppUrl -or !$AppAppServiceName -or !$AppResourceGroup)) {
    $useTerraform = $true
}
if (($All -or $Test) -and !$AppUrl) {
    $useTerraform = $true
}
if ($useTerraform) {
    # Gather data from Terraform
    try {
        Push-Location $tfdirectory
        . (Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) get_tf_version.ps1) -ValidateInstalledVersion
        $priorWorkspace = (SetWorkspace -Workspace $Workspace -ShowWorkspaceName).PriorWorkspaceName
        
        Invoke-Command -ScriptBlock {
            $Private:ErrorActionPreference = "Continue"

            # Set only if not null
            $script:AppResourceGroup       ??= (GetTerraformOutput "paas_app_resource_group")
            $script:AppAppServiceName      ??= (GetTerraformOutput "paas_app_service_name")

            $script:AppAppServiceIdentity  ??= (GetTerraformOutput "paas_app_service_msi_name")
            $script:AppAppServiceClientID  ??= (GetTerraformOutput "paas_app_service_msi_client_id")

            $script:DBAName                ??= (GetTerraformOutput "admin_login")
            $script:DBAObjectId            ??= (GetTerraformOutput "admin_object_id")

            $script:AppUrl                 ??= (GetTerraformOutput "paas_app_url")
            $script:DevOpsOrgUrl           ??= (GetTerraformOutput "devops_org_url")
            $script:DevOpsProject          ??= (GetTerraformOutput "devops_project")
            $script:SqlServer              ??= (GetTerraformOutput "paas_app_sql_server")
            $script:SqlServerFQDN          ??= (GetTerraformOutput "paas_app_sql_server_fqdn")
            $script:SqlDatabase            ??= (GetTerraformOutput "paas_app_sql_database")
        }

        if ([string]::IsNullOrEmpty($AppAppServiceName)) {
            Write-Host "App Service has not been created, nothing to do deploy to" -ForeGroundColor Yellow
            exit 
        }
    } finally {
        $null = SetWorkspace -Workspace $priorWorkspace
        Pop-Location
    }
}

if ($All -or $Database) {
    # We don't rely on AAD here as that would require a pre-existing AAD Security Group, 
    #  with both Automation Service Principal and user, to be assigbned as SQL Server AAD Admin
    # Create temporary Database admin password
    $adminPassword = ResetDatabasePassword -SqlDatabaseName $SqlDatabase -SqlServerFQDN $SqlServerFQDN -ResourceGroup $AppResourceGroup
    if ([string]::IsNullOrEmpty($adminPassword)) {
        Write-Error "Unable to create temporary password" -ForeGroundColor Red
        exit 
    }
    $adminUser = "vdcadmin"

    # Import Database
    ImportDatabase -SqlDatabaseName $SqlDatabase -SqlServer $SqlServer -SqlServerFQDN $SqlServerFQDN `
                   -UserName $adminUser -SecurePassword $adminPassword -ResourceGroup $AppResourceGroup `
                   -MSIName $AppAppServiceIdentity -MSIClientId $AppAppServiceClientID
}

if ($All -or $Website) {
    # Deploy Web App
    DeployContainerWebApp
}
if ($All -or $Restart -or $Website) {
    # Deploy Web App
    RestartApp
}
if ($All -or $Restart -or $Test -or $Website) {
    # Test & Warm up 
    TestApp -AppUrl $AppUrl 
}