#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    Removes the state lock from Terraform backend storage
#> 
param (    
    [parameter(Mandatory=$false,HelpMessage="The workspace to break lease for")][string]$Workspace=$env:TF_WORKSPACE,
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "terraform")
) 
if(-not($Workspace)) {
    if (Test-Path ${tfdirectory}/.terraform/environment) {
        $Workspace = Get-Content ${tfdirectory}/.terraform/environment
    } else {
        throw "You must supply a value for Workspace" 
    }
}
$Script:ErrorActionPreference = "Stop"

if ($MyInvocation.InvocationName -ne "&") {
    Write-Host "Using Terraform workspace '$Workspace'"
}

# Access Terraform (Azure) backend to get leases for each workspace
Write-Host "Reading Terraform settings from ${tfdirectory}/.terraform/terraform.tfstate..."
$tfConfig = $(Get-Content ${tfdirectory}/.terraform/terraform.tfstate | ConvertFrom-Json)
if ($tfConfig.backend.type -ne "azurerm") {
    throw "This script only works with azurerm provider"
}
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

Write-Host "Retrieving blob https://${backendStorageAccountName}.blob.core.windows.net/${backendStorageContainerName}/${blobName}..."
$tfStateBlob = Get-AzStorageBlob -Context $backendstorageContext -Container $backendStorageContainerName -Blob $blobName -ErrorAction SilentlyContinue
if (!($tfStateBlob)) {
    Write-Host "Workspace '${Workspace}' state not found" -ForegroundColor Red
    exit
}

if ($tfStateBlob.ICloudBlob.Properties.LeaseStatus -ieq "Unlocked") {
    Write-Host "Workspace '${Workspace}' is not locked" -ForegroundColor Yellow
    exit
} else {
    # Prompt to continue
    Write-Host "If you wish to proceed to unlock workspace '${Workspace}', please reply 'yes' - null or N aborts" -ForegroundColor Cyan
    $proceedanswer = Read-Host

    if ($proceedanswer -ne "yes") {
        Write-Host "`nReply is not 'yes' - Aborting " -ForegroundColor Yellow
        exit
    }
    Write-Host "Unlocking workspace '${Workspace}' by breaking lease on blob $($tfStateBlob.ICloudBlob.Uri.AbsoluteUri)..."
    $lease = $tfStateBlob.ICloudBlob.BreakLease()
    if ($lease.Ticks -eq 0) {
        Write-Host "Unlocked workspace '${Workspace}'"
    } else {
        Write-Host "Lease has unexpected value for 'Ticks'" -ForegroundColor Yellow
        $lease
    }
}