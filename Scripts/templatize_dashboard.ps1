#!/usr/bin/env pwsh

param ( 
    [parameter(Mandatory=$false)][string]$InputFile="tmpdashboard.json",
    [parameter(Mandatory=$false)][string]$OutputFile="dashboard.tpl",
    [parameter(Mandatory=$false)][string]$Environment,
    [parameter(Mandatory=$false)][string]$Prefix,
    [parameter(Mandatory=$false)][string]$Suffix,
    [parameter(Mandatory=$false)][switch]$Force=$false,
    [parameter(Mandatory=$false)][switch]$ShowTemplate=$false,
    [parameter(Mandatory=$false)][switch]$DontWrite=$false,
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "Terraform")
) 

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
if (!($Environment -and $Prefix -and $Suffix)) {
    Write-Host "Please specify token vakues to look for (Environment/Prefix/Suffix)" -ForegroundColor Red
    exit
}

$template = (Get-Content $InputFilePath -Raw) 
$template = $($template | jq '.properties') # Use jq, ConvertFrom-Json does not parse properly
$template = $template -Replace "/subscriptions/........-....-....-................./", "`$`{subscription`}/"
$template = $template -Replace "${Prefix}-", "`$`{prefix`}-"
$template = $template -Replace "-${Environment}-", "-`$`{environment`}-"
$template = $template -Replace "-${Suffix}", "-`$`{suffix`}"
$template = $template -Replace "\`'${Suffix}\`'", "'`$`{suffix`}'"

# Check for remnants of tokens that should've been caught
$enviromentMatches = $template -match $Environment
$suffixMatches = $template -match $Suffix
if ($enviromentMatches) {
    Write-Host "Environment value '$Environment' found in output:" -ForegroundColor Red
    $enviromentMatches
}
if ($suffixMatches) {
    Write-Host "Environment value '$Suffix' found in output:" -ForegroundColor Red
    $suffixMatches
}
if ($enviromentMatches -or $suffixMatches) {
    Write-Host "Aborting" -ForegroundColor Red
    exit
}
if ($ShowTemplate) {
    Write-Host $template
}
if (($DontWrite -ne $false) -or ($DontWrite -eq $null)) {
    $template | Out-File $OutputFilePath
} else {
    Write-Host "Skipped writing template"
}