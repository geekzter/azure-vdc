#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    Grants access to given AAD user/service principal name

#> 
#Requires -Version 7

### Arguments
param ( 
    [parameter(Mandatory=$false)][string]$DBAName,
    [parameter(Mandatory=$false)][string]$DBAObjectId,
    [parameter(Mandatory=$true)][string]$MSIName,
    [parameter(Mandatory=$true)][string]$MSIClientId,
    [parameter(Mandatory=$true)][string]$SqlDatabaseName,
    [parameter(Mandatory=$false)][string]$SqlServer=$SqlServerFQDN.Split(".")[0],
    [parameter(Mandatory=$true)][string]$SqlServerFQDN,
    [parameter(Mandatory=$false)][string]$UserName=$null,
    [parameter(Mandatory=$false)][SecureString]$SecurePassword=$null
) 

. (Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) functions.ps1)

$msiSID = ConvertTo-Sid $MSIClientId
$msiSqlParameters = @{msi_name=$MSIName;msi_sid=$msiSID}
$scriptDirectory = (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).FullName 
$msiSqlScript = (Join-Path $scriptDirectory "grant-msi-database-access.sql")
Execute-Sql -QueryFile $msiSqlScript -Parameters $msiSqlParameters -SqlDatabaseName $SqlDatabaseName -SqlServerFQDN $SqlServerFQDN -UserName $UserName -SecurePassword $SecurePassword

if ($DBAName -and $DBAObjectId) {
    $dbaSID = ConvertTo-Sid $DBAObjectId
    $dbaSqlParameters = @{dba_name=$DBAName;dba_sid=$dbaSID}
    $scriptDirectory = (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).FullName 
    $dbaSqlScript = (Join-Path $scriptDirectory "grant-dbas-database-access.sql")
    # Can't connect to Master to make DBA server admin
    #Execute-Sql -QueryFile $dbaSqlScript -Parameters $dbaSqlParameters -SqlServerFQDN $SqlServerFQDN
    # Connect to database instead
    Execute-Sql -QueryFile $dbaSqlScript -Parameters $dbaSqlParameters -SqlDatabaseName $SqlDatabaseName -SqlServerFQDN $SqlServerFQDN -UserName $UserName -SecurePassword $SecurePassword
}
