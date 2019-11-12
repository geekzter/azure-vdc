#!/usr/bin/env pwsh

param (    
    [parameter(Mandatory=$false,HelpMessage="The workspace tag to filter use")][string] $Workspace,
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "Terraform")
) 
if(-not($Workspace)) {
    if (Test-Path $tfdirectory/.terraform/environment) {
        $Workspace = Get-Content $tfdirectory/.terraform/environment
    } else {
        throw "You must supply a value for Workspace" 
    }
}

# Access Terraform (Azure) backend to get leases for each workspace
$tfConfig = $(Get-Content $tfdirectory/.terraform/terraform.tfstate | ConvertFrom-Json)
$backendStorageAccountName = $tfConfig.backend.config.storage_account_name
$backendStorageContainerName = $tfConfig.backend.config.container_name
$backendStateKey = $tfConfig.backend.config.key
$backendStorageKey = $env:ARM_ACCESS_KEY
$backendstorageContext = New-AzStorageContext -StorageAccountName $backendStorageAccountName -StorageAccountKey $backendStorageKey
if ($Workspace -eq "default") {
    $blobName = $backendStateKey
} else {
    $blobName = "${backendStateKey}env:${Workspace}"
}

Write-Host "Retrieving $blobName"
$tfStateBlob = Get-AzStorageBlob -Context $backendstorageContext -Container $backendStorageContainerName -Blob $blobName
Write-Host "Breaking lease on blob $($tfStateBlob.ICloudBlob.Uri.AbsoluteUri)..."

$tfStateBlob.ICloudBlob.BreakLease()
