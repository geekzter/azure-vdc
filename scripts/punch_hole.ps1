#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    Creates allow rules for PaaS firewalls for the current connection. This connections are required for Terraform to function.
 
.DESCRIPTION 
    This script is invoked from other scripts
#> 
#Requires -Version 7

param (
    [parameter(Mandatory=$false)][switch]$UsePreviewApis=([string]::IsNullOrEmpty($env:AGENT_VERSION)) # Use API's that use stderr for support notices
) 

. (Join-Path $PSScriptRoot functions.ps1)


# Retrieve Azure resources config using Terraform
try {
    Push-Location $tfdirectory
    if ($MyInvocation.InvocationName -ne "&") {
        Write-Host "Using Terraform workspace '$(terraform workspace show)'" 
    }
    
    Invoke-Command -ScriptBlock {
        Write-Information "Gathering Terraform output..."
        $Private:ErrorActionPreference    = "SilentlyContinue"
        $Script:appResourceGroup          = (GetTerraformOutput "paas_app_resource_group")
        $Script:appService                = (GetTerraformOutput "paas_app_service_name")
        $Script:appStorageAccount         = (GetTerraformOutput "paas_app_storage_account_name")
        $Script:appEventHubStorageAccount = (GetTerraformOutput "paas_app_eventhub_storage_account_name")
        $Script:appEventHubNamespace      = (GetTerraformOutput "paas_app_eventhub_namespace")
        $Script:appSQLServer              = (GetTerraformOutput "paas_app_sql_server")
        $Script:automationStorageAccount  = (GetTerraformOutput "automation_storage_account_name")
        $Script:keyVault                  = (GetTerraformOutput "key_vault_name")
        $Script:vdcDiagnosticsStorage     = (GetTerraformOutput "vdc_diag_storage")
        $Script:vdcResourceGroup          = (GetTerraformOutput "vdc_resource_group")

        $Script:appRGExists = (![string]::IsNullOrEmpty($appResourceGroup) -and ($null -ne $(az group list --query "[?name=='$appResourceGroup']")))

        if ($VerbosePreference -ine "SilentlyContinue") {
            terraform output 2>$null
        }
    }

    Write-Verbose "az group list --query `"[?name==`'`$appResourceGroup`']`":"
    if ($VerbosePreference -ine "SilentlyContinue") {
        az group list --query "[?name=='$appResourceGroup']"
    }
    Write-Verbose "`$appResourceGroup: $appResourceGroup"
    Write-Verbose "`$appRGExists: $appRGExists"
    Write-Verbose "`$appStorageAccount: $appStorageAccount"
    Write-Verbose "`$appEventHubNamespace: $appEventHubNamespace"

    if (!$appRGExists -or ([string]::IsNullOrEmpty($appStorageAccount) -and [string]::IsNullOrEmpty($appEventHubNamespace))) {
        Write-Host "Resources have not yet been created, nothing to do"
        exit 
    } else {
        Write-Information "Resources exist"
    }
} finally {
    Pop-Location
}

# Get public IP address
# Use RIPE for both Ipv4 & Ipv6
#$ipAddress=$(Invoke-RestMethod https://stat.ripe.net/data/whats-my-ip/data.json -MaximumRetryCount 9 | Select-Object -ExpandProperty data | Select-Object -ExpandProperty ip)
# Stick to ipinfo for Ipv4 only
$ipAddress=$(Invoke-RestMethod -Uri https://ipinfo.io/ip -MaximumRetryCount 9).Trim()
Write-Host "Public IP address is $ipAddress"

# Get block(s) the public IP address belongs to
# HACK: We need this to cater for changing public IP addresses e.g. Azure Pipelines Hosted Agents
$ipPrefix = Invoke-RestMethod -Uri https://stat.ripe.net/data/network-info/data.json?resource=${ipAddress} -MaximumRetryCount 9 | Select-Object -ExpandProperty data | Select-Object -ExpandProperty prefix
Write-Host "Public IP prefix is $ipPrefix"

# App Service Deployment Slot
if ($appService -and $UsePreviewApis) {
    Invoke-Command -ScriptBlock {
        $Private:ErrorActionPreference = "Continue"
        Write-Debug "App Service $appService exist, checking whether prefix $ipPrefix is already allowed..."
        if (-not (az webapp config access-restriction show -s staging -n $appService -g $appResourceGroup --query "ipSecurityRestrictions[?ip_address=='$ipPrefix']" -o tsv 2>$null)) {
            Write-Host "Adding rule for App Service $appService deployment slot 'staging' to allow prefix $ipPrefix..."
            az webapp config access-restriction add -s staging -n $appService -g $appResourceGroup --ip-address $ipPrefix -r letmein -p 65000 -o none 2>&1
        } else {
            Write-Information "App Service $appService staging slot already allows access from prefix $ipPrefix"
        }
    }
}

# Punch hole in PaaS Firewalls
foreach ($storageAccount in @($appStorageAccount,$appEventHubStorageAccount)) {
    if ($storageAccount) {
        Write-Host "Adding rule for Storage Account $storageAccount to allow prefix $ipPrefix..."
        az storage account network-rule add -g $appResourceGroup --account-name $storageAccount --ip-address $ipPrefix -o none
        # BUG: If a pipeline agent or VS Codespace is located in the same region as a storage account the request will be routed over Microsoft’s internal IPv6 network. As a result the source IP of the request is not the same as the one added to the Storage Account firewall.
        # 1.0;2020-05-17T13:22:59.2714021Z;GetContainerProperties;IpAuthorizationError;403;4;4;authenticated;xxxxxx;xxxxxx;blob;"https://xxxxxx.blob.core.windows.net:443/paasappscripts?restype=container";"/";75343457-f01e-005c-674e-2c705c000000;0;172.16.5.4:59722;2018-11-09;453;0;130;246;0;;;;;;"Go/go1.14.2 (amd64-linux) go-autorest/v14.0.0 tombuildsstuff/giovanni/v0.10.0 storage/2018-11-09";;
        # HACK: Open the door, Terraform will close it again
        az storage account update -g $appResourceGroup -n $storageAccount --default-action Allow -o none
    }
}
foreach ($storageAccount in @($automationStorageAccount,$vdcDiagnosticsStorage)) {
    if ($storageAccount) {
        Write-Host "Adding rule for Storage Account $storageAccount to allow prefix $ipPrefix..."
        az storage account network-rule add -g $vdcResourceGroup --account-name $storageAccount --ip-address $ipPrefix -o none
        # BUG: If a pipeline agent or VS Codespace is located in the same region as a storage account the request will be routed over Microsoft’s internal IPv6 network. As a result the source IP of the request is not the same as the one added to the Storage Account firewall.
        # 1.0;2020-05-17T13:22:59.2714021Z;GetContainerProperties;IpAuthorizationError;403;4;4;authenticated;xxxxxx;xxxxxx;blob;"https://xxxxxx.blob.core.windows.net:443/paasappscripts?restype=container";"/";75343457-f01e-005c-674e-2c705c000000;0;172.16.5.4:59722;2018-11-09;453;0;130;246;0;;;;;;"Go/go1.14.2 (amd64-linux) go-autorest/v14.0.0 tombuildsstuff/giovanni/v0.10.0 storage/2018-11-09";;
        # HACK: Open the door, Terraform will close it again
        az storage account update -g $vdcResourceGroup -n $storageAccount --default-action Allow -o none
    }
}

if ($appEventHubNamespace) {
    Write-Host "Adding rule for Event Hub $appEventHubNamespace to allow prefix $ipPrefix..."
    az eventhubs namespace network-rule add -g $appResourceGroup --namespace-name $appEventHubNamespace --ip-address $ipPrefix --action Allow -o none
}

# if ($appSQLServer) {
#     Write-Host "Adding rule for SQL Server $appSQLServer to allow address $ipAddress... "
#     az sql server firewall-rule create -g $appResourceGroup -s $appSQLServer -n "PunchHole $ipAddress" --start-ip-address $ipAddress --end-ip-address $ipAddress -o none
# }
if ($keyVault) {
    if (az keyvault network-rule list -n $keyVault -g $vdcResourceGroup --query "ipRules[?value=='$ipPrefix'].value" -o tsv) {
        Write-Host "Rule for Key Vault $keyVault to allow prefix $ipPrefix already exists"
    } else {
        Write-Host "Adding rule for Key Vault $keyVault to allow prefix $ipPrefix..."
        az keyvault network-rule add -g $vdcResourceGroup -n $keyVault --ip-address $ipPrefix -o none
    }
}