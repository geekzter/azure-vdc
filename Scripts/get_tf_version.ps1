#!/usr/bin/env pwsh

param ( 
    [parameter(Mandatory=$false)][ValidateSet('Installed','Latest')][string]$Version="Installed"
) 

$pipeline = ![string]::IsNullOrEmpty($env:AGENT_VERSION)

switch ($Version) {
    'Installed'   {
        $result = terraform -v | Select-String -Pattern '(?<version>[\d\.]+)'
        $terraformInstalledVersion = $result.Matches[0].Groups['version'].Value

        Write-Output $terraformInstalledVersion      
        if ($pipeline) {
            Write-Host “##vso[task.setvariable variable=InstalledVersion;isSecret=false;isOutput=true;]$terraformInstalledVersion"
        }
    }
    'Latest'      {
        $terraformLatestVersion = Invoke-WebRequest -Uri https://checkpoint-api.hashicorp.com/v1/check/terraform -UseBasicParsing | Select-Object -ExpandProperty Content | ConvertFrom-Json | Select-Object -ExpandProperty "current_version"

        Write-Output $terraformLatestVersion      
        if ($pipeline) {
            Write-Host “##vso[task.setvariable variable=LatestVersion;isSecret=false;isOutput=true;]$terraformLatestVersion”
        }
    }
}
