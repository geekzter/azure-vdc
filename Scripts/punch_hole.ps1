#!/usr/bin/env pwsh

param (    
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "Terraform"),
    [parameter(Mandatory=$false)][string]$subscription=$env:ARM_SUBSCRIPTION_ID,
    [parameter(Mandatory=$false)][string]$tenantid=$env:ARM_TENANT_ID,
    [parameter(Mandatory=$false)][string]$clientid=$env:ARM_CLIENT_ID,
    [parameter(Mandatory=$false)][string]$clientsecret=$env:ARM_CLIENT_SECRET
) 
if(-not($subscription)) { Throw "You must supply a value for subscription" }

. (Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) functions.ps1)

# Log on to Azure if not already logged on
AzLogin

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
    Write-Host "Adding rule for storage account $appStorageAccount to allow $ipAddress..."
    $rule = Add-AzStorageAccountNetworkRule -ResourceGroupName $appResourceGroup -Name $appStorageAccount -IPAddressOrRange "$ipAddress" -ErrorAction SilentlyContinue
    if ($rule) {
        $rule
        Write-Host "Added rule for storage account $appStorageAccount to allow $ipAddress"
    }
    Write-Host "Adding rule for storage account $appStorageAccount to allow $ipPrefix..."
    $rule = Add-AzStorageAccountNetworkRule -ResourceGroupName $appResourceGroup -Name $appStorageAccount -IPAddressOrRange "$ipPrefix" -ErrorAction SilentlyContinue
    if ($rule) {
        $rule
        Write-Host "Added rule for storage account $appStorageAccount to allow $ipPrefix"
    }
    Write-Host "Network Rules for ${appStorageAccount}:"
    Get-AzStorageAccountNetworkRuleSet -ResourceGroupName $appResourceGroup -Name $appStorageAccount | Select-Object -ExpandProperty IpRules | Sort-Object -Property IPAddressOrRange | Format-Table
}
if ($appEventHubNamespace) {
    Write-Host "Adding rule for event hub $appEventHubNamespace to allow $ipAddress..."
    $rule = Add-AzEventHubIPRule -ResourceGroupName $appResourceGroup -Name $appEventHubNamespace -IpMask "$ipAddress" -Action Allow -ErrorAction SilentlyContinue
    if ($rule) {
        $rule.IpRules
        Write-Host "Added rule for event hub $appEventHubNamespace to allow $ipAddress"
    }
}