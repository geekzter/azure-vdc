#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    Get the terraform version installed, latest available, or used before

#> 
param ( 
    [parameter(Mandatory=$false)][ValidateSet('Installed','Latest','Preferred')][string]$Version="Installed",
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "Terraform")
) 

function GetLatestTerraformVersion() {
    return Invoke-WebRequest -Uri https://checkpoint-api.hashicorp.com/v1/check/terraform -UseBasicParsing | Select-Object -ExpandProperty Content | ConvertFrom-Json | Select-Object -ExpandProperty "current_version"
}

$pipeline = ![string]::IsNullOrEmpty($env:AGENT_VERSION)

switch ($Version) {
    'Installed'   {
        $result = terraform -v | Select-String -Pattern '(?<version>[\d\.]+)'
        $terraformInstalledVersion = $result.Matches[0].Groups['version'].Value

        Write-Output $terraformInstalledVersion      
        if ($pipeline) {
            Write-Host “##vso[task.setvariable variable=InstalledVersion;isSecret=false;isOutput=true;]$terraformInstalledVersion"
            Write-Host “##vso[task.setvariable variable=Version;isSecret=false;isOutput=true;]$terraformInstalledVersion"
        }
    }
    'Latest'      {
        $terraformLatestVersion = GetLatestTerraformVersion

        Write-Output $terraformLatestVersion      
        if ($pipeline) {
            Write-Host “##vso[task.setvariable variable=Version;isSecret=false;isOutput=true;]$terraformLatestVersion”
            Write-Host “##vso[task.setvariable variable=LatestVersion;isSecret=false;isOutput=true;]$terraformLatestVersion”
        }
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
        
        Write-Output $terraformPreferredVersion      
        if ($pipeline) {
            Write-Host “##vso[task.setvariable variable=Version;isSecret=false;isOutput=true;]$terraformPreferredVersion"
            Write-Host “##vso[task.setvariable variable=PreferredVersion;isSecret=false;isOutput=true;]$terraformPreferredVersion"
        }
    }
}