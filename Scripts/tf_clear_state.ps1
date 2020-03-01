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
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "Terraform"),
    [parameter(Mandatory=$false)][string]$subscription=$env:ARM_SUBSCRIPTION_ID,
    [parameter(Mandatory=$false)][string]$tenantid=$env:ARM_TENANT_ID,
    [parameter(Mandatory=$false)][string]$clientid=$env:ARM_CLIENT_ID,
    [parameter(Mandatory=$false)][string]$clientsecret=$env:ARM_CLIENT_SECRET
)
if (!($Workspace)) { Throw "You must supply a value for Workspace" }

$application = "Automated VDC"

. (Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) functions.ps1)

# Log on to Azure if not already logged on
AzLogin

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
    AzLogin

    # Remove resource groups 
    # Async operation, as they have unique suffixes that won't clash with new deployments
    Write-Host "Removing VDC resource groups (async)..."
    $resourceGroups = Get-AzResourceGroup -Tag @{workspace=$Workspace}
    $stopWatch = New-Object -TypeName System.Diagnostics.Stopwatch     
    if ((RemoveResourceGroups $resourceGroups -Force $Force)) {
        $stopWatch.Start()
    } else {
        Write-Host "No resource group found to delete for workspace $Workspace"
    }

    # Remove resources in the NetworkWatcher resource group
    Write-Host "Removing VDC network watchers from shared resource group 'NetworkWatcherRG' (async)..."
    $resources = Get-AzResource -ResourceGroupName "NetworkWatcherRG" -Tag @{workspace=$Workspace}
    $resources | Remove-AzResource -Force -AsJob

    # Remove DNS records using tags expressed as record level metadata
    # Synchronous operation, as records will clash with new deployments
    Write-Host "Removing VDC records from shared DNS zone (sync)..."
    foreach ($dnsZone in $(Get-AzDnsZone)) {
        Write-Verbose "Processing zone '$($dnsZone.Name)'..."
        $dnsRecords = Get-AzDnsRecordSet -Zone $dnsZone
        foreach ($dnsRecord in $dnsRecords) {
            Write-Verbose "Processing record '$($dnsRecord.Name).$($dnsZone.Name)'..."
            if ($dnsRecord.Metadata -and `
                $dnsRecord.Metadata["application"] -eq $application -and `
                $dnsRecord.Metadata["workspace"] -eq $Workspace) {
                Write-Information "Removing record '$($dnsRecord.Name).$($dnsZone.Name)'..."
                Remove-AzDnsRecordSet -RecordSet $dnsRecord
            }
        }
    }

    $jobs = Get-Job | Where-Object {$_.Command -match "Remove-Az"}
    $jobs | Format-Table -Property Id, Name, State
    if ($Wait -and $jobs) {
        # Waiting for async operations to complete
        WaitForJobs -Jobs $jobs -TimeoutMinutes $TimeoutMinutes
    }
}