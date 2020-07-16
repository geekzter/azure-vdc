#!/usr/bin/env pwsh

$repoDirectory = (Split-Path (get-childitem diagram.vsdx -Path ~ -Recurse).FullName -Parent)
$scriptDirectory = Join-Path $repoDirectory "scripts"

# Manage PATH environment variable
[System.Collections.ArrayList]$pathList = $env:PATH.Split(":")
if (!$pathList.Contains($scriptDirectory)) {
    $pathList.Insert(1,$scriptDirectory)
}
$env:PATH = $pathList -Join ":"

$env:SHELL = (Get-Command pwsh).Source

# Let Terraform know which Codespace is running it
$env:TF_VAR_vso_url="https://online.visualstudio.com/environment/$env:CLOUDENV_ENVIRONMENT_ID"

Set-Location $repoDirectory