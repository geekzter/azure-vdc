#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    This script creates/updates dashboard.tpl with updates made to the dashboard in the Azure Portal
.DESCRIPTION 
    This template updated/created (dashboard.tpl) is a Terraform template. This script will replace literals with template tokens as needed, such that new deployments will use values pertaining to that deployment.
#> 
param ( 
    [parameter(Mandatory=$false)][string]$InputFile,
    [parameter(Mandatory=$false)][string]$OutputFile="dashboard.tpl",
    [parameter(Mandatory=$false)][string]$Workspace=$env:TF_WORKSPACE,
    [parameter(Mandatory=$false)][switch]$Force=$false,
    [parameter(Mandatory=$false)][switch]$ShowTemplate=$false,
    [parameter(Mandatory=$false)][switch]$DontWrite=$false,
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "Terraform"),
    [parameter(Mandatory=$false)][string]$subscription=$env:ARM_SUBSCRIPTION_ID
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
    $priorWorkspace = (SetWorkspace -Workspace $Workspace -ShowWorkspaceName).PriorWorkspaceName

    Invoke-Command -ScriptBlock {
        $Private:ErrorActionPreference = "Continue"
        $Script:dashboardID    = $(terraform output "dashboard_id"                   2>$null)
        $Script:appInsightsID  = $(terraform output "application_insights_id"        2>$null)
        $Script:appRGShort     = $(terraform output "paas_app_resource_group_short"  2>$null)
        $Script:prefix         = $(terraform output "resource_prefix"                2>$null)
        $Script:suffix         = $(terraform output "resource_suffix"                2>$null)
        $Script:environment    = $(terraform output "resource_environment"           2>$null)
        $Script:sharedRegistry = $(terraform output "shared_container_registry_name" 2>$null)
        $Script:sharedRG       = $(terraform output "shared_resources_group"         2>$null)
    }

    if ([string]::IsNullOrEmpty($prefix) -or [string]::IsNullOrEmpty($environment) -or [string]::IsNullOrEmpty($suffix)) {
        Write-Host "Resources have not yet been, or are being created. Nothing to do" -ForegroundColor Yellow
        exit 
    }
} finally {
    $null = SetWorkspace -Workspace $priorWorkspace
    Pop-Location
}

if ($InputFile) {
    Write-Host "Reading from file $InputFile..." -ForegroundColor Green
    $template = (Get-Content $InputFilePath -Raw) 
    $template = $($template | jq '.properties') # Use jq, ConvertFrom-Json does not parse properly
} else {
    Write-Host "Retrieving resource $dashboardID..." -ForegroundColor Green
    $template = az resource show --ids $dashboardID --query "properties" -o json
}


$template = $template -Replace "/subscriptions/........-....-....-................./", "`$`{subscription`}/"
if ($appInsightsID) {
    $template = $template -Replace "${appInsightsID}", "`$`{appinsights_id`}"
}
if ($prefix) {
    $template = $template -Replace "${prefix}-", "`$`{prefix`}-"
}
if ($environment) {
    $template = $template -Replace "-${environment}-", "-`$`{environment`}-"
    $template = $template -Replace "\`"${environment}\`"", "`"`$`{environment`}`""
}

if ($env:ARM_SUBSCRIPTION_ID) {
    $subscription = $env:ARM_SUBSCRIPTION_ID
} else {
    $subscription = $(az account show --query "id" -o tsv)
}
if ($subscription) {
    $template = $template -Replace "${subscription}", "`$`{subscription_guid`}"
}
if ($suffix) {
    $template = $template -Replace "-${suffix}", "-`$`{suffix`}"
    $template = $template -Replace "\`'${suffix}\`'", "'`$`{suffix`}'"
}
if ($prefix -and $environment -and $suffix) {
    $template = $template -Replace "${prefix}${environment}${suffix}", "`$`{prefix`}`$`{environment`}`$`{suffix`}"
}
if ($appRGShort) {
    $template = $template -Replace "${appRGShort}", "`$`{paas_app_resource_group_short`}"
}
$template = $template -Replace "http[s?]://[\w\.]*iisapp[\w\.]*/", "`$`{iaas_app_url`}"
$template = $template -Replace "http[s?]://[\w\.]*webapp[\w\.]*/", "`$`{paas_app_url`}"
$template = $template -Replace "https://dev.azure.com[^`']*_build[^`']*`'", "`$`{build_web_url`}`'"
$template = $template -Replace "https://dev.azure.com[^`']*_release[^`']*`'", "`$`{release_web_url`}`'"
$template = $template -Replace "https://online.visualstudio.com[^`']*`'", "`$`{vso_url`}`'"
$template = $template -Replace "[\w]*\.portal.azure.com", "portal.azure.com"
$template = $template -Replace "@microsoft.onmicrosoft.com", "@"
$template = $template -Replace "/resourceGroups/${sharedRG}", "/resourceGroups/`$`{shared_rg`}"
$template = $template -Replace "/registries/${sharedRegistry}", "/registries/`$`{container_registry_name`}"

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