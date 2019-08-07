#!/usr/bin/env pwsh

$terraformVersion = Invoke-WebRequest -Uri https://checkpoint-api.hashicorp.com/v1/check/terraform -UseBasicParsing | Select-Object -ExpandProperty Content | ConvertFrom-Json | Select-Object -ExpandProperty "current_version"

Write-Host $terraformVersion

$pipeline = ![string]::IsNullOrEmpty($env:AGENT_VERSION)
if ($pipeline) {
    Write-Host “##vso[task.setvariable variable=LatestVersion;isSecret=false;isOutput=true;]$terraformVersion”
}
