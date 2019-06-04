#!/usr/bin/env pwsh

param  
(    
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "Terraform"),
    [parameter(Mandatory=$false)][string]$subscription=$env:ARM_SUBSCRIPTION_ID,
    [parameter(Mandatory=$false)][string]$tenantid=$env:ARM_TENANT_ID,
    [parameter(Mandatory=$false)][string]$clientid=$env:ARM_CLIENT_ID,
    [parameter(Mandatory=$false)][string]$clientsecret=$env:ARM_CLIENT_SECRET,
    [parameter(Mandatory=$false)][switch]$nowait=$false
) 
if(-not($subscription)) { Throw "You must supply a value for Workspace" }

# Log on to Azure if not already logged on
if (!(Get-AzContext)) 
{
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
try 
{`
    Push-Location $tfdirectory
    $appResourceGroup = $(terraform output "app_resource_group" 2>$null)
    $vdcResourceGroup = $(terraform output "vdc_resource_group" 2>$null)

    if (![string]::IsNullOrEmpty($appResourceGroup)) 
    {
        # Start App VM's async
        Get-AzVM -ResourceGroupName $appResourceGroup -Status | Where-Object {$_.PowerState -notmatch "running"} | Start-AzVM -AsJob
    }    
    if (![string]::IsNullOrEmpty($vdcResourceGroup)) 
    {
        # Start VDC VM's async
        Get-AzVM -ResourceGroupName $vdcResourceGroup -Status | Where-Object {$_.PowerState -notmatch "running"} | Start-AzVM -AsJob
    }
    
    if (![string]::IsNullOrEmpty($appResourceGroup) -and !$nowait) 
    {
        # Block until App VM's have started
        Get-AzVM -ResourceGroupName $appResourceGroup -Status | Where-Object {$_.PowerState -notmatch "running"} | Start-AzVM
    }
    
    if (![string]::IsNullOrEmpty($vdcResourceGroup) -and !$nowait) 
    {
        # Block until VDC VM's have started
        Get-AzVM -ResourceGroupName $vdcResourceGroup -Status | Where-Object {$_.PowerState -notmatch "running"} | Start-AzVM
    }
}
finally
{
    Pop-Location
}
