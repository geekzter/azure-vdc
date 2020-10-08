#!/usr/bin/env pwsh

<# 
.SYNOPSIS 
    Clears the state of a Terraform workspace, and destroys resources 
 
.DESCRIPTION 
    This script destroys resources independent from Terraform, as background job. 
    Therefore it is the fastest way to 'start over' with a clean workspace.

.EXAMPLE
    ./erase.ps1 -Workspace test -Destroy

.EXAMPLE
    ./erase.ps1 -Suffix b1234 -Destroy
#> 
#Requires -Version 7

[CmdletBinding(DefaultParameterSetName="Workspace")]
param (
    [parameter(Mandatory=$false,ParameterSetName="Workspace")]
    [string]
    $Workspace=$env:TF_WORKSPACE,
    
    [parameter(Mandatory=$false,ParameterSetName="DeploymentName")]
    [string]
    $DeploymentName,
    
    [parameter(Mandatory=$false,ParameterSetName="Suffix")]
    [string[]]
    $Suffix,
    
    [parameter(Mandatory=$false,ParameterSetName="Workspace")]
    [bool]
    $ClearTerraformState=$true,
    
    [switch]
    $Destroy=$false,
    
    [parameter(Mandatory=$false)]
    [switch]
    $Force=$false,

    [parameter(Mandatory=$false)]
    [switch]
    $Wait=$false,

    [parameter(Mandatory=$false)]
    [int]
    $TimeoutMinutes=50,

    [parameter(Mandatory=$false)]
    [string]
    $tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "terraform")
)
Write-Host $MyInvocation.line -ForegroundColor Green

$application = "Automated VDC"

. (Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) functions.ps1)

if ($ClearTerraformState -and ($PSCmdlet.ParameterSetName -ieq "Workspace")) {
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
        . (Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) get_tf_version.ps1) -ValidateInstalledVersion
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
    $tagQuery = "[?tags.application == '${application}' && properties.provisioningState != 'Deleting'].id"
    switch ($PSCmdlet.ParameterSetName) {
        "DeploymentName" {
            $tagQuery = $tagQuery -replace "\]", " && tags.deployment == '${DeploymentName}']"
        }
        "Suffix" {
            $suffixQuery = "("
            foreach ($suff in $Suffix) {
                if ($suffixQuery -ne "(") {
                    $suffixQuery += " || "
                }
                $suffixQuery += "tags.suffix == '${suff}'"
            }
            $suffixQuery += ")"
            $tagQuery = $tagQuery -replace "\]", " && $suffixQuery]"
        }
        "Workspace" {
            $tagQuery = $tagQuery -replace "\]", " && tags.workspace == '${Workspace}']"
        }
    }
    Write-Host "Removing resources which match JMESPath `"$tagQuery`"" -ForegroundColor Green

    # Remove resource groups 
    # Async operation, as they have unique suffixes that won't clash with new deployments
    Write-Host "Removing VDC resource groups (async)..."
    $resourceGroupIDs = $(az group list --query "$tagQuery" -o tsv)
    if ($resourceGroupIDs -and $resourceGroupIDs.Length -gt 0) {
        Write-Verbose "Starting job 'az resource delete --ids $resourceGroupIDs'"
        Start-Job -Name "Remove ResourceGroups" -ScriptBlock {az resource delete --ids $args} -ArgumentList $resourceGroupIDs | Out-Null
    }

    # Remove resources in the NetworkWatcher resource group
    Write-Host "Removing VDC network watchers from shared resource group 'NetworkWatcherRG' (async)..."
    $resourceIDs = $(az resource list -g NetworkWatcherRG --query "$tagQuery" -o tsv)
    if ($resourceIDs -and $resourceIDs.Length -gt 0) {
        Write-Verbose "Starting job 'az resource delete --ids $resourceIDs'"
        Start-Job -Name "Remove Resources from NetworkWatcherRG" -ScriptBlock {az resource delete --ids $args} -ArgumentList $resourceIDs | Out-Null
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
            Write-Information "Removing DNS records from zone '$($dnsZone.name)'..."
            az resource delete --ids $dnsResourceIDs -o none
        }
    }

    $jobs = Get-Job -State Running | Where-Object {$_.Command -match "az resource"}
    $jobs | Format-Table -Property Id, Name, Command, State
    if ($Wait -and $jobs) {
        # Waiting for async operations to complete
        WaitForJobs -Jobs $jobs -TimeoutMinutes $TimeoutMinutes
    }
}