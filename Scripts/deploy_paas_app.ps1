#!/usr/bin/env pwsh

param (    
    [parameter(Mandatory=$false,HelpMessage="The workspace tag to filter use")][string] $Workspace,
    [parameter(Mandatory=$false)][string]$subscription=$env:ARM_SUBSCRIPTION_ID,
    [parameter(Mandatory=$false)][string]$tenantid=$env:ARM_TENANT_ID,
    [parameter(Mandatory=$false)][string]$clientid=$env:ARM_CLIENT_ID,
    [parameter(Mandatory=$false)][string]$clientsecret=$env:ARM_CLIENT_SECRET,
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "Terraform")
) 

try {
    Push-Location $tfdirectory
    if ($MyInvocation.InvocationName -ne "&") {
        Write-Host "Using Terraform workspace '$(terraform workspace show)'" 
    }
    
    Invoke-Command -ScriptBlock {
        $Private:ErrorActionPreference = "Continue"
        $Script:appResourceGroup       = $(terraform output "paas_app_resource_group" 2>$null)
        $Script:appAppServiceName      = $(terraform output "paas_app_service_name"   2>$null)
        $Script:appUrl                 = $(terraform output "paas_app_url"            2>$null)
        $Script:devOpsOrgUrl           = $(terraform output "devops_org_url"          2>$null)
        $Script:devOpsProject          = $(terraform output "devops_project"          2>$null)
    }

    if ([string]::IsNullOrEmpty($appAppServiceName)) {
        Write-Host "Resources have not been created, nothing to do deploy" -ForeGroundColor Yellow
        exit 
    }
} finally {
    Pop-Location
}
$buildDefinitionName = "asp.net-sql-ci" # From asp.net-sql-ci.yml
$packageName = "ZipDeploy.zip" # From asp.net-sql-ci.yml
$tmpDir = [System.IO.Path]::GetTempPath()

# We need this for Azure DevOps
az extension add --name azure-devops 

# Set defaults
az account set --subscription $subscription
az devops configure --defaults organization=$devOpsOrgUrl project=$devOpsProject

$runid = $(az pipelines runs list --result succeeded --top 1 --query "[?definition.name == '$buildDefinitionName'].id | [0]")
Write-Information "Last successful run of $buildDefinitionName is $runid"

# Download pipeline artifact (build artifact won't work)
Write-Host "Downloading artifacts from from build $runid to $tmpDir..."
az pipelines runs artifact download --run-id $runid --artifact-name aspnetsql2 --path $tmpDir

# Publish web app
Write-Host "Publishing $packageName to web app $appAppServiceName..."
$null = az webapp deployment source config-zip -g $appResourceGroup -n $appAppServiceName --src $tmpDir/$packageName

Write-Host "Web app $appAppServiceName published at $appUrl"

# Test & Warm up 
$maxTests = 60
$test = 0
Write-Host "Testing $appUrl (max $maxTests times)..." -NoNewLine
while (!$responseOK -and ($test -lt $maxTests)) {
    try {
        $test++
        Write-Host "." -NoNewLine
        $homePageResponse = Invoke-WebRequest -UseBasicParsing -Uri $appUrl
    }
    catch {
        $responseOK = $false
        if ($test -ge $maxTests) {
            throw
        } else {
            Start-Sleep -Milliseconds 500
        }
    }
}
Write-Host "✓" # Force NewLine
Write-Host "Request to $appUrl completed with HTTP Status Code $($homePageResponse.StatusCode)"