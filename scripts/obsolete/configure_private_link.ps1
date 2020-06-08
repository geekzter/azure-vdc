#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    Creates Private Endpoints for PaaS services (SQLDB, Storage)
 
.DESCRIPTION 
    This is a temporary workaround until private link is supported by Terraform
    As some API's are in beta and not always working, it is also a mix of Azure PowerShell and Azure CLI
#> 
#Requires -Version 7

param (    
    [parameter(Mandatory=$false)][string]$PrivateEndpointId,
    [parameter(Mandatory=$false)][string]$VDCResourceGroupName,
    [parameter(Mandatory=$false)][string]$Workspace=$env:TF_WORKSPACE,
    [parameter(Mandatory=$false)][string]$subscription=$env:ARM_SUBSCRIPTION_ID,
    [parameter(Mandatory=$false)][string]$tenantid=$env:ARM_TENANT_ID,
    [parameter(Mandatory=$false)][string]$clientid=$env:ARM_CLIENT_ID,
    [parameter(Mandatory=$false)][string]$clientsecret=$env:ARM_CLIENT_SECRET,
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "terraform")
) 

### Internal Functions
. (Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) functions.ps1)

$Script:ErrorActionPreference = "Stop"
if(-not($subscription)) { Throw "You must supply a value for subscription" }

# Log on to Azure if not already logged on
AzLogin

if (!$privateEndpointId) {
  # Retrieve Azure resources config using Terraform
  try {
    Push-Location $tfdirectory
    $priorWorkspace = (SetWorkspace -Workspace $Workspace -ShowWorkspaceName).PriorWorkspaceName

    Invoke-Command -ScriptBlock {
      $Private:ErrorActionPreference = "Continue"
      $Script:PrivateEndpointId      = $(terraform output "paas_app_sql_server_endpoint_id" 2>$null)
      if ([string]::IsNullOrEmpty($PrivateEndpointId)) {
        throw "Terraform output paas_app_sql_server_endpoint_id is empty"
      }

      $Script:VDCResourceGroupName   = $(terraform output "vdc_resource_group"              2>$null)
      if ([string]::IsNullOrEmpty($VDCResourceGroupName)) {
        throw "Terraform output vdc_resource_group is empty"
      }
    }
  } finally {
    $null = SetWorkspace -Workspace $priorWorkspace
    Pop-Location
  }
}

$privateEndpointResource = Get-AzResource -ResourceId $PrivateEndpointId
$privateEndpoint = Get-AzPrivateEndpoint -Name $privateEndpointResource.Name -ResourceGroupName $privateEndpointResource.ResourceGroupName
$networkInterface = Get-AzResource -ResourceId $privateEndpoint.NetworkInterfaces[0].Id -ApiVersion "2019-04-01" 

Import-Module Az.PrivateDns # Does not get loaded automatically sometimes (e.g. in subshell)
foreach ($ipconfig in $networkInterface.properties.ipConfigurations) { 
  foreach ($fqdn in $ipconfig.properties.privateLinkConnectionProperties.fqdns) { 
    $recordName = $fqdn.split('.',2)[0] 
    $dnsZone = $fqdn.split('.',2)[1] 
    Write-Host "Creating Private DNS A record $fqdn -> $($ipconfig.properties.privateIPAddress)..."
    $dnsRecord = New-AzPrivateDnsRecordSet -Name $recordName -RecordType A -ZoneName "privatelink.database.windows.net" `
      -ResourceGroupName $VDCResourceGroupName -Ttl 600 `
      -PrivateDnsRecords (New-AzPrivateDnsRecordConfig -IPv4Address $ipconfig.properties.privateIPAddress) `
      -Overwrite
    Write-Host "Created Private DNS A record $($dnsRecord.Name).$($dnsRecord.ZoneName) -> $($dnsRecord.Records[0])"
  } 
} 