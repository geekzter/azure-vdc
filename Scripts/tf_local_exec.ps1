#!/usr/bin/env pwsh

param  
( 
    [parameter(Mandatory=$true)][string]$userName,
    [parameter(Mandatory=$true)][string]$password,
    [parameter(Mandatory=$true)][string]$bastionIPAddress,
    [parameter(Mandatory=$true)][string]$fwPIPAddress,
    [parameter(Mandatory=$true)][string]$rdpPort
) 

if ($IsWindows -or ($null -eq $PSVersionTable.PSEdition))
{
    # Running on Windows
    cmdkey.exe /generic:$bastionIPAddress /user:$userName /pass:$password
    cmdkey.exe /generic:${data.azurerm_public_ip.iag_pip_created.ip_address} /user:$userName /pass:$password
    Write-Output To connect to bastion, type:
    Write-Output type 'mstsc.exe /v:$bastionIPAddress'
    Write-Output type 'mstsc.exe /v:$fwPIPAddress:$rdpPort'
}