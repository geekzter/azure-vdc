#!/usr/bin/env pwsh

param (
    [parameter(Mandatory=$false)][string]$workspace
)

Push-Location (Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent "Terraform")

$currentWorkspace = $(terraform workspace show)
if ($workspace) {
    terraform workspace select $workspace
} else {
    $workspace = $(terraform workspace show)
}

try {
    # terraform state rm does not remove output (anymore)
    # Manipulate the state directly instead
    $tfState = terraform state pull | ConvertFrom-Json
    $tfState.outputs = New-Object PSObject
    $tfState.resources = @()
    $tfState | ConvertTo-Json
    $tfState | ConvertTo-Json | terraform state push -force -
} finally {
    # Ensure this always runs
    if ($currentWorkspace) {
        terraform workspace select $currentWorkspace
    }
    Pop-Location
}