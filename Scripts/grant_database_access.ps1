#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    Grants access to given AAD user/service principal name

#> 
### Arguments
param ( 
    [parameter(Mandatory=$false)][string]$DBAName,
    [parameter(Mandatory=$false)][string]$DBAObjectId,
    [parameter(Mandatory=$true)][string]$MSIName,
    [parameter(Mandatory=$true)][string]$MSIClientId,
    [parameter(Mandatory=$true)][string]$SqlDatabaseName,
    [parameter(Mandatory=$true)][string]$SqlServerFQDN,
    [parameter(Mandatory=$false)][string]$tenantid=$env:ARM_TENANT_ID,
    [parameter(Mandatory=$false)][string]$clientid=$env:ARM_CLIENT_ID,
    [parameter(Mandatory=$false)][string]$clientsecret=$env:ARM_CLIENT_SECRET
) 

. (Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) functions.ps1)

$msiSID = ConvertTo-Sid $MSIClientId
$msiSqlParameters = @{msi_name=$MSIName;msi_sid=$msiSID}
$scriptDirectory = (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).FullName 
$msiSqlScript = (Join-Path $scriptDirectory "grant-msi-database-access.sql")
Execute-Sql -QueryFile $msiSqlScript -Parameters $msiSqlParameters -SqlDatabaseName $SqlDatabaseName -SqlServerFQDN $SqlServerFQDN

if ($DBAName -and $DBAObjectId) {
    $dbaSID = ConvertTo-Sid $DBAObjectId
    $dbaSqlParameters = @{dba_name=$MSIName;dba_sid=$dbaSID}
    $scriptDirectory = (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).FullName 
    $dbaSqlScript = (Join-Path $scriptDirectory "grant-dbas-database-access.sql")
    Execute-Sql -QueryFile $dbaSqlScript -Parameters $dbaSqlParameters -SqlServerFQDN $SqlServerFQDN
}
