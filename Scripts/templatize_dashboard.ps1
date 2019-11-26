#!/usr/bin/env pwsh

param ( 
    [parameter(Mandatory=$false)][string]$InputFile="tmpdashboard.json",
    [parameter(Mandatory=$false)][string]$OutputFile="dashboard.tpl",
    [parameter(Mandatory=$false)][switch]$Force=$false,
    [parameter(Mandatory=$false)][switch]$ShowTemplate=$false,
    [parameter(Mandatory=$false)][switch]$DontWrite=$false,
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "Terraform"),
    [parameter(Mandatory=$false)][string]$subscription=$env:ARM_SUBSCRIPTION_ID,
    [parameter(Mandatory=$false)][string]$tenantid=$env:ARM_TENANT_ID,
    [parameter(Mandatory=$false)][string]$clientid=$env:ARM_CLIENT_ID,
    [parameter(Mandatory=$false)][string]$clientsecret=$env:ARM_CLIENT_SECRET
) 


### Internal Functions
. (Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) functions.ps1)
$InputFilePath  = Join-Path $tfdirectory $InputFile
$OutputFilePath = Join-Path $tfdirectory $OutputFile


If (!(Test-Path $InputFilePath)) {
    Write-Host "$InputFilePath not found" -ForegroundColor Red
    exit
}
If (!(Test-Path $OutputFilePath) -and !$Force -and !$DontWrite) {
    Write-Host "$OutputFilePath already exists" -ForegroundColor Red
    exit
}
# if (!($Environment -and $Prefix -and $Suffix)) {
#     Write-Host "Please specify token vakues to look for (Environment/Prefix/Suffix)" -ForegroundColor Red
#     exit
# }

# Retrieve Azure resources config using Terraform
try {
    Push-Location $tfdirectory

    Invoke-Command -ScriptBlock {
        $Private:ErrorActionPreference = "Continue"
        $Script:prefix      = $(terraform output "resource_prefix"      2>$null)
        $Script:suffix      = $(terraform output "resource_suffix"      2>$null)
        $Script:environment = $(terraform output "resource_environment" 2>$null)
    }

    if ([string]::IsNullOrEmpty($prefix) -or [string]::IsNullOrEmpty($environment) -or [string]::IsNullOrEmpty($suffix)) {
        Write-Host "Resources have not yet been created, nothing to do" -ForegroundColor Yellow
        exit 
    }
} finally {
    Pop-Location
}

$template = (Get-Content $InputFilePath -Raw) 
$template = $($template | jq '.properties') # Use jq, ConvertFrom-Json does not parse properly
$template = $template -Replace "/subscriptions/........-....-....-................./", "`$`{subscription`}/"
$template = $template -Replace "${prefix}-", "`$`{prefix`}-"
$template = $template -Replace "-${environment}-", "-`$`{environment`}-"
$template = $template -Replace "-${suffix}", "-`$`{suffix`}"
$template = $template -Replace "\`'${suffix}\`'", "'`$`{suffix`}'"
$template = $template -Replace "http[s?]://[\w\.]*iisapp[\w\.]*/", "`$`{iaas_app_url`}"
$template = $template -Replace "http[s?]://[\w\.]*webapp[\w\.]*/", "`$`{paas_app_url`}"
$template = $template -Replace "https://dev.azure.com[^`']*`'", "`$`{release_web_url`}`'"

# Check for remnants of tokens that should've been caught
$enviromentMatches = $template -match $environment
$suffixMatches = $template -match $suffix
if ($enviromentMatches) {
    Write-Host "Environment value '$environment' found in output:" -ForegroundColor Red
    $enviromentMatches
}
if ($suffixMatches) {
    Write-Host "Suffix value '$suffix' found in output:" -ForegroundColor Red
    $suffixMatches
}
if ($enviromentMatches -or $suffixMatches) {
    Write-Host "Aborting" -ForegroundColor Red
    exit
}

if (($DontWrite -eq $false) -or ($DontWrite -eq $null)) {
    $template | Out-File $OutputFilePath
} else {
    Write-Host "Skipped writing template" -ForegroundColor Yellow
}
if ($ShowTemplate) {
    #Write-Host $template
    Get-Content $OutputFilePath
}