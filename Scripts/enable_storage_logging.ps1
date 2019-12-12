#!/usr/bin/env pwsh

param (    
    [parameter(Mandatory=$false)][string]$StorageAccountName,
    [parameter(Mandatory=$false)][string]$ResourceGroupName

)

# Enable logging on storage account
Write-Host "Enabling blob logging for storage account $StorageAccountName..."
$storageKey = Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -AccountName $StorageAccountName | Where-Object {$_.KeyName -eq "key1"} | Select-Object -ExpandProperty Value
$storageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $storageKey
$loggingProperty = Set-AzStorageServiceLoggingProperty -Context $storageContext -ServiceType Blob -LoggingOperations Delete,Read,Write -PassThru 
if ($loggingProperty) {
    Write-Host "Enabled blob logging for storage account ${StorageAccountName}:"
    $loggingProperty
}