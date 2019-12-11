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
    [parameter(Mandatory=$false)][string]$NetworkWatcherName="NetworkWatcher_$Location",
    [parameter(Mandatory=$false)][string]$ResourceGroupName="NetworkWatcherRG"
) 

$hostProcess = (Get-Process -id $pid).Parent.ProcessName
Write-Host "'$($MyInvocation.Line)' invoked from $hostProcess"

# Check if a Network Watcher already exists
$networkWatcher = Get-AzNetworkWatcher -Location $Location -ErrorAction SilentlyContinue
if ($networkWatcher) {
    Write-Host "Network Watcher '$($networkWatcher.Name)' already exists in Resource Group '$($networkWatcher.ResourceGroupName)' and region '$($networkWatcher.Location)'" -ForegroundColor Yellow
    if ($networkWatcher.Name -ne $NetworkWatcherName) {
        Write-Host "Network Watcher '$($networkWatcher.Name)' name is different from argument '$NetworkWatcherName'" -ForegroundColor Yellow
    }
        if ($networkWatcher.ResourceGroupName -ne $ResourceGroupName) {
        Write-Host "Network Watcher Resource Group '$($networkWatcher.ResourceGroupName)' name is different from argument '$ResourceGroupName'" -ForegroundColor Yellow
    }
    $networkWatcher | ConvertTo-Json
    exit
}

# Create Resource Group for Network Watcher, if it does not exists yet
$resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if ($resourceGroup) {
    Write-Host "Resource group '$($resourceGroup.ResourceGroupName)' already exists in region '$($resourceGroup.Location)'" -ForegroundColor Yellow
} else {
    Write-Host "Creating resource group '$ResourceGroupName' in region '$Location'..."
    $resourceGroup = New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Force
    Write-Host "Resource group '$($resourceGroup.ResourceGroupName)' created in region '$($resourceGroup.Location)'"
}

Write-Host "Creating Network Watcher '$NetworkWatcherName' in Resource Group '$ResourceGroupName' and region '$Location'..."
$networkWatcher = New-AzNetworkWatcher -Name $NetworkWatcherName -ResourceGroup $ResourceGroupName -Location $Location
if ($networkWatcher) {
    Write-Host "Network Watcher '$($networkWatcher.Name)' created Resource Group '$($networkWatcher.ResourceGroupName)' and region '$($networkWatcher.Location)'"
    $networkWatcher | ConvertTo-Json
} else {
    # Empty JSON object
    @{} | ConvertTo-Json  
    exit 1
}