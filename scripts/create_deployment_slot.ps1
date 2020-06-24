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
    [parameter(Mandatory=$false)][string]$Slot="staging"
) 

if (az webapp deployment slot list -n $AppService -g $ResourceGroup --query "[?name=='$Slot']" -o tsv) {
    Write-Warning "Deployment slot '$Slot' already exists"
    exit
}

az webapp deployment slot create -n $AppService --configuration-source $AppService -s $Slot -g $ResourceGroup --query "hostNames"

$productionMode = $(az webapp config appsettings list -n $AppService -g $ResourceGroup --query "[?name=='ASPNETCORE_ENVIRONMENT'].value" -o tsv)
$stagingMode = ($productionMode -eq "Offline" ? "Online" : "Offline")

az webapp config appsettings set --settings ASPNETCORE_ENVIRONMENT=$stagingMode -s $Slot -n $AppService -g $ResourceGroup --query "[?name=='ASPNETCORE_ENVIRONMENT']"
