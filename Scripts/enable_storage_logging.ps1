#!/usr/bin/env pwsh

param (    
    [parameter(Mandatory=$false)][string]$AppStorageAccount,
    [parameter(Mandatory=$false)][string]$AppResourceGroup

)

# Enable logging on storage account
Write-Host "Enabling blob logging for storage account $AppStorageAccount..."
$storageKey = Get-AzStorageAccountKey -ResourceGroupName $AppResourceGroup -AccountName $AppStorageAccount | Where-Object {$_.KeyName -eq "key1"} | Select-Object -ExpandProperty Value
$storageContext = New-AzStorageContext -StorageAccountName $AppStorageAccount -StorageAccountKey $storageKey
$loggingProperty = Set-AzStorageServiceLoggingProperty -Context $storageContext -ServiceType Blob -LoggingOperations Delete,Read,Write -PassThru 
$loggingProperty