# Input bindings are passed in via param block
param($Timer)

# Get the current universal time in the default string format
$currentUTCtime = (Get-Date).ToUniversalTime()

# The 'IsPastDue' porperty is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}

# Write to the Azure Functions log stream
Write-Host "PowerShell HTTP trigger function processed a request."

Write-Host "Stopping VM's in resource group $env:APPSETTING_app_resource_group..."
Get-AzVM -ResourceGroupName $env:APPSETTING_app_resource_group -Status | Where-Object {$_.PowerState -match "running"} | Stop-AzVM -Force

Write-Host "Stopping VM's in resource group $env:APPSETTING_vdc_resource_group..."
Get-AzVM -ResourceGroupName $env:APPSETTING_vdc_resource_group -Status | Where-Object {$_.PowerState -match "running"} | Stop-AzVM -Force

# Write an information log with the current time
Write-Host "Finished Shutdown script at: $currentUTCtime"
