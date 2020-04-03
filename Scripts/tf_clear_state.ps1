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
    [parameter(Mandatory=$false)][string]$Environment,
    [parameter(Mandatory=$false)][switch]$Destroy,
    [parameter(Mandatory=$false)][switch]$Force=$false,
    [parameter(Mandatory=$false)][switch]$Wait=$false,
    [parameter(Mandatory=$false)][int]$TimeoutMinutes=5,
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "Terraform")
)
if (!$Workspace -and !$Environment) { 
    Write-Warning "You must supply a value for either Environment or Workspace" 
    exit
}
if ($Workspace -and $Environment) { 
    Write-Warning "You must supply a value for either Environment or Workspace (not both)" 
}
if ($Environment) {
    # Environment provided as argument
    $backendFile = (Join-Path $tfdirectory backend.tf)
    if (Test-Path $backendFile) {
        Write-Warning "Terraform backend configured at $backendFile, please provide Workspace argument instead of Environment"
        exit
    }
}
$application = "Automated VDC"

. (Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) functions.ps1)

if ($Workspace -or $Environment) {
    try {
        # Local backend, prompt the user to clear
        if (!$Force) {
            Write-Host "Do you wish to proceed clearing terraform state? `nplease reply 'yes' - null or N aborts" -ForegroundColor Cyan
            $proceedanswer = Read-Host
            if ($proceedanswer -ne "yes") {
                break
            }
        }
        Push-Location $tfdirectory
        if ($Workspace) {
            $priorWorkspace = (SetWorkspace -Workspace $Workspace -ShowWorkspaceName).PriorWorkspaceName      
        }
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
        if ($priorWorkspace) {
            $null = SetWorkspace -Workspace $priorWorkspace
        }
        Pop-Location
    }
}

if ($Destroy) {
    if (!$Force) {
        $proceedanswer = $null
        Write-Host "Do you wish to proceed removing resources? `nplease reply 'yes' - null or N aborts" -ForegroundColor Cyan
        $proceedanswer = Read-Host
        if ($proceedanswer -ne "yes") {
            exit
        }
    }
    $jobs = @()
    if ($Workspace) {
        $tagQuery = "[?tags.workspace == '${Workspace}' && tags.application == '${application}'].id"
        Write-Host "Removing resources with tags workspace='${Workspace}' and application='${application}'..." -ForegroundColor Green
    } else {
        Write-Host "Removing resources with tags environment='${Environment}' and application='${application}'..." -ForegroundColor Green
        $tagQuery = "[?tags.environment == '${Environment}' && tags.application == '${application}'].id"
    }
    Write-Information "JMESPath Tags Query: $tagQuery"
    # Remove resource groups 
    # Async operation, as they have unique suffixes that won't clash with new deployments
    Write-Host "Removing VDC resource groups (async)..."
    $resourceGroupIDs = $(az group list --query "$tagQuery" -o tsv)
    if ($resourceGroupIDs) {
        $jobs += Start-Job -Name "Remove ResourceGroups" -ScriptBlock {az resource delete --ids $args} -ArgumentList $resourceGroupIDs
    }

    # Remove resources in the NetworkWatcher resource group
    Write-Host "Removing VDC network watchers from shared resource group 'NetworkWatcherRG' (async)..."
    $resourceIDs = $(az resource list -g NetworkWatcherRG --query "$tagQuery" -o tsv)
    if ($resourceIDs) {
        $jobs += Start-Job -Name "Remove Resources from NetworkWatcherRG" -ScriptBlock {az resource delete --ids $args} -ArgumentList $resourceIDs
    }

    $metadataQuery = $tagQuery -replace "tags\.","metadata."
    Write-Information "JMESPath Metadata Query: $metadataQuery"
    # Remove DNS records using tags expressed as record level metadata
    # Synchronous operation, as records will clash with new deployments
    Write-Host "Removing VDC records from shared DNS zone (sync)..."
    $dnsZones = $(az network dns zone list | ConvertFrom-Json)
    foreach ($dnsZone in $dnsZones) {
        Write-Verbose "Processing zone '$($dnsZone.name)'..."
        $dnsResourceIDs = $(az network dns record-set list -g $dnsZone.resourceGroup -z $dnsZone.name --query "$metadataQuery" -o tsv)
        if ($dnsResourceIDs) {
            Write-Host "Removing DNS records  from zone '$($dnsZone.name)' with metadata environment='${Environment}' and application='${application}'..." -ForegroundColor Green
            az resource delete --ids $dnsResourceIDs -o none
        }
    }

    $jobs | Format-Table -Property Id, Name, State
    if ($Wait -and $jobs) {
        # Waiting for async operations to complete
        WaitForJobs -Jobs $jobs -TimeoutMinutes $TimeoutMinutes
    }
}