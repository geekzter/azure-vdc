#!/usr/bin/env pwsh

$repoDirectory = (Split-Path (get-childitem README.md -Path ~ -Recurse).FullName -Parent)
$scriptDirectory = Join-Path $repoDirectory "scripts"

# Manage PATH environment variable
[System.Collections.ArrayList]$pathList = $env:PATH.Split(":")
if (!$pathList.Contains($scriptDirectory)) {
    $pathList.Insert(1,$scriptDirectory)
}
$env:PATH = $pathList -Join ":"

Set-Location $repoDirectory