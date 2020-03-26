#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    Deploys Web App ASP.NET artifacts
 
.DESCRIPTION 
    This scripts pulls a pre-created ZipDeploy package from Pipeline artifacts and publishes it to the App Service Web App.
    It eliminates the need for a release pipeline just to test the Web App.
#> 
param (    
    [parameter(Mandatory=$false)][switch]$Database,
    [parameter(Mandatory=$false)][switch]$Website,
    [parameter(Mandatory=$false)][switch]$All,

    # These parameters are either provided or their values retrieved from Terraform
    [parameter(Mandatory=$false)][object]$AppResourceGroup,
    [parameter(Mandatory=$false)][object]$AppAppServiceName=$null,
    [parameter(Mandatory=$false)][object]$AppAppServiceIdentity,
    [parameter(Mandatory=$false)][object]$AppAppServiceClientID,
    [parameter(Mandatory=$false)][object]$AppUrl,
    [parameter(Mandatory=$false)][object]$DevOpsOrgUrl,
    [parameter(Mandatory=$false)][object]$DevOpsProject,
    [parameter(Mandatory=$false)][object]$SqlServer,
    [parameter(Mandatory=$false)][object]$SqlServerFQDN,
    [parameter(Mandatory=$false)][object]$SqlDatabase,

    [parameter(Mandatory=$false,HelpMessage="The Terraform workspace to use")][string]$Workspace=$env:TF_WORKSPACE,
    [parameter(Mandatory=$false)][int]$MaxTests=60,
    [parameter(Mandatory=$false)][string]$subscription=$env:ARM_SUBSCRIPTION_ID,
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "Terraform")
) 

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
    $dotnetVersion = "2.2"

    # We need this for Azure DevOps
    az extension add --name azure-devops 

    # Set defaults
    az account set --subscription $subscription
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
    $null = az webapp deployment source config-zip -g $appResourceGroup -n $appAppServiceName --src $packagePath

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

 

    # Create SQL Firewall rule for import
    Invoke-Command -ScriptBlock {
        $Private:ErrorActionPreference = "Continue"
        $Script:sqlFWRule = $(az sql server firewall-rule show -g $ResourceGroup -s $SqlServer -n $sqlFWRuleName 2>$null)
    }
    #$sqlFWRule = $(az sql server firewall-rule show -g $ResourceGroup -s $SqlServer -n $sqlFWRuleName 2>$null)
    if (!$sqlFWRule) {
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
        az sql db import -s $SqlServer -n $SqlDatabaseName -g $ResourceGroup -p $password -u $UserName --storage-key $storageSAS `
        --storage-key-type SharedAccessKey `
        --storage-uri $storageUrl

    } else {
        Write-Host "Database ${SqlServer}/${SqlDatabaseName} is not empty, skipping import"
    }

    # Fix permissions on database, so App Service MSI has access
    Write-Verbose "./grant_database_access.ps1 -MSIName $MSIName -MSIClientId $MSIClientId -SqlDatabaseName $SqlDatabaseName -SqlServerFQDN $SqlServerFQDN -UserName $UserName -SecurePassword $SecurePassword"
    ./grant_database_access.ps1 -MSIName $MSIName -MSIClientId $MSIClientId `
                                -SqlDatabaseName $SqlDatabaseName -SqlServerFQDN $SqlServerFQDN `
                                -UserName $UserName -SecurePassword $SecurePassword

    if (!$sqlFWRule) {
        # Remove SQL Firewall rule
        Write-Verbose "Removing SQL Server ${SqlServer} Firewall rule $sqlFWRuleName ..."
        az sql server firewall-rule delete -g $appResourceGroup -s $SqlServer -n $sqlFWRuleName
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
    $null = az sql server update --admin-password $dbaPassword --resource-group $ResourceGroup --name $SqlServer 
    
    $securePassword = ConvertTo-SecureString $dbaPassword -AsPlainText -Force
    $securePassword.MakeReadOnly()
    return $securePassword
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
if (!($All -or $Database -or $Website)) {
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
if ($useTerraform) {
    # Gather data from Terraform
    try {
        Push-Location $tfdirectory
        $priorWorkspace = (SetWorkspace -Workspace $Workspace -ShowWorkspaceName).PriorWorkspaceName
        
        Invoke-Command -ScriptBlock {
            $Private:ErrorActionPreference = "Continue"

            # Set only if not null
            $script:AppResourceGroup       ??= $(terraform output "paas_app_resource_group"        2>$null)
            $script:AppAppServiceName      ??= $(terraform output "paas_app_service_name"          2>$null)

            $script:AppAppServiceIdentity  ??= $(terraform output "paas_app_service_msi_name"      2>$null)
            $script:AppAppServiceClientID  ??= $(terraform output "paas_app_service_msi_client_id" 2>$null)

            $script:AppUrl                 ??= $(terraform output "paas_app_url"                   2>$null)
            $script:DevOpsOrgUrl           ??= $(terraform output "devops_org_url"                 2>$null)
            $script:DevOpsProject          ??= $(terraform output "devops_project"                 2>$null)
            $script:SqlServer              ??= $(terraform output "paas_app_sql_server"            2>$null)
            $script:SqlServerFQDN          ??= $(terraform output "paas_app_sql_server_fqdn"       2>$null)
            $script:SqlDatabase            ??= $(terraform output "paas_app_sql_database"          2>$null)
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
    DeployWebApp

    # Test & Warm up 
    TestApp -AppUrl $AppUrl 
}