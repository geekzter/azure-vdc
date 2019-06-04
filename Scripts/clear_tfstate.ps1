#!/usr/bin/env pwsh

param(
    [parameter(Mandatory=$false)][string]$workspace
)

Push-Location (Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent "Terraform")

$currentWorkspace = $(terraform workspace list | Select-String -Pattern \* | %{$_ -Replace ".* ",""} 2> $null)
if ($workspace)
{
    terraform workspace select $workspace
}

try 
{
    foreach($resource in $(terraform state list)) {
        Write-Host -NoNewline "removing $resource from Terraform state: "
        terraform state rm $resource
    }
}
finally
{
    # Ensure this always runs
    if ($currentWorkspace)
    {
        terraform workspace select $currentWorkspace
    }
}

Pop-Location