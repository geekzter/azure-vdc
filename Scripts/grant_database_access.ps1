#!/usr/bin/env pwsh

### Arguments
param ( 
    [parameter(Mandatory=$false)][string]$sqlDatabase="vdcdevpaasappfxausqlserver.database.windows.net",
    [parameter(Mandatory=$false)][string]$sqlServerFQDN="vdcdevpaasappfxausqldb",
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
        Write-debug "Access token type is $($tokenResponse.token_type), expires $($tokenResponse.expires_on)"
        $token = $tokenResponse.access_token
    } else {
        throw "Unable to obtain access token"
    }

    return $token
}

$token = GetAccessToken

$conn = new-object System.Data.SqlClient.SqlConnection
$conn.ConnectionString = "Server=tcp:$($sqlServerFQDN),1433;Initial Catalog=$($sqlDatabase);Persist Security Info=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;" 
$conn.AccessToken = $token

Write-Host "Connecting to database $sqlServerFQDN/$sqlDatabase..."
$conn.Open()