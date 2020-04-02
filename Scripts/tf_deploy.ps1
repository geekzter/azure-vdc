#!/usr/bin/env pwsh

<# 
.SYNOPSIS 
    Deploys Azure resources using Terraform
 
.DESCRIPTION 
    This script is a wrapper around Terraform. It is provided for convenience only, as it works around some limitations in the demo. 
    E.g. terraform might need resources to be started before executing, and resources may not be accessible from the current locastion (IP address).

.EXAMPLE
    ./tf_deploy.ps1 -apply -Workspace default
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
    [parameter(Mandatory=$false,HelpMessage="The Terraform workspace to use")][string]$Workspace=$env:TF_WORKSPACE,
    [parameter(Mandatory=$false,HelpMessage="Don't use Terraform resource_suffix variable if output exists")][switch]$StickySuffix=$false,
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "Terraform"),
    [parameter(Mandatory=$false)][int]$Parallelism=10, # Lower this to 10 if you run into rate limits
    [parameter(Mandatory=$false)][int]$Trace=0
) 

### Internal Functions
. (Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) functions.ps1)

### Validation
if (!($Workspace)) { Throw "You must supply a value for Workspace" }

Write-Host $MyInvocation.line -ForegroundColor Green
PrintCurrentBranch

AzLogin

### Main routine
# Configure instrumentation
Set-PSDebug -trace $Trace
if ((${env:system.debug} -eq "true") -or ($env:system_debug -eq "true") -or ($env:SYSTEM_DEBUG -eq "true")) {
    # Increase debug information consistent with Azure Pipeline debug setting
    Get-ChildItem -Hidden -System Env:* | Sort-Object -Property Name
}

$Script:ErrorActionPreference = "Stop"

$pipeline = ![string]::IsNullOrEmpty($env:AGENT_VERSION)
if ($pipeline -or $Force) {
    $env:TF_IN_AUTOMATION="true"
    $env:TF_INPUT=0
}

$planFile           = "$Workspace.tfplan".ToLower()
$varsFile           = "$Workspace.tfvars".ToLower()

try {
    Push-Location $tfdirectory

    # Copy any secret files provided as part of an Azure Pipeline
    foreach ($file in $(Get-ChildItem Env:*SECUREFILEPATH))
    {
        Copy-Item $file.Value $tfdirectory
    }

    # TODO: Do this from Terraform data.external data source
    $env:TF_VAR_branch=GetCurrentBranch

    # Convert uppercased Terraform environment variables (Azure Pipeline Agent) to their original casing
    foreach ($tfvar in $(Get-ChildItem -Path Env: -Recurse -Include TF_VAR_*)) {
        $properCaseName = $tfvar.Name.Substring(0,7) + $tfvar.Name.Substring(7).ToLowerInvariant()
        Invoke-Expression "`$env:$properCaseName = `$env:$($tfvar.Name)"  
    } 
    if (($Trace -gt 0) -or (${env:system.debug} -eq "true")) {
        Get-ChildItem -Path Env: -Recurse -Include ARM_*,TF_VAR_* | Sort-Object -Property Name
    }

    # Print version info
    $azModule = Get-Module Az -ListAvailable | Select-Object -First 1     
    Write-Host "PowerShell $($azModule.Name) v$($azModule.Version)"
    terraform -version

    if ($Init -or $Upgrade) {
        $backendFile = (Join-Path $tfdirectory backend.tf)
        $newBackend = (!(Test-Path $backendFile))
        $tfbackendArgs = ""
        if ($newBackend) {
            # Terraform azurerm backend does not exist, create one
            Copy-Item -Path "${backendFile}.sample" -Destination $backendFile
            
            if ($pipeline) {
                if (!$env:TF_VAR_backend_resource_group -or !$env:TF_VAR_backend_storage_account -or !$env:TF_VAR_backend_storage_container) {
                    Write-Error "Environment variables TF_VAR_backend_resource_group, TF_VAR_backend_storage_account, TF_VAR_backend_storage_container most all be set when creating a new backend from a pipeline"
                    exit
                } else {

                }
            } else {
                $tfbackendArgs += " -input=true"
            }
            $tfbackendArgs += " -reconfigure"
        }

        if ($env:TF_VAR_backend_resource_group) {
            $tfbackendArgs += " -backend-config=`"resource_group_name=${env:TF_VAR_backend_resource_group}`""
        }
        if ($env:TF_VAR_backend_storage_account) {
            $tfbackendArgs += " -backend-config=`"storage_account_name=${env:TF_VAR_backend_storage_account}`""
        }
        if ($env:TF_VAR_backend_storage_container) {
            $tfbackendArgs += " -backend-config=`"container_name=${env:TF_VAR_backend_storage_container}`""
        }

        $initCmd = "terraform init $tfbackendArgs"
        if ($Upgrade) {
            $initCmd += " -upgrade"
        }
        Invoke "`n$initCmd" 
    }

    # Workspace can only be selected after init 
    $priorWorkspace = (SetWorkspace -Workspace $Workspace -ShowWorkspaceName).PriorWorkspaceName

    if ($Validate) {
        Invoke "`nterraform validate" 
    }
    
    # Prepare common arguments
    if ($Force) {
        $ForceArgs = "-auto-approve"
    }

    if (!(Get-ChildItem Env:TF_VAR_* -Exclude TF_VAR_branch, TF_VAR_backend_storage_account) -and (Test-Path $varsFile)) {
        # Load variables from file, if it exists and environment variables have not been set
        $varArgs = "-var-file='$varsFile'"
    }

    if ($Clear) {
        # Clear Terraform workspace
        & (Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "tf_clear_state.ps1") 
    }

    if ($Plan -or $Apply -or $Destroy) {
        Write-Host "`nPunch hole in PaaS Firewalls, otherwise terraform may fail" -ForegroundColor Green 
        & (Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "punch_hole.ps1")
    }

    if ($Plan -or $Apply) {
        if ($StickySuffix) {
            SetSuffix
        }

        # Create plan
        Invoke "terraform plan $varArgs -parallelism=$Parallelism -out='$planFile'" 
    }

    if ($Apply) {
        if (!$Force) {
            # Prompt to continue
            Write-Host "If you wish to proceed executing Terraform plan $planFile in workspace $WorkspaceLowercase, please reply 'yes' - null or N aborts" -ForegroundColor Cyan
            $proceedanswer = Read-Host 

            if ($proceedanswer -ne "yes") {
                Write-Host "`nReply is not 'yes' - Aborting " -ForegroundColor Yellow
                Exit
            }
        }

        Invoke "terraform apply $ForceArgs -parallelism=$Parallelism '$planFile'"
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
        # Now let Terraform do it's work
        Invoke "terraform destroy $ForceArgs -parallelism=$Parallelism"
    }
} finally {
    $null = SetWorkspace -Workspace $priorWorkspace
    Pop-Location
}
