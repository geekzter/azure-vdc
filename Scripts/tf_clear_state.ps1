#!/usr/bin/env pwsh

<# 
.SYNOPSIS 
    Clears the state of a Terraform workspace, and optionally destroys the resources in that workspace
 
.DESCRIPTION 
    This script destroys resources independent from Terraform, as background job. 
    Therefore it is the fastest way to 'start over' with a clean workspace.

.EXAMPLE
    ./tf_clear_state.ps1 -Workspace test -Destroy
#> 

param (
    [parameter(Mandatory=$false)][string]$Workspace,
    [parameter(Mandatory=$false)][switch]$Destroy,
    [parameter(Mandatory=$false)][switch]$Force=$false,
    [parameter(Mandatory=$false)][switch]$Wait=$false,
    [parameter(Mandatory=$false)][int]$Timeout=300,
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "Terraform"),
    [parameter(Mandatory=$false)][string]$subscription=$env:ARM_SUBSCRIPTION_ID,
    [parameter(Mandatory=$false)][string]$tenantid=$env:ARM_TENANT_ID,
    [parameter(Mandatory=$false)][string]$clientid=$env:ARM_CLIENT_ID,
    [parameter(Mandatory=$false)][string]$clientsecret=$env:ARM_CLIENT_SECRET
)

. (Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) functions.ps1)

try {
    Push-Location $tfdirectory

    if ($Workspace) {
        $currentWorkspace = $(terraform workspace show)
        terraform workspace select $Workspace
    } else {
        $Workspace = $(terraform workspace show)
    }

    Write-Host "Clearing Terraform workspace '$Workspace'..." -ForegroundColor Green

    # 'terraform state rm' does not remove output (anymore)
    # HACK: Manipulate the state directly instead
    $tfState = terraform state pull | ConvertFrom-Json
    if ($tfState -and $tfState.outputs) {
        $tfState.outputs = New-Object PSObject # Empty output
        $tfState.resources = @() # No resources
        $tfState.serial++
        $tfState | ConvertTo-Json | terraform state push -
        if ($LASTEXITCODE -ne 0) {
            exit
        }
        terraform state pull 
    } else {
        Write-Host "Terraform state not valid" -ForegroundColor Red
        exit
    }
} finally {
    # Ensure this always runs
    if ($currentWorkspace) {
        terraform workspace select $currentWorkspace
    }
    Pop-Location
}

if ($Destroy) {
    AzLogin

    # Remove resources in the NetworkWatcher resource group
    $resources = Get-AzResource -ResourceGroupName "NetworkWatcherRG" -Tag @{workspace=$Workspace}
    $resources | Remove-AzResource -Force

    # Remove resource groups
    $resourceGroups = Get-AzResourceGroup -Tag @{workspace=$Workspace}
    if ((RemoveResourceGroups $resourceGroups -Force $Force)) {
        $stopWatch = New-Object -TypeName System.Diagnostics.Stopwatch     
        $stopWatch.Start()

        $jobs = Get-Job | Where-Object {$_.Command -like "Remove-AzResourceGroup"}
        $jobs | Format-Table -Property Id, Name, State
        if ($Wait) {
            Write-Host "Waiting for jobs to complete..."
            $waitStatus = Wait-Job -Job $jobs -Timeout $Timeout
            if ($waitStatus) {
                $stopWatch.Stop()
                $elapsed = $stopWatch.Elapsed.ToString("m'm's's'")
                $jobs | Format-Table -Property Id, Name, State
                Write-Host "Jobs completed in $elapsed"
            } else {
                $jobs | Format-Table -Property Id, Name, State
                Write-Warning "Jobs did not complete before timeout (${Timeout}s) expired"
                exit 1
            }
        }
    } else {
        Write-Host "Nothing found to delete for workspace $Workspace"
    }
}