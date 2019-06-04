#!/usr/bin/env pwsh

param  
( 
   #[string] $Workspace = "default",
   [parameter(Mandatory=$false)][string]$Tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "Terraform"),
   [string] $ApiVersion = "2014-01",
   [int] $ExpirationSeconds = 300
) 

# Retrieve config using Terraform
Push-Location $tfdirectory
$eventHubNameSpaceFqdn = $(terraform output app_eventhub_namespace_fqdn)
$eventHubName = $(terraform output app_eventhub_name)
$eventHubKey = $(terraform output app_eventhub_namespace_key)
#$resourceGroup = $(terraform output app_resource_group)
Pop-Location

# Create SAS
[Reflection.Assembly]::LoadWithPartialName("System.Web")| out-null
$URI="$eventHubNameSpaceFqdn/$eventHubName"
$Access_Policy_Name="RootManageSharedAccessKey"
$Expires=([DateTimeOffset]::Now.ToUnixTimeSeconds()) + $ExpirationSeconds
$SignatureString=[System.Web.HttpUtility]::UrlEncode($URI)+ "`n" + [string]$Expires
$HMAC = New-Object System.Security.Cryptography.HMACSHA256
$HMAC.key = [Text.Encoding]::ASCII.GetBytes($eventHubKey)
$Signature = $HMAC.ComputeHash([Text.Encoding]::ASCII.GetBytes($SignatureString))
$Signature = [Convert]::ToBase64String($Signature)
$SASToken = "SharedAccessSignature sr=" + [System.Web.HttpUtility]::UrlEncode($URI) + "&sig=" + [System.Web.HttpUtility]::UrlEncode($Signature) + "&se=" + $Expires + "&skn=" + $Access_Policy_Name
$SASToken

# Perform Event Hub HTTP request
$headers = @{}
$headers.Add("Authorization",$SASToken)
$headers.Add("Content-Type","application/atom+xml;type=entry;charset=utf-8")
$headers.Add("Host",$eventHubNameSpaceFqdn)
$messageBody="Hello World " + $(Get-Date)
Invoke-WebRequest -Uri "https://$URI//messages?timeout=60&api-version=$ApiVersion" -Method "POST" -Body $messageBody -Headers $headers
