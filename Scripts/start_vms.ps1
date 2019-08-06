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
if(-not($subscription)) { Throw "You must supply a value for subscription" }
if(-not($tenantid)) { Throw "You must supply a value for tenant" }

# Log on to Azure if not already logged on
if (!(Get-AzContext)) 
{
    if(-not($clientid)) { Throw "You must supply a value for clientid" }
    if(-not($clientsecret)) { Throw "You must supply a value for clientsecret" }
    # Use Terraform ARM Backend config to authenticate to Azure
    $secureClientSecret = ConvertTo-SecureString $clientsecret -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential ($clientid, $secureClientSecret)
    Connect-AzAccount -Tenant $tenantid -Subscription $subscription -ServicePrincipal -Credential $credential
}
Set-AzContext -Subscription $subscription -Tenant $tenantid

# Retrieve Azure resources config using Terraform
try 
{
    Push-Location $tfdirectory
    Invoke-Command -ScriptBlock {
        $Private:ErrorActionPreference = "Continue"
        $Script:appResourceGroup = $(terraform output "app_resource_group" 2>$null)
        $Script:vdcResourceGroup = $(terraform output "vdc_resource_group" 2>$null)

        $Script:appRGExists = (![string]::IsNullOrEmpty($appResourceGroup) -and ($null -ne $(Get-AzResourceGroup -Name $appResourceGroup -ErrorAction "SilentlyContinue")))
        $Script:vdcRGExists = (![string]::IsNullOrEmpty($vdcResourceGroup) -and ($null -ne $(Get-AzResourceGroup -Name $vdcResourceGroup -ErrorAction "SilentlyContinue")))
    }

    if ($appRGExists) 
    {
        # Start App VM's async
        Get-AzVM -ResourceGroupName $appResourceGroup -Status | Where-Object {$_.PowerState -notmatch "running"} | Start-AzVM -AsJob
    }    
    if ($vdcRGExists) 
    {
        # Start VDC VM's async
        Get-AzVM -ResourceGroupName $vdcResourceGroup -Status | Where-Object {$_.PowerState -notmatch "running"} | Start-AzVM -AsJob
    }
    
    if ($appRGExists -and !$nowait) 
    {
        # Block until App VM's have started
        Get-AzVM -ResourceGroupName $appResourceGroup -Status | Where-Object {$_.PowerState -notmatch "running"} | Start-AzVM
    }
    if ($vdcRGExists -and !$nowait) 
    {
        # Block until VDC VM's have started
        Get-AzVM -ResourceGroupName $vdcResourceGroup -Status | Where-Object {$_.PowerState -notmatch "running"} | Start-AzVM
    }
}
finally
{
    Pop-Location
}
