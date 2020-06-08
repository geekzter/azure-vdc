#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    Intended to be used from Terraform local-exec provisioner
 
.DESCRIPTION 
    Creates NetworkWatcherRG resource group and Network Watcher in given location, if they do not exist.
    Network Watcher is a singleton deployment, hence provisioning is not isolated from other workloads

#> 
param ( 
    [parameter(Mandatory=$true)][string]$Location,
    #[parameter(Mandatory=$false)][string]$NetworkWatcherName="NetworkWatcher_$Location",
    [parameter(Mandatory=$false)][string]$NetworkWatcherName="${Location}-watcher",
    [parameter(Mandatory=$false)][string]$ResourceGroupName="NetworkWatcherRG"
) 
#Requires -Version 7

$hostProcess = (Get-Process -id $pid).Parent.ProcessName
Write-Host "'$($MyInvocation.Line)' invoked from $hostProcess"

# Check if a Network Watcher already exists
$networkWatcher = $(az network watcher list --query "[?location=='$Location']" | ConvertFrom-Json | Where-Object -Property location -eq $Location)
if ($networkWatcher) {
    Write-Host "Network Watcher '$($networkWatcher.name)' already exists in Resource Group '$($networkWatcher.resourceGroup)' and region '$($networkWatcher.location)'" -ForegroundColor Yellow
    if ($networkWatcher.name -ne $NetworkWatcherName) {
        Write-Host "Network Watcher '$($networkWatcher.name)' name is different from argument '$NetworkWatcherName'" -ForegroundColor Yellow
    }
    if ($networkWatcher.resourceGroup -ne $ResourceGroupName) {
        Write-Host "Network Watcher Resource Group '$($networkWatcher.resourceGroup)' name is different from argument '$ResourceGroupName'" -ForegroundColor Yellow
    }
    $networkWatcher | ConvertTo-Json
    exit
}

# Create Resource Group for Network Watcher, if it does not exists yet
Invoke-Command -ScriptBlock {
    $Private:ErrorActionPreference = "Continue"
    $Script:resourceGroup = $(az group show --name $ResourceGroupName 2>$null | ConvertFrom-Json)
}
if ($resourceGroup) {
    Write-Host "Resource group '$($resourceGroup.name)' already exists in region '$($resourceGroup.location)'" -ForegroundColor Yellow
} else {
    Write-Host "Creating resource group '$ResourceGroupName' in region '$Location'..."
    $resourceGroup = $(az group create -l $Location -n $ResourceGroupName | ConvertFrom-Json)
    Write-Host "Resource group '$($resourceGroup.name)' created in region '$($resourceGroup.location)'"
}

Write-Host "Creating Network Watcher '$NetworkWatcherName' in Resource Group '$ResourceGroupName' and region '$Location'..."
$networkWatcher = $(az network watcher configure -g $ResourceGroupName -l $Location --enabled true --query "[?location=='$Location']" | ConvertFrom-Json)
Write-Host "Network Watcher '$($networkWatcher.name)' created in Resource Group '$($networkWatcher.resourceGroup)' and region '$($networkWatcher.location)'"
