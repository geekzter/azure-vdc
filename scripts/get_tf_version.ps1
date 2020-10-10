#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    Get the terraform version installed, latest available, or used before

#> 
#Requires -Version 7

param ( 
    [parameter(Mandatory=$false)][ValidateSet('Installed','Latest','Preferred','State')][string]$Version,
    [parameter(Mandatory=$false)][switch]$ValidateInstalledVersion,
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "terraform")
) 

function GetLatestTerraformVersion() {
    return Invoke-WebRequest -Uri https://checkpoint-api.hashicorp.com/v1/check/terraform -UseBasicParsing | Select-Object -ExpandProperty Content | ConvertFrom-Json | Select-Object -ExpandProperty "current_version"
}
function GetTerraformVersion(
    [ValidateSet('Installed','Latest','Preferred','State')][string]$Version="Installed",
    [bool]$GeneratePipelineOutput=$false
) {   
    switch ($Version) {
        'Installed'   {
            $result = terraform -v | Select-String -Pattern '(?<version>[\d\.]+)'
            $terraformInstalledVersion = $result.Matches[0].Groups['version'].Value
             if ($GeneratePipelineOutput) {
                Write-Host “##vso[task.setvariable variable=InstalledVersion;isSecret=false;isOutput=true;]$terraformInstalledVersion"
                Write-Host “##vso[task.setvariable variable=Version;isSecret=false;isOutput=true;]$terraformInstalledVersion"
            }
            return $terraformInstalledVersion
        }
        'Latest'      {
            $terraformLatestVersion = GetLatestTerraformVersion
            if ($GeneratePipelineOutput) {
                Write-Host “##vso[task.setvariable variable=Version;isSecret=false;isOutput=true;]$terraformLatestVersion”
                Write-Host “##vso[task.setvariable variable=LatestVersion;isSecret=false;isOutput=true;]$terraformLatestVersion”
            }
            return $terraformLatestVersion
        }
        'Preferred'    {
            $tfenvFile = Join-Path $tfdirectory ".terraform-version"
            if (Test-Path $tfenvFile) {
                $terraformPreferredVersion = Get-Content $tfenvFile -TotalCount 1
            }
            if ([string]::IsNullOrEmpty($terraformPreferredVersion) -or ($terraformPreferredVersion -ieq "latest"))
            {
                # Preferred version not specified, take the latest 
                $terraformPreferredVersion = GetLatestTerraformVersion
            }            
            if ($GeneratePipelineOutput) {
                Write-Host “##vso[task.setvariable variable=Version;isSecret=false;isOutput=true;]$terraformPreferredVersion"
                Write-Host “##vso[task.setvariable variable=PreferredVersion;isSecret=false;isOutput=true;]$terraformPreferredVersion"
            }
            return $terraformPreferredVersion
        }
        'State'    {
            $tfState = terraform state pull 2>$null | ConvertFrom-Json
            if ($tfState) {
                $terraformStateVersion = $tfState.terraform_version
                if ($GeneratePipelineOutput) {
                    Write-Host “##vso[task.setvariable variable=Version;isSecret=false;isOutput=true;]$terraformStateVersion"
                    Write-Host “##vso[task.setvariable variable=StateVersion;isSecret=false;isOutput=true;]$terraformStateVersion"
                }
                return $terraformStateVersion
            }
        }
    }
}

if ($Version) {
    $pipeline = ![string]::IsNullOrEmpty($env:AGENT_VERSION)
    Write-Output $(GetTerraformVersion -Version $Version -GeneratePipelineOutput $pipeline)
}

if ($ValidateInstalledVersion) {
    $installedVersion = (GetTerraformVersion -Version Installed)
    $preferredVersion = (GetTerraformVersion -Version Preferred)
    $stateVersion = (GetTerraformVersion -Version State)

    if ($installedVersion -ne $preferredVersion) {
        Write-Warning "Installed Terraform version $installedVersion is different from preferred version $preferredVersion specified in $(Join-Path $tfdirectory .terraform-version) (read by tfenv)"
    }
    if ($stateVersion) {
        if ($installedVersion -lt $stateVersion) {
            Write-Warning "Installed Terraform version $installedVersion is older than version $stateVersion used to create Terraform state"
        }
    } else {
        $stateStdPlusError = $(terraform state pull 2>&1) 
        if ($stateStdPlusError -match "\[\d+m") {
            # Escape code in output, Terraform is complaining
            Write-Warning $stateStdPlusError
        }
    }
}