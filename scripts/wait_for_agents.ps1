#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    Wait for Pipeline Environment agents to come up
    There is no CLI / REST operation on how to detect this, so simply wait for a VM to have started long enough ago
#> 
param ( 
    [parameter(Mandatory=$true)][string]$ResourceGroup,
    [parameter(Mandatory=$false)][int]$Timeout=120
) 

$vmIDs = $(az vm list -g $ResourceGroup --query "[].id" -o tsv)

# Wait for stable state, VM's may be restarting now
az vm wait --updated --ids $vmIDs -o none

Write-Information "Retrieving last VM status change timestamp..."
$startTimeString = (az vm get-instance-view --ids $vmIDs --query "max([].instanceView.statuses[].time)" -o tsv)

if ($startTimeString) {
    Write-Host "VM's last started $startTimeString"
    $startTime = [datetime]::Parse($startTimeString)
    $waitUntil = $startTime.AddSeconds($Timeout)
} else {
    $waitUntil = (Get-Date).AddSeconds($Timeout)
}

$sleepTime = ($waitUntil - (Get-Date))

if ($sleepTime -gt 0) {
    Write-Host "Sleeping $([math]::Ceiling($sleepTime.TotalSeconds)) seconds..."
    Start-Sleep -Milliseconds $sleepTime.TotalMilliseconds
}