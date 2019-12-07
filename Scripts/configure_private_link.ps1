#!/usr/bin/env pwsh

<# 
.SYNOPSIS 
    Creates Private Endpoints for PaaS services (SQLDB, Storage)
 
.DESCRIPTION 
    This is a temporary workaround until private link is supported by Terraform
    As some API's are in beta and not always working, it is also a mix of Azure PowerShell and Azure CLI
#> 

param (    
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "Terraform"),
    [parameter(Mandatory=$false)][string]$subscription=$env:ARM_SUBSCRIPTION_ID,
    [parameter(Mandatory=$false)][string]$tenantid=$env:ARM_TENANT_ID,
    [parameter(Mandatory=$false)][string]$clientid=$env:ARM_CLIENT_ID,
    [parameter(Mandatory=$false)][string]$clientsecret=$env:ARM_CLIENT_SECRET
) 
$Script:ErrorActionPreference = "Stop"
if(-not($subscription)) { Throw "You must supply a value for subscription" }

# Log on to Azure if not already logged on
if (!(Get-AzTenant -TenantId $tenantid -ErrorAction SilentlyContinue)) {
    Write-Host "Reconnecting to Azure with SPN..."
    if(-not($tenantid)) { Throw "You must supply a value for tenantid" }
    if(-not($clientid)) { Throw "You must supply a value for clientid" }
    if(-not($clientsecret)) { Throw "You must supply a value for clientsecret" }
    # Use Terraform ARM Backend config to authenticate to Azure
    $secureClientSecret = ConvertTo-SecureString $clientsecret -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential ($clientid, $secureClientSecret)
    $null = Connect-AzAccount -Tenant $tenantid -Subscription $subscription -ServicePrincipal -Credential $credential
}
$null = Set-AzContext -Subscription $subscription

# Retrieve Azure resources config using Terraform
try {
    Push-Location $tfdirectory

    Invoke-Command -ScriptBlock {
        $Private:ErrorActionPreference = "Continue"
        $Script:appResourceGroup       = $(terraform output "paas_app_resource_group"       2>$null)
        if ([string]::IsNullOrEmpty($appResourceGroup)) {
          throw "Terraform output paas_app_resource_group is empty"
        }
        $Script:appEventHubNamespace   = $(terraform output "paas_app_eventhub_namespace"   2>$null)
        if ([string]::IsNullOrEmpty($appEventHubNamespace)) {
          throw "Terraform output paas_app_eventhub_namespace is empty"
        }
        $Script:appSqlServer           = $(terraform output "paas_app_sql_server"           2>$null)
        if ([string]::IsNullOrEmpty($appSqlServer)) {
          throw"Terraform output paas_app_sql_server is empty"
        }
        $Script:appSqlServerId         = $(terraform output "paas_app_sql_server_id"        2>$null)
        if ([string]::IsNullOrEmpty($appSqlServerId)) {
          throw "Terraform output paas_app_sql_server_id is empty"
        }
        $Script:appStorageAccount      = $(terraform output "paas_app_storage_account_name" 2>$null)
        if ([string]::IsNullOrEmpty($appStorageAccount)) {
          throw "Terraform output paas_app_storage_account_name is empty"
        }
        $Script:location               = $(terraform output "location"                      2>$null)
        if ([string]::IsNullOrEmpty($location)) {
          throw "Terraform output location is empty"
        }
        $Script:paasNetworkName        = $(terraform output "paas_vnet_name"                2>$null)
        if ([string]::IsNullOrEmpty($paasNetworkName)) {
          throw "Terraform output paas_vnet_name is empty"
        }
        $Script:vdcResourceGroup       = $(terraform output "vdc_resource_group"            2>$null)
        if ([string]::IsNullOrEmpty($vdcResourceGroup)) {
          throw "Terraform output vdc_resource_group is empty"
        }
    }

} finally {
    Pop-Location
}

$sqlDBPrivateLinkServiceConnectionName = "${appSqlServer}-endpoint-connection"
Write-Host "SQL DB Private Link Service connection will be named '$sqlDBPrivateLinkServiceConnectionName'"
$sqlDBPrivateEndpointName = "${appSqlServer}-endpoint"
Write-Host "SQL DB Private Endpoint will be named '$sqlDBPrivateEndpointName'"
$endpointSubnet = "data"

# Source: https://docs.microsoft.com/en-us/azure/private-link/create-private-endpoint-powershell

$virtualNetwork = Get-AzVirtualNetwork -ResourceGroupName $vdcResourceGroup -Name $paasNetworkName
if ($virtualNetwork) {
  $virtualNetwork
} else {
  Write-Error "Virtual Network $paasNetworkName not found"
}

$subnet = $virtualNetwork `
  | Select-Object -ExpandProperty subnets `
  | Where-Object  {$_.Name -eq $endpointSubnet}  
if ($subnet -and ![string]::IsNullOrEmpty($subnet)) {
  $subnet
} else {
  Write-Error "Subnet '$endpointSubnet' not found in Virtual Network ${virtualNetwork.Name}"
}

# Disable network policies, should not be needed at GA
if ($subnet.PrivateEndpointNetworkPolicies -ine "Disabled") {
  $subnet.PrivateEndpointNetworkPolicies = "Disabled"
  $virtualNetwork | Set-AzVirtualNetwork
}
 
$privateEndpointConnection = New-AzPrivateLinkServiceConnection -Name "$sqlDBPrivateLinkServiceConnectionName" `
  -PrivateLinkServiceId $appSqlServerId `
  -GroupId "sqlServer" 
if ($privateEndpointConnection) {
  $privateEndpointConnection
} else {
  Write-Error "Private Endpoint connection for '$appSqlServerId' is null"
}

$privateEndpoint = New-AzPrivateEndpoint -ResourceGroupName $vdcResourceGroup `
  -Name $sqlDBPrivateEndpointName `
  -Location $location `
  -Subnet $subnet `
  -PrivateLinkServiceConnection $privateEndpointConnection
if ($privateEndpoint) {
  $privateEndpoint
} else {
  Write-Error "Private Endpoint is null"
}

$privateEndpoint = Get-AzPrivateEndpoint -Name $sqlDBPrivateEndpointName -ResourceGroupName $vdcResourceGroup
$networkInterface = Get-AzResource -ResourceId $privateEndpoint.NetworkInterfaces[0].Id -ApiVersion "2019-04-01" 
 
foreach ($ipconfig in $networkInterface.properties.ipConfigurations) { 
  foreach ($fqdn in $ipconfig.properties.privateLinkConnectionProperties.fqdns) { 
    Write-Host "$($ipconfig.properties.privateIPAddress) $($fqdn)"  
    $recordName = $fqdn.split('.',2)[0] 
    $dnsZone = $fqdn.split('.',2)[1] 
    New-AzPrivateDnsRecordSet -Name $recordName -RecordType A -ZoneName "privatelink.database.windows.net" `
      -ResourceGroupName $vdcResourceGroup -Ttl 600 `
      -PrivateDnsRecords (New-AzPrivateDnsRecordConfig -IPv4Address $ipconfig.properties.privateIPAddress)  
  } 
} 