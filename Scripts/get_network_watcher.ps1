#!/usr/bin/env pwsh
# No longer used

param ( 
    [parameter(Mandatory=$true)][string]$Location,
    [parameter(Mandatory=$false)][string]$SubscriptionId=$env:ARM_SUBSCRIPTION_ID
) 

#$terraformQuery = [Console]::In.ReadLine() | ConvertFrom-Json

$resourceQuery = "Resources | where type == `"microsoft.network/networkwatchers`" and location == `"${Location}`" and subscriptionId == `"${SubscriptionId}`" | project name, resourceGroup"
#Write-Host "Executing graph query:`n$resourceQuery" -ForegroundColor Green
$graphResult = Search-AzGraph -Query $resourceQuery
if ($graphResult) {
    $graphResult | ConvertTo-Json | Write-Output
} else {
    # Empty JSON object
    @{} | ConvertTo-Json  `
}