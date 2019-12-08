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

### Internal Functions
. (Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) functions.ps1)

$Script:ErrorActionPreference = "Stop"
if(-not($subscription)) { Throw "You must supply a value for subscription" }

# Log on to Azure if not already logged on
AzLogin

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
  Write-Host "Found Virtual Network '$($virtualNetwork.Name)'"
} else {
  Write-Error "Virtual Network '$paasNetworkName' not found"
  exit 1
}

$subnet = $virtualNetwork | Select-Object -ExpandProperty subnets | Where-Object {$_.Name -eq $endpointSubnet}  
if ($subnet -and ![string]::IsNullOrEmpty($subnet)) {
  Write-Host "Found Subnet '$($subnet.Name)'"
} else {
  Write-Error "Subnet '$endpointSubnet' not found in Virtual Network ${virtualNetwork.Name}"
  exit 2
}

# Disable network policies, should not be needed at GA
if ($subnet.PrivateEndpointNetworkPolicies -ine "Disabled") {
  $subnet.PrivateEndpointNetworkPolicies = "Disabled"
  $virtualNetwork | Set-AzVirtualNetwork
}
 
Write-Host "Creating Private Link Connection '$sqlDBPrivateLinkServiceConnectionName'..."
$privateEndpointConnection = New-AzPrivateLinkServiceConnection -Name "$sqlDBPrivateLinkServiceConnectionName" `
  -PrivateLinkServiceId $appSqlServerId `
  -GroupId "sqlServer" 
if ($privateEndpointConnection) {
  Write-Host "Created Private Link Connection '$($privateEndpointConnection.Name)'"
} else {
  Write-Error "Private Endpoint connection for '$appSqlServerId' is null"
  exit 3
}

Write-Host "Creating Private EndPoint '$sqlDBPrivateEndpointName'..."
$privateEndpoint = New-AzPrivateEndpoint -ResourceGroupName $appResourceGroup `
  -Name $sqlDBPrivateEndpointName `
  -Location $location `
  -Subnet $subnet `
  -PrivateLinkServiceConnection $privateEndpointConnection `
  -Force
if ($privateEndpoint) {
  Write-Host "Created Private EndPoint '$($privateEndpoint.Name)'"
} else {
  Write-Error "Private Endpoint is null"
  exit 4
}

$privateEndpoint = Get-AzPrivateEndpoint -Name $sqlDBPrivateEndpointName -ResourceGroupName $appResourceGroup
$networkInterface = Get-AzResource -ResourceId $privateEndpoint.NetworkInterfaces[0].Id -ApiVersion "2019-04-01" 
 
foreach ($ipconfig in $networkInterface.properties.ipConfigurations) { 
  foreach ($fqdn in $ipconfig.properties.privateLinkConnectionProperties.fqdns) { 
    $recordName = $fqdn.split('.',2)[0] 
    $dnsZone = $fqdn.split('.',2)[1] 
    Write-Host "Creating Private DNS A record $fqdn -> $($ipconfig.properties.privateIPAddress)..."
    $dnsRecord = New-AzPrivateDnsRecordSet -Name $recordName -RecordType A -ZoneName "privatelink.database.windows.net" `
      -ResourceGroupName $vdcResourceGroup -Ttl 600 `
      -PrivateDnsRecords (New-AzPrivateDnsRecordConfig -IPv4Address $ipconfig.properties.privateIPAddress) `
      -Overwrite
    Write-Host "Created Private DNS A record $($dnsRecord.Name).$($dnsRecord.ZoneName) -> $($dnsRecord.Records[0])"
  } 
} 