# Input bindings are passed in via param block
param($Timer)

# The 'IsPastDue' porperty is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}

# Write an information log with the current time
Write-Host "Starting Shutdown script at UTC $((Get-Date).ToUniversalTime())"

#$resourceGroupIDs = $env:APPSETTING_resource_group_ids.Split(",")

Write-Host "Stopping VM's in resource group $env:APPSETTING_app_resource_group..."
Get-AzVM -ResourceGroupName $env:APPSETTING_app_resource_group -Status | Where-Object {$_.PowerState -match "running"} | Stop-AzVM -Force

Write-Host "Stopping VM's in resource group $env:APPSETTING_vdc_resource_group..."
Get-AzVM -ResourceGroupName $env:APPSETTING_vdc_resource_group -Status | Where-Object {$_.PowerState -match "running"} | Stop-AzVM -Force

# Write an information log with the current time
Write-Host "Finished Shutdown script at UTC $((Get-Date).ToUniversalTime())"
