#!/usr/bin/env pwsh

& (Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "erase.ps1") -DeploymentName dflt -ClearTerraformState $false -Destroy