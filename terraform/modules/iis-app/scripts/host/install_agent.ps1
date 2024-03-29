#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    Installs and configures Azure Pipeline Agent on target
#> 
param ( 
    [parameter(Mandatory=$false)][string]$AgentName=$env:COMPUTERNAME,
    [parameter(Mandatory=$true)][string]$Environment,
    [parameter(Mandatory=$true)][string[]]$Tags,
    [parameter(Mandatory=$true)][string]$Organization,
    [parameter(Mandatory=$true)][string]$Project,
    [parameter(Mandatory=$true)][string]$PAT
) 
Set-PSDebug -Trace 1 # Trace in the case the extension doesn't successfully load
$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue' # Improves batch performance of Invoke-Webrequest in Windows PowerShell
Write-Host $MyInvocation.line
if (!$IsWindows -and ($PSVersionTable.PSEdition -ine "Desktop")) {
    Write-Error "This only runs on Windows..."
    exit 1
}

$pipelineDirectory = Join-Path $env:ProgramFiles pipeline-agent
$agentService = "vstsagent.${Organization}.${Environment}.${AgentName}"
if (Test-Path (Join-Path $pipelineDirectory .agent)) {
    Write-Host "Agent $AgentName already installed, removing first..."
    Push-Location $pipelineDirectory 
    Stop-Service $agentService
    .\config.cmd remove --unattended --auth pat --token $PAT
}

# Get latest released version from GitHub
$agentVersion = $(Invoke-Webrequest -Uri https://api.github.com/repos/microsoft/azure-pipelines-agent/releases/latest -UseBasicParsing | ConvertFrom-Json | Select-Object -ExpandProperty name) -replace "v",""
$agentPackage = "vsts-agent-win-x64-${agentVersion}.zip"
$agentUrl = "https://vstsagentpackage.azureedge.net/agent/${agentVersion}/${agentPackage}"

$null = New-Item -ItemType directory -Path $pipelineDirectory -Force
Push-Location $pipelineDirectory 
Write-Host "Retrieving agent from ${agentUrl}..."
Invoke-Webrequest -Uri $agentUrl -UseBasicParsing -OutFile $agentPackage #-MaximumRetryCount 9
Write-Host "Extracting ${agentPackage} in ${pipelineDirectory}..."
Expand-Archive -Path $agentPackage -DestinationPath $pipelineDirectory -Force
Write-Host "Extracted ${agentPackage}"

# Use work directory that does not contain spaces, and is located at the designated OS location for data
$pipelineWorkDirectory = "$($env:ProgramData)\pipeline-agent\_work"
$null = New-Item -ItemType Directory -Path $pipelineWorkDirectory -Force

# Unattended config
# https://docs.microsoft.com/en-us/azure/devops/pipelines/agents/v2-windows?view=azure-devops#unattended-config
# https://github.com/microsoft/azure-pipelines-agent/blob/master/src/Agent.Listener/CommandLine/ConfigureAgent.cs
Write-Host "Creating agent ${AgentName} and adding it to environment ${Environment} in proiect ${Project} and organization ${Organization}..."
.\config.cmd --environment --environmentname $Environment `
             --agent $AgentName --replace `
             --addvirtualmachineresourcetags --virtualmachineresourcetags "$($Tags -join ',')" `
             --runasservice `
             --work $pipelineWorkDirectory `
             --url "https://dev.azure.com/${Organization}/" `
             --projectname $Project `
             --auth pat --token $PAT `
             --acceptTeeEula `
             --windowsLogonAccount "NT AUTHORITY\SYSTEM" `
             --unattended
# Start Service
Start-Service $agentService
sc.exe config $agentService start=auto
