#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    Creates allow rules for PaaS firewalls for the current connection. This connections are required for Terraform to function.
 
.DESCRIPTION 
    This script is invoked from other scripts
#> 
param () 

. (Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) functions.ps1)


# Retrieve Azure resources config using Terraform
try {
    Push-Location $tfdirectory
    if ($MyInvocation.InvocationName -ne "&") {
        Write-Host "Using Terraform workspace '$(terraform workspace show)'" 
    }
    
    Invoke-Command -ScriptBlock {
        $Private:ErrorActionPreference = "Continue"
        $Script:appResourceGroup       = $(terraform output "paas_app_resource_group"       2>$null)
        $Script:appStorageAccount      = $(terraform output "paas_app_storage_account_name" 2>$null)
        $Script:appEventHubNamespace   = $(terraform output "paas_app_eventhub_namespace"   2>$null)
        $Script:appSQLServer           = $(terraform output "paas_app_sql_server"           2>$null)
        

        $Script:appRGExists = (![string]::IsNullOrEmpty($appResourceGroup) -and ($null -ne $(Get-AzResourceGroup -Name $appResourceGroup -ErrorAction "SilentlyContinue")))
    }

    if (!$appRGExists -or ([string]::IsNullOrEmpty($appStorageAccount) -and [string]::IsNullOrEmpty($appEventHubNamespace))) {
        Write-Host "Resources have not yet been created, nothing to do"
        exit 
    }
} finally {
    Pop-Location
}

# Get public IP address
# Use RIPE for both Ipv4 & Ipv6
#$ipAddress=$(Invoke-RestMethod https://stat.ripe.net/data/whats-my-ip/data.json | Select-Object -ExpandProperty data | Select-Object -ExpandProperty ip)
# Stick to ipinfo for Ipv4 only
$ipAddress=$(Invoke-RestMethod https://ipinfo.io/ip).Trim()
Write-Host "Public IP address is $ipAddress"

# Get block(s) the public IP address belongs to
# HACK: We need this to cater for changing public IP addresses e.g. Azure Pipelines Hosted Agents
$ipPrefix = Invoke-RestMethod https://stat.ripe.net/data/network-info/data.json?resource=${ipAddress} | Select-Object -ExpandProperty data | Select-Object -ExpandProperty prefix
Write-Host "Public IP prefix is $ipPrefix"

# Punch hole in PaaS Firewalls
if ($appStorageAccount) {
    Write-Host "Adding rule for storage account $appStorageAccount to allow address $ipAddress..."
    az storage account network-rule add -g $appResourceGroup --account-name $appStorageAccount --ip-address $ipAddress -o tsv
    Write-Host "Adding rule for storage account $appStorageAccount to allow prefix $ipPrefix..."
    az storage account network-rule add -g $appResourceGroup --account-name $appStorageAccount --ip-address $ipPrefix -o tsv
}
if ($appEventHubNamespace) {
    Write-Host "Adding rule for event hub $appEventHubNamespace to allow address $ipAddress..."
    az eventhubs namespace network-rule add -g $appResourceGroup --namespace-name $appEventHubNamespace --ip-address $ipAddress --action Allow -o tsv
    Write-Host "Adding rule for event hub $appEventHubNamespace to allow prefix $ipPrefix..."
    az eventhubs namespace network-rule add -g $appResourceGroup --namespace-name $appEventHubNamespace --ip-address $ipPrefix --action Allow -o tsv
}
if ($appSQLServer) {
    Write-Host "Adding rule for SQL Server $appSQLServer to allow address $ipAddress... "
    az sql server firewall-rule create -g $appResourceGroup -s $appSQLServer -n "LetMeInRule $ipAddress" --start-ip-address $ipAddress --end-ip-address $ipAddress -o tsv
}