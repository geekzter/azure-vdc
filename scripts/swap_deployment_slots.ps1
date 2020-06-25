#!/usr/bin/env pwsh

<# 
.SYNOPSIS 
    Creates Deployment Slot for App Service
 
.DESCRIPTION 
    This script creates a staging deeployment slot (if it does not exist yet) by cloning the production slot
    It then toggles the ASPNETCORE_ENVIRONMENT on the slot to have the opposite valkue from the production slot
.EXAMPLE
    ./create_deployment_slot.ps1 
#> 
#Requires -Version 7

param ( 
    [parameter(Mandatory=$true)][string]$AppService,
    [parameter(Mandatory=$true)][string]$ResourceGroup,
    [parameter(Mandatory=$false)][string]$Slot="staging",
    [parameter(Mandatory=$false)][ValidateSet("Online", "Offline")][string]$Mode
) 

# Make sure slot exists
& (Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "create_deployment_slot.ps1") -Slot $Slot -AppService $AppService -ResourceGroup $ResourceGroup

if (!(az webapp list --query "[?name=='$AppService' && resourceGroup=='$ResourceGroup'].id" -o tsv)) {
    Write-Warning "App Service '$AppService' does not exist (yet) in resource group '$ResourceGroup'"
    exit
}

$productionMode = $(az webapp config appsettings list -n $AppService -g $ResourceGroup --query "[?name=='ASPNETCORE_ENVIRONMENT'].value" -o tsv)

if ($Mode -and ($productionMode -eq $Mode)) {
    Write-Host "Already $Mode, no swap needed"
} else {
    Write-Host "Swapping slots..."
    # Swap slots
    az webapp deployment slot swap -s $slot -n $AppService -g $ResourceGroup
}

az webapp config appsettings list -n $AppService -g $ResourceGroup --query "[?name=='ASPNETCORE_ENVIRONMENT']" 