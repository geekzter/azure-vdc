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
    [parameter(Mandatory=$false)][string]$Workspace=$env:TF_WORKSPACE,
    [parameter(Mandatory=$false)][switch]$Destroy,
    [parameter(Mandatory=$false)][switch]$Force=$false,
    [parameter(Mandatory=$false)][switch]$Wait=$false,
    [parameter(Mandatory=$false)][int]$TimeoutMinutes=5,
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "Terraform")
)
if (!($Workspace)) { Throw "You must supply a value for Workspace" }

$application = "Automated VDC"

. (Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) functions.ps1)

try {
    Push-Location $tfdirectory
    $priorWorkspace = (SetWorkspace -Workspace $Workspace -ShowWorkspaceName).PriorWorkspaceName
    $Workspace = $(terraform workspace show) # Ensure this is always populated

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
    $null = SetWorkspace -Workspace $priorWorkspace
    Pop-Location
}

if ($Destroy) {
    if (!$Force) {
        Write-Host "If you wish to proceed removing resources? `nplease reply 'yes' - null or N aborts" -ForegroundColor Cyan
        $proceedanswer = Read-Host
        if ($proceedanswer -ne "yes") {
            exit
        }
    }
    $jobs = @()
    # Remove resource groups 
    # Async operation, as they have unique suffixes that won't clash with new deployments
    Write-Host "Removing VDC resource groups (async)..."
    $resourceGroupIDs = $(az group list --query "[?tags.workspace == '${Workspace}' && tags.application == '${application}'].id" -o tsv)
    if ($resourceGroupIDs) {
        $jobs += Start-Job -Name "Remove ResourceGroups" -ScriptBlock {az resource delete --ids $args} -ArgumentList $resourceGroupIDs
    }

    # Remove resources in the NetworkWatcher resource group
    Write-Host "Removing VDC network watchers from shared resource group 'NetworkWatcherRG' (async)..."
    $resourceIDs = $(az resource list -g NetworkWatcherRG --query "[?tags.workspace == '${Workspace}' && tags.application == '${application}'].id" -o tsv)
    if ($resourceIDs) {
        $jobs += Start-Job -Name "Remove Resources from NetworkWatcherRG" -ScriptBlock {az resource delete --ids $args} -ArgumentList $resourceIDs
    }

    # Remove DNS records using tags expressed as record level metadata
    # Synchronous operation, as records will clash with new deployments
    Write-Host "Removing VDC records from shared DNS zone (sync)..."
    $dnsZones = $(az network dns zone list | ConvertFrom-Json)
    foreach ($dnsZone in $dnsZones) {
        Write-Verbose "Processing zone '$($dnsZone.name)'..."
        $dnsResourceIDs = $(az network dns record-set list -g $dnsZone.resourceGroup -z $dnsZone.name --query "[?metadata.workspace == '${Workspace}' && metadata.application == '${application}'].id" -o tsv)
        if ($dnsResourceIDs) {
            az resource delete --ids $dnsResourceIDs -o none
        }
    }

    $jobs | Format-Table -Property Id, Name, State
    if ($Wait -and $jobs) {
        # Waiting for async operations to complete
        WaitForJobs -Jobs $jobs -TimeoutMinutes $TimeoutMinutes
    }
}