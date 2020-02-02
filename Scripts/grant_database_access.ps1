#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    Grants access to given AAD user/service principal name

#> 
### Arguments
param ( 
    [parameter(Mandatory=$true)][string]$UserName,
    [parameter(Mandatory=$true)][string]$UserClientId,
    [parameter(Mandatory=$true)][string]$SqlDatabaseName,
    [parameter(Mandatory=$true)][string]$SqlServerFQDN,
    [parameter(Mandatory=$false)][string]$tenantid=$env:ARM_TENANT_ID,
    [parameter(Mandatory=$false)][string]$clientid=$env:ARM_CLIENT_ID,
    [parameter(Mandatory=$false)][string]$clientsecret=$env:ARM_CLIENT_SECRET
) 

# From: https://blog.bredvid.no/handling-azure-managed-identity-access-to-azure-sql-in-an-azure-devops-pipeline-1e74e1beb10b
function ConvertTo-Sid {
    param (
        [string]$appId
    )
    [guid]$guid = [System.Guid]::Parse($appId)
    foreach ($byte in $guid.ToByteArray()) {
        $byteGuid += [System.String]::Format("{0:X2}", $byte)
    }
    return "0x" + $byteGuid
}

function GetAccessToken () {
    # From https://blog.bredvid.no/handling-azure-managed-identity-access-to-azure-sql-in-an-azure-devops-pipeline-1e74e1beb10b
    $resourceAppIdURI = 'https://database.windows.net/'
    $tokenResponse = Invoke-RestMethod -Method Post -UseBasicParsing `
        -Uri "https://login.windows.net/$($tenantid)/oauth2/token" `
        -Body @{
            resource=$resourceAppIdURI
            client_id=$clientid
            grant_type='client_credentials'
            client_secret=$clientsecret
        } -ContentType 'application/x-www-form-urlencoded'

    if ($tokenResponse) {
        Write-Debug "Access token type is $($tokenResponse.token_type), expires $($tokenResponse.expires_on)"
        $token = $tokenResponse.access_token
        Write-Debug "Access token is $token"
    } else {
        Write-Error "Unable to obtain access token"
    }

    return $token
}

$scriptDirectory=(Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).FullName


# Prepare SQL Connection
$token = GetAccessToken
$conn = New-Object System.Data.SqlClient.SqlConnection
$conn.ConnectionString = "Data Source=tcp:$($SqlServerFQDN),1433;Initial Catalog=$($SqlDatabaseName);Connection Timeout=30;" 
$conn.AccessToken = $token

try {
    # Connect to SQL Server
    Write-Host "Connecting to database $SqlServerFQDN/$SqlDatabaseName..."
    $conn.Open()

    # Prepare SQL Command
    $sid = ConvertTo-Sid $UserClientId
    $query = (Get-Content (Join-Path $scriptDirectory grant-database-access.sql)) -replace "@user_name",$UserName -replace "@user_sid",$sid -replace "\-\-.*$",""
    $command = New-Object -TypeName System.Data.SqlClient.SqlCommand($query, $conn)
    # Use parameterized query to protect against SQL injection
    #$null = $command.Parameters.AddWithValue("@user_name",$UserName)
    #$null = $command.Parameters.AddWithValue("@user_sid",$userSID)
    # Problem: 'AADSTS65002: Consent between first party applications and resources must be configured via preauthorization

    # Execute SQL Command
    Write-Debug "Executing query:`n$query"
    $Result = $command.ExecuteNonQuery()
    $Result
} finally {
    $conn.Close()
}