#!/usr/bin/env pwsh

param (    
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "Terraform"),
    [parameter(Mandatory=$false)][string]$subscription=$env:ARM_SUBSCRIPTION_ID,
    [parameter(Mandatory=$false)][string]$tenantid=$env:ARM_TENANT_ID,
    [parameter(Mandatory=$false)][string]$clientid=$env:ARM_CLIENT_ID,
    [parameter(Mandatory=$false)][string]$clientsecret=$env:ARM_CLIENT_SECRET
) 
if(-not($subscription)) { Throw "You must supply a value for subscription" }

# Log on to Azure if not already logged on
if (!(Get-AzTenant -TenantId $tenantid -ErrorAction SilentlyContinue)) {
    if(-not($tenantid)) { Throw "You must supply a value for tenantid" }
    if(-not($clientid)) { Throw "You must supply a value for clientid" }
    if(-not($clientsecret)) { Throw "You must supply a value for clientsecret" }
    # Use Terraform ARM Backend config to authenticate Azure CLI
    $secureClientSecret = ConvertTo-SecureString $clientsecret -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential ($clientid, $secureClientSecret)
    Connect-AzAccount -Tenant $tenantid -Subscription $subscription -ServicePrincipal -Credential $credential
}
Set-AzContext -Subscription $subscription

# Retrieve Azure resources config using Terraform
try {
    Push-Location $tfdirectory

    Invoke-Command -ScriptBlock {
        $Private:ErrorActionPreference = "Continue"
        $Script:appResourceGroup       = $(terraform output "paas_app_resource_group"       2>$null)
        $Script:appStorageAccount      = $(terraform output "paas_app_storage_account_name" 2>$null)
        $Script:appEventHubNamespace   = $(terraform output "paas_app_eventhub_namespace"   2>$null)

        $Script:appRGExists = (![string]::IsNullOrEmpty($appResourceGroup) -and ($null -ne $(Get-AzResourceGroup -Name $appResourceGroup -ErrorAction "SilentlyContinue")))
    }

    if (!$appRGExists -or ([string]::IsNullOrEmpty($appStorageAccount) -and [string]::IsNullOrEmpty($appEventHubNamespace))) {
        Write-Output "Resources have not yet been created, nothing to do" 
        exit 
    }
} finally {
    Pop-Location
}

# Get public IP address
$ipAddress=$(Invoke-RestMethod http://ipinfo.io/json | Select-Object -exp ip)
Write-Host "Public IP address is $ipAddress"

# Punch hole in PaaS Firewalls
if ($appStorageAccount) {
    Add-AzStorageAccountNetworkRule -ResourceGroupName $appResourceGroup -Name $appStorageAccount -IPAddressOrRange "$ipAddress" -ErrorAction SilentlyContinue
    Write-Host "Network Rules for ${appStorageAccount}:"
    Get-AzStorageAccountNetworkRuleSet -ResourceGroupName $appResourceGroup -Name $appStorageAccount | Select-Object -ExpandProperty IpRules | Sort-Object -Property IPAddressOrRange | Format-Table
}
if ($appEventHubNamespace) {
    Add-AzEventHubIPRule -ResourceGroupName $appResourceGroup -Name $appEventHubNamespace -IpMask "$ipAddress" -Action Allow -ErrorAction SilentlyContinue
}