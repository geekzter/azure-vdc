#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    Deploys Web App ASP.NET artifacts
 
.DESCRIPTION 
    This scripts pulls a pre-created ZipDeploy package from Pipeline artifacts and publishes it to the App Service Web App.
    It eliminates the need for a release pipeline just to test the Web App.
#> 
param (    
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
    $sqlQueryFile = "check-database-contents.sql"
    $sqlFWRuleName = "AllowAllWindowsAzureIPs"
    # This is no secret
    $storageSAS = "?st=2020-03-20T13%3A57%3A32Z&se=2023-04-12T13%3A57%3A00Z&sp=r&sv=2018-03-28&sr=c&sig=qGpAjJlpDQsq2SB6ev27VbwOtgCwh2qu2l3G8kYX4rU%3D"
    $storageUrl = "https://ewimages.blob.core.windows.net/databasetemplates/vdcdevpaasappsqldb-2020-1-18-15-13.bacpac"
    $userName = "vdcadmin"

    # Check whether we need to import
    $schemaExists = Execute-Sql -QueryFile $sqlQueryFile -SqlDatabaseName $SqlDatabaseName -SqlServerFQDN $SqlServerFQDN -UserName $UserName -SecurePassword $SecurePassword

    # Create SQL Firewall rule for import
    $sqlFWRule = $(az sql server firewall-rule show -g $ResourceGroup -s $SqlServer -n $sqlFWRuleName 2>$null)
    if (!$sqlFWRule) {
        Write-Information "Creating SQL Server ${SqlServer} Firewall rule '${sqlFWRuleName}' ..."
        $sqlFWRule = $(az sql server firewall-rule create -g $ResourceGroup -s $SqlServer -n $sqlFWRuleName --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0)
    } else {
        Write-Verbose "SQL Server ${SqlServer} Firewall rule $sqlFWRuleName already exists"
    }

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

. (Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) functions.ps1)

# Gather data from Terraform
try {
    Push-Location $tfdirectory
    $priorWorkspace = (SetWorkspace -Workspace $Workspace -ShowWorkspaceName).PriorWorkspaceName
    
    Invoke-Command -ScriptBlock {
        $Private:ErrorActionPreference = "Continue"
        $Script:appResourceGroup       = $(terraform output "paas_app_resource_group"        2>$null)
        $Script:appAppServiceName      = $(terraform output "paas_app_service_name"          2>$null)

        $Script:appAppServiceIdentity  = $(terraform output "paas_app_service_msi_name"      2>$null)
        $Script:appAppServiceClientID  = $(terraform output "paas_app_service_msi_client_id" 2>$null)

        $Script:appUrl                 = $(terraform output "paas_app_url"                   2>$null)
        $Script:devOpsOrgUrl           = $(terraform output "devops_org_url"                 2>$null)
        $Script:devOpsProject          = $(terraform output "devops_project"                 2>$null)
        $Script:sqlServer              = $(terraform output "paas_app_sql_server"            2>$null)
        $Script:sqlServerFQDN          = $(terraform output "paas_app_sql_server_fqdn"       2>$null)
        $Script:sqlDatabase            = $(terraform output "paas_app_sql_database"          2>$null)
    }

    if ([string]::IsNullOrEmpty($appAppServiceName)) {
        Write-Host "App Service has not been created, nothing to do deploy to" -ForeGroundColor Yellow
        exit 
    }
} finally {
    $null = SetWorkspace -Workspace $priorWorkspace
    Pop-Location
}

# We don't rely on AAD here as that would require a pre-existing AAD Security Group, 
#  with both Automation Service Principal and user, to be assigbned as SQL Server AAD Admin
# Create temporary Database admin password
$adminPassword = ResetDatabasePassword -SqlDatabaseName $sqlDatabase -SqlServerFQDN $sqlServerFQDN -ResourceGroup $appResourceGroup
$adminUser = "vdcadmin"

# Import Database
ImportDatabase -SqlDatabaseName $sqlDatabase -SqlServer $sqlServer -SqlServerFQDN $sqlServerFQDN `
               -UserName $adminUser -SecurePassword $adminPassword -ResourceGroup $appResourceGroup `
               -MSIName $appAppServiceIdentity -MSIClientId $appAppServiceClientID

# Deploy Web App
DeployWebApp

# Test & Warm up 
TestApp -AppUrl $appUrl 