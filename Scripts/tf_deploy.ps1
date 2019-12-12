#!/usr/bin/env pwsh

<# 
.SYNOPSIS 
    Deploys Azure resources using Terraform
 
.DESCRIPTION 
    This script is a wrapper around Terraform. It is provided for convenience only, as it works around some limitations in the demo. 
    E.g. terraform might need resources to be started before executing, and resources may not be accessible from the current locastion (IP address).

.EXAMPLE
    ./tf_deploy.ps1 -apply
#> 

### Arguments
param ( 
    [parameter(Mandatory=$false,HelpMessage="Initialize Terraform backend, modules & provider")][switch]$Init=$false,
    [parameter(Mandatory=$false,HelpMessage="Perform Terraform plan stage")][switch]$Plan=$false,
    [parameter(Mandatory=$false,HelpMessage="Perform Terraform validate stage")][switch]$Validate=$false,
    [parameter(Mandatory=$false,HelpMessage="Perform Terraform apply stage (implies plan)")][switch]$Apply=$false,
    [parameter(Mandatory=$false,HelpMessage="Perform Terraform destroy stage")][switch]$Destroy=$false,
    [parameter(Mandatory=$false,HelpMessage="Show Terraform output variables")][switch]$Output=$false,
    [parameter(Mandatory=$false,HelpMessage="Don't show prompts")][switch]$Force=$false,
    [parameter(Mandatory=$false,HelpMessage="Initialize Terraform backend, upgrade modules & provider")][switch]$Upgrade=$false,
    [parameter(Mandatory=$false,HelpMessage="Clears Terraform worksoace before starting")][switch]$Clear=$false,
    [parameter(Mandatory=$false,HelpMessage="The Terraform workspace to use")][string] $Workspace = "default",
    [parameter(Mandatory=$false,HelpMessage="Don't use Terraform resource_suffix variable if output exists")][switch]$StickySuffix=$false,
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "Terraform"),
    [parameter(Mandatory=$false)][int]$Parallelism=10, # Lower this to 10 if you run into rate limits
    [parameter(Mandatory=$false)][string]$subscription=$env:ARM_SUBSCRIPTION_ID,
    [parameter(Mandatory=$false)][string]$tenantid=$env:ARM_TENANT_ID,
    [parameter(Mandatory=$false)][string]$clientid=$env:ARM_CLIENT_ID,
    [parameter(Mandatory=$false)][string]$clientsecret=$env:ARM_CLIENT_SECRET,
    [parameter(Mandatory=$false)][int]$Trace=0
) 

### Internal Functions
. (Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) functions.ps1)

### Validation
if (!($Workspace)) { Throw "You must supply a value for Workspace" }
#if (!(Get-Module Az)) { Throw "Az modules not loaded"}

Write-Host $MyInvocation.line -ForegroundColor Green
PrintCurrentBranch

### Main routine
# Configure instrumentation
Set-PSDebug -trace $Trace
if ((${env:system.debug} -eq "true") -or ($env:system_debug -eq "true") -or ($env:SYSTEM_DEBUG -eq "true")) {
    # Increase debug information consistent with Azure Pipeline debug setting
    $Trace = 2
}
switch ($Trace) {
    0 {
        $Script:informationPreference = "SilentlyContinue"
        $Script:warningPreference = "SilentlyContinue"
        $Script:verbosePreference = "SilentlyContinue"
        $Script:debugPreference   = "SilentlyContinue"    
        #Remove-Item Env:TF_LOG -ErrorAction SilentlyContinue
    }
    1 {
        $Script:warningPreference = "Continue"
        $Script:informationPreference = "Continue"
        $Script:verbosePreference = "Continue"
        $Script:debugPreference   = "SilentlyContinue"
        $env:TF_LOG="TRACE"
        $env:TF_LOG_PATH="terraform.log"

        Get-ChildItem -Hidden -System Env:* | Sort-Object -Property Name
    }
    Default {
        $Script:warningPreference = "Continue"
        $Script:informationPreference = "Continue"
        $Script:verbosePreference = "Continue"
        $Script:debugPreference   = "Continue"      
        $env:TF_LOG="TRACE"
        $env:TF_LOG_PATH="terraform.log"

        Get-ChildItem -Hidden -System Env:* | Sort-Object -Property Name
    }
}
if ($env:TF_LOG_PATH -and (Test-Path $env:TF_LOG_PATH))
{
   # Clear log file
   Remove-Item $env:TF_LOG_PATH
}
$Script:ErrorActionPreference = "Stop"

$pipeline = ![string]::IsNullOrEmpty($env:AGENT_VERSION)
if ($pipeline -or $Force) {
    $env:TF_IN_AUTOMATION="true"
    $env:TF_INPUT=0
}
$WorkspaceLowercase = $Workspace.ToLower()
$PlanFile           = "$Workspace.tfplan".ToLower()
$varsFile           = "$Workspace.tfvars".ToLower()

try {
    Push-Location $tfdirectory

    # Copy any secret files provided as part of an Azure Pipeline
    foreach ($file in $(Get-ChildItem Env:*SECUREFILEPATH))
    {
        Copy-Item $file.Value $tfdirectory
    }

    $env:TF_VAR_branch=GetCurrentBranch

    # Convert uppercased Terraform environment variables (Azure Pipeline Agent) to their original casing
    foreach ($tfvar in $(Get-ChildItem -Path Env: -Recurse -Include TF_CFG_*,TF_VAR_*)) {
        $properCaseName = $tfvar.Name.Substring(0,7) + $tfvar.Name.Substring(7).ToLowerInvariant()
        Invoke-Expression "`$env:$properCaseName = `$env:$($tfvar.Name)"  
    } 
    if (($Trace -gt 0) -or (${env:system.debug} -eq "true")) {
        Get-ChildItem -Path Env: -Recurse -Include ARM_*,TF_CFG_*,TF_VAR_* | Sort-Object -Property Name
    }

    terraform -version
    if ($Init -or $Upgrade) {
        if([string]::IsNullOrEmpty($env:TF_CFG_backend_storage_account))   { Throw "You must set environment variable TF_CFG_backend_storage_account" }
        $tfbackendArgs = "-backend-config=`"storage_account_name=${env:TF_CFG_backend_storage_account}`""
        $InitCmd = "terraform init $tfbackendArgs"
        if ($Upgrade) {
            $InitCmd += " -upgrade"
        }
        Invoke "`n$InitCmd" 
    }

    # Workspace can only be selected after init 
    Invoke-Command -ScriptBlock {
        $Private:ErrorActionPreference = "Continue"
        terraform workspace new $WorkspaceLowercase 2>$null
    }
    terraform workspace select $WorkspaceLowercase
    Write-Host "Terraform workspaces:" -ForegroundColor White
    terraform workspace list
    Write-Host "Using Terraform workspace '$(terraform workspace show)'" 

    if ($Validate) {
        Invoke "`nterraform validate" 
    }
    
    # Prepare common arguments
    if ($Force) {
        $ForceArgs = "-auto-approve"
    }

    if (!(Get-ChildItem Env:TF_VAR_* -Exclude TF_VAR_branch, TF_VAR_paas_app_database_import) -and (Test-Path $varsFile)) {
        # Load variables from file, if it exists and environment variables have not been set
        $varArgs = "-var-file='$varsFile'"
    }

    if ($Clear) {
        # Clear Terraform workspace
        & (Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "tf_clear_state.ps1") 
    }

    if ($Plan -or $Apply -or $Destroy) {
        # For Terraform apply, plan & destroy stages we need access to resources, and for destroy as well sometimes
        Write-Host "`nStart VM's, some operations (e.g. adding VM extensions) may fail if they're not started" -ForegroundColor Green 
        & (Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "start_vms.ps1") 

        Write-Host "`nPunch hole in PaaS Firewalls, otherwise terraform plan stage may fail" -ForegroundColor Green 
        & (Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "punch_hole.ps1")

    }

    if ($Plan -or $Apply) {
        SetDatabaseImport
        if ($StickySuffix) {
            SetSuffix
        }
        Invoke "terraform plan $varArgs -parallelism=$Parallelism -out='$PlanFile'" 
    }

    if ($Apply) {
        if (!$Force) {
            # Prompt to continue
            Write-Host "If you wish to proceed executing Terraform plan $PlanFile in workspace $WorkspaceLowercase, please reply 'yes' - null or N aborts" -ForegroundColor Cyan
            $proceedanswer = Read-Host 

            if ($proceedanswer -ne "yes") {
                Write-Host "`nReply is not 'yes' - Aborting " -ForegroundColor Yellow
                Exit
            }
        }

        Invoke "terraform apply $ForceArgs -parallelism=$Parallelism '$PlanFile'"
    }

    if ($Output) {
        Write-Host "`nterraform output" -ForegroundColor Green 
        terraform output
    }

    if (($Apply -or $Output) -and $pipeline) {
        # Export Terraform output as Pipeline output variables for subsequent tasks
        SetPipelineVariablesFromTerraform
    }

    if ($Destroy) {
        # Delete resources created with ARM templates, Terraform doesn't know about those
        DeleteArmResources

        # Now let Terraform do it's work
        Invoke "terraform destroy $ForceArgs -parallelism=$Parallelism"
    }
} catch {
    # Useful info to debug potential network exceptions
    $ipAddress=$(Invoke-RestMethod http://ipinfo.io/json | Select-Object -exp ip)
    Write-Host "Connected from IP address: $ipAddress"
    # Rethrow exception
    throw
} finally {
    Pop-Location
}
