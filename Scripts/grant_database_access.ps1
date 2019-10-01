#!/usr/bin/env pwsh

### Arguments
param ( 
    [parameter(Mandatory=$true)][string]$spName,
    [parameter(Mandatory=$true)][string]$sqlDatabase,
    [parameter(Mandatory=$true)][string]$sqlServerFQDN,
    [parameter(Mandatory=$false)][string]$tenantid=$env:ARM_TENANT_ID,
    [parameter(Mandatory=$false)][string]$clientid=$env:ARM_CLIENT_ID,
    [parameter(Mandatory=$false)][string]$clientsecret=$env:ARM_CLIENT_SECRET
) 

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

$token = GetAccessToken

$conn = New-Object System.Data.SqlClient.SqlConnection
$conn.ConnectionString = "Data Source=tcp:$($sqlServerFQDN),1433;Initial Catalog=$($sqlDatabase);Connection Timeout=30;" 
$conn.AccessToken = $token

Write-Host "Connecting to database $sqlServerFQDN/$sqlDatabase..."
$conn.Open()
$query = (Get-Content grant-database-access.sql) -replace "sqldbname",$sqlDatabase -replace "spname",$spName
Write-Debug "Executing query:`n$query"
$command = New-Object -TypeName System.Data.SqlClient.SqlCommand($query, $conn) 	
# Problem: 'AADSTS65002: Consent between first party applications and resources must be configured via preauthorization
$Result = $command.ExecuteNonQuery()
$Result
$conn.Close()
