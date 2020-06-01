#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    Wait for Pipeline Environment agents to come online
#> 
param ( 
    [Parameter(Mandatory=$true,
    ParameterSetName="ResourceGroup")]
    [String]
    $ResourceGroup,

    [Parameter(Mandatory=$true,
    ParameterSetName="Environment")]
    [String]
    $Environment,
    [Parameter(Mandatory=$true,
    ParameterSetName="Environment")]
    [String]
    $OrganizationUrl,
    [Parameter(Mandatory=$true,
    ParameterSetName="Environment")]
    [String]
    $Project,
    [Parameter(Mandatory=$false,
    ParameterSetName="Environment")]
    [String[]]
    $Tags,

    #[parameter(Mandatory=$true)][string]$ResourceGroup,
    [parameter(Mandatory=$false)][int]$TimeoutSeconds=300
) 
Write-Host $MyInvocation.line

function Build-AgentQuery (
    [string[]]$Tags,
    [string]$Attribute,
    [switch]$Offline
) {
    [string]$query = "?"
    if ($Tags) {
        foreach ($tag in $Tags) {
            $query += "contains(tags,'$Tag') && "
        }
    }
    if ($Offline) {
        $query += " agent.status=='offline' && "
    }
    $query += " agent.enabled"

    $jmesPath = "value[$query].agent"
    if ($Attribute) {
        $jmesPath += ".$Attribute"
    }
    return $jmesPath
}


if ($Environment) {
    $extensionExists = $(az extension list --query "[?name=='azure-devops']" -o tsv) 
    if (!$extensionExists) {
        az extension add -y -n azure-devops
    }

    #$apiVersion="6.0-preview"
    $apiVersion="5.2-preview"

    # Discover appropriate arguments using this information:
    # az devops invoke --org $OrganizationUrl --query "[?area=='environments']"  
    $environmentId = $(az devops invoke --org $OrganizationUrl --area environments --api-version $apiVersion --route-parameters project=$Project resource=environments --resource environments --query "value[?name=='$Environment'].id" -o tsv)
    #$agentQuery = "value[?contains(tags,'$Tag') && agent.enabled].agent.name"
    $agentQuery = Build-AgentQuery -Tags $Tags -Attribute "name"
    $agents = $(az devops invoke --org $OrganizationUrl --area environments --api-version $apiVersion --route-parameters project=$Project environmentId=$environmentId --resource vmresource --query "$agentQuery" -o tsv)
    if (!$agents) {
        Write-Warning "This command didn't yield any output:"
        Write-Warning "az devops invoke --org $OrganizationUrl --area environments --api-version $apiVersion --route-parameters project=$Project environmentId=$environmentId --resource vmresource --query `"$agentQuery`" -o tsv"
        Write-Error "No agents found"
        exit
    }
    Write-Host "Checking status of environment agents $agents..."
    #$offlineAgentQuery = "value[?contains(tags,'$Tag') && agent.enabled && agent.status=='offline'].agent.name"
    $offlineAgentQuery = Build-AgentQuery -Tags $Tags -Attribute "name" -Offline
    $offlineAgents = $(az devops invoke --org $OrganizationUrl --area environments --api-version $apiVersion --route-parameters project=$Project environmentId=$environmentId --resource vmresource --query "$offlineAgentQuery" -o tsv)
    $waitUntil = (Get-Date).AddSeconds($TimeoutSeconds)
    if ($offlineAgents) {
        Write-Host "Waiting for $offlineAgents to come online ..." -NoNewline
    }
    while ($offlineAgents -and ((Get-Date) -lt $waitUntil)) {
        Write-Host "." -NoNewLine
        $offlineAgents = $(az devops invoke --org $OrganizationUrl --area environments --api-version $apiVersion --route-parameters project=$Project environmentId=$environmentId --resource vmresource --query "$offlineAgentQuery" -o tsv)
        Start-Sleep -Seconds 5
    }
    Write-Host "✓" # Force NewLine
}

if ($ResourceGroup) {
    $vmIDs = $(az vm list -g $ResourceGroup --query "[].id" -o tsv)

    # Wait for stable state, VM's may be restarting now
    az vm wait --updated --ids $vmIDs -o none
    
    Write-Information "Retrieving last VM status change timestamp..."
    $startTimeString = (az vm get-instance-view --ids $vmIDs --query "max([].instanceView.statuses[].time)" -o tsv)
    
    if ($startTimeString) {
        Write-Host "Last VM started $startTimeString"
        $startTime = [datetime]::Parse($startTimeString)
        $waitUntil = $startTime.AddSeconds($TimeoutSeconds)
    } else {
        $waitUntil = (Get-Date).AddSeconds($TimeoutSeconds)
    }
    
    $sleepTime = ($waitUntil - (Get-Date))
    
    if ($sleepTime -gt 0) {
        Write-Host "Sleeping $([math]::Ceiling($sleepTime.TotalSeconds)) seconds..."
        Start-Sleep -Milliseconds $sleepTime.TotalMilliseconds
    }
}