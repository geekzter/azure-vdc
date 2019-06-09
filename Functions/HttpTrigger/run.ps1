using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

<#
Write-Host "Listing module's"
Get-Module -ListAvailable 

Write-Host "Installing module(s)..."
Install-Module -Scope CurrentUser -Name Az.Compute
Install-Module -Scope CurrentUser -Name Az

Write-Host "Importing module(s)..."
Import-Module Az

#>
Write-Host "Now executing some Az commands..."
Get-AzContext
Get-AzVM -ResourceGroupName cra-vdc-mpme -Status | Where-Object {$_.PowerState -notmatch "running"}
#Get-AzVM -ResourceGroupName cra-vdc-mpme -Status | Where-Object {$_.PowerState -notmatch "running"} | Start-AzVM

# Interact with query parameters or the body of the request.
$name = $Request.Query.Name
if (-not $name) {
    $name = $Request.Body.Name
}

if ($name) {
    $status = [HttpStatusCode]::OK
    $body = "Hello $name"
}
else {
    $status = [HttpStatusCode]::BadRequest
    $body = "Please pass a name on the query string or in the request body."
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = $status
    Body = $body
})
