#!/usr/bin/env pwsh

param (
    [parameter(Mandatory=$false)][string]$workspace
)

Push-Location (Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent "Terraform")

$currentWorkspace = $(terraform workspace list | Select-String -Pattern \* | %{$_ -Replace ".* ",""} 2> $null)
if ($workspace) {
    terraform workspace select $workspace
} else {
    $workspace = $(terraform workspace show)
}

try {
    $backupPath = [system.io.path]::GetTempPath()
    Write-Host "Backups will be saved in $backupPath"
    foreach($resource in $(terraform state list)) {
        Write-Host -NoNewline "Removing $resource from Terraform workspace ${workspace}: "
        terraform state rm -backup="$backupPath" $resource
    }
} finally {
    # Ensure this always runs
    if ($currentWorkspace) {
        terraform workspace select $currentWorkspace
    }
    Pop-Location
}