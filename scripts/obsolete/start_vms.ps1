#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    Start Virtual Machines deployed
 
.DESCRIPTION 
    Terraform plan may need VM's to be started for certain resources e.g. VM extensions
#> 
param  
(    
    [parameter(Mandatory=$false,HelpMessage="The Terraform workspace to use")][string]$Workspace=$env:TF_WORKSPACE,
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "terraform"),
    [parameter(Mandatory=$false)][string]$subscription=$env:ARM_SUBSCRIPTION_ID,
    [parameter(Mandatory=$false)][string]$tenantid=$env:ARM_TENANT_ID,
    [parameter(Mandatory=$false)][string]$clientid=$env:ARM_CLIENT_ID,
    [parameter(Mandatory=$false)][string]$clientsecret=$env:ARM_CLIENT_SECRET,
    [parameter(Mandatory=$false)][switch]$nowait=$false
) 
if(-not($subscription)) { Throw "You must supply a value for subscription" }
if(-not($tenantid)) { Throw "You must supply a value for tenant" }

. (Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) functions.ps1)

# Log on to Azure if not already logged on
AzLogin

# Retrieve Azure resources config using Terraform
try 
{
    Push-Location $tfdirectory
    $priorWorkspace = (SetWorkspace -Workspace $Workspace).PriorWorkspaceName
    
    Invoke-Command -ScriptBlock {
        $Private:ErrorActionPreference = "Continue"
        $Script:appResourceGroup = $(terraform output "iaas_app_resource_group" 2>$null)
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
    $null = SetWorkspace -Workspace $priorWorkspace
    Pop-Location
}
