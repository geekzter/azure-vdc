#!/usr/bin/env pwsh

param (
    [parameter(Mandatory=$false)][string]$Workspace
)

Push-Location (Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent "Terraform")

$currentWorkspace = $(terraform workspace show)
if ($Workspace) {
    terraform workspace select $Workspace
} else {
    $Workspace = $(terraform workspace show)
}

try {
    # 'terraform state rm' does not remove output (anymore)
    # HACK: Manipulate the state directly instead
    $tfState = terraform state pull | ConvertFrom-Json
    $tfState.outputs = New-Object PSObject # Empty output
    $tfState.resources = @() # No resources
    $tfState.serial++
    $tfState | ConvertTo-Json
    $tfState | ConvertTo-Json | terraform state push -
} finally {
    # Ensure this always runs
    if ($currentWorkspace) {
        terraform workspace select $currentWorkspace
    }
    Pop-Location
}