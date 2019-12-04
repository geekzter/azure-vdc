#!/usr/bin/env pwsh

param ( 
    [parameter(Mandatory=$false)][string]$InputFile,
    [parameter(Mandatory=$false)][string]$OutputFile="dashboard.tpl",
    [parameter(Mandatory=$false)][string]$Workspace,
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

# Retrieve Azure resources config using Terraform
try {
    Push-Location $tfdirectory
    if ($Workspace) {
        $currentWorkspace = $(terraform workspace show)
        terraform workspace select $Workspace
    } else {
        $Workspace = $(terraform workspace show)
    }
    Write-Host "Using Terraform workspace '$(terraform workspace show)'" 

    Invoke-Command -ScriptBlock {
        $Private:ErrorActionPreference = "Continue"
        $Script:dashboardID = $(terraform output "dashboard_id"                  2>$null)
        $Script:appRGShort  = $(terraform output "paas_app_resource_group_short" 2>$null)
        $Script:prefix      = $(terraform output "resource_prefix"               2>$null)
        $Script:suffix      = $(terraform output "resource_suffix"               2>$null)
        $Script:environment = $(terraform output "resource_environment"          2>$null)
    }

    if ([string]::IsNullOrEmpty($prefix) -or [string]::IsNullOrEmpty($environment) -or [string]::IsNullOrEmpty($suffix)) {
        Write-Host "Resources have not yet been, or are being created. Nothing to do" -ForegroundColor Yellow
        exit 
    }
} finally {
    # Ensure this always runs
    if ($currentWorkspace) {
        terraform workspace select $currentWorkspace
    }
    Pop-Location
}

if ($InputFile) {
    Write-Host "Reading from file $InputFile..." -ForegroundColor Green
    $template = (Get-Content $InputFilePath -Raw) 
    $template = $($template | jq '.properties') # Use jq, ConvertFrom-Json does not parse properly
} else {
    Write-Host "Retrieving resource $dashboardID..." -ForegroundColor Green
    # This doesn't export full JSON
    # Get-AzResource -ResourceId $dashboardID -ExpandProperties
    # Resource Graph doesn't export full JSON either
    # $dashboardQuery  = "Resources | where type == `"microsoft.portal/dashboards`" and id == `"$dashboardID`" | project properties"
    # Write-Host "Executing Graph Query:`n$dashboardQuery" -ForegroundColor Green
    # $dashboardProperties = Search-AzGraph -Query $dashboardQuery -Subscription $subscription
    # HACK: Use Azure CLI instead
    $dashboardProperties = az resource show --ids $dashboardID
    $template = $dashboardProperties | jq '.properties'
}

$template = $template -Replace "/subscriptions/........-....-....-................./", "`$`{subscription`}/"
if ($prefix) {
    $template = $template -Replace "${prefix}-", "`$`{prefix`}-"
}
if ($environment) {
    $template = $template -Replace "-${environment}-", "-`$`{environment`}-"
    $template = $template -Replace "\`"${environment}\`"", "`"`$`{environment`}`""
}
if ($subscription) {
    $template = $template -Replace "${subscription}", "`$`{subscription_guid`}"
}
if ($suffix) {
    $template = $template -Replace "-${suffix}", "-`$`{suffix`}"
    $template = $template -Replace "\`'${suffix}\`'", "'`$`{suffix`}'"
}
if ($appRGShort) {
    $template = $template -Replace "${appRGShort}", "`$`{paas_app_resource_group_short`}"
}
$template = $template -Replace "http[s?]://[\w\.]*iisapp[\w\.]*/", "`$`{iaas_app_url`}"
$template = $template -Replace "http[s?]://[\w\.]*webapp[\w\.]*/", "`$`{paas_app_url`}"
$template = $template -Replace "https://dev.azure.com[^`']*_build[^`']*`'", "`$`{build_web_url`}`'"
$template = $template -Replace "https://dev.azure.com[^`']*_release[^`']*`'", "`$`{release_web_url`}`'"
$template = $template -Replace "https://online.visualstudio.com[^`']*`'", "`$`{vso_url`}`'"

# Check for remnants of tokens that should've been caught
$enviromentMatches = $template -match $environment
$subscriptionMatches = $template -match $subscription
$suffixMatches = $template -match $suffix
if ($enviromentMatches) {
    Write-Host "Environment value '$environment' found in output:" -ForegroundColor Red
    $enviromentMatches
}
if ($subscriptionMatches) {
    Write-Host "Subscription GUID '$subscription' found in output:" -ForegroundColor Red
    $subscriptionMatches
}
if ($suffixMatches) {
    Write-Host "Suffix value '$suffix' found in output:" -ForegroundColor Red
    $suffixMatches
}
if ($enviromentMatches -or $subscriptionMatches -or $suffixMatches) {
    Write-Host "Aborting" -ForegroundColor Red
    exit 1
}

if (($DontWrite -eq $false) -or ($DontWrite -eq $null)) {
    $template | Out-File $OutputFilePath
    Write-Host "Saved template to $OutputFilePath"
} else {
    Write-Host "Skipped writing template" -ForegroundColor Yellow
}
if ($ShowTemplate) {
    #Write-Host $template
    Get-Content $OutputFilePath
}