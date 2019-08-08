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
    [parameter(Mandatory=$false)][switch]$init=$false,
    [parameter(Mandatory=$false)][switch]$plan=$false,
    [parameter(Mandatory=$false)][switch]$validate=$false,
    [parameter(Mandatory=$false)][switch]$apply=$false,
    [parameter(Mandatory=$false)][switch]$destroy=$false,
    [parameter(Mandatory=$false)][switch]$output=$false,
    [parameter(Mandatory=$false)][switch]$force=$false,
    [parameter(Mandatory=$false,HelpMessage="The Terraform workspace to use")][string] $workspace = "default",
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "Terraform"),
    [parameter(Mandatory=$false)][int]$parallelism=10, # Lower this to 10 if you run into rate limits
    [parameter(Mandatory=$false)][string]$subscription=$env:ARM_SUBSCRIPTION_ID,
    [parameter(Mandatory=$false)][string]$tenantid=$env:ARM_TENANT_ID,
    [parameter(Mandatory=$false)][string]$clientid=$env:ARM_CLIENT_ID,
    [parameter(Mandatory=$false)][string]$clientsecret=$env:ARM_CLIENT_SECRET,
    [parameter(Mandatory=$false)][int]$trace=0
) 

### Internal Functions
function AzLogin () {
    if (!(Get-AzTenant -TenantId $tenantid -ErrorAction SilentlyContinue)) {
        if(-not($clientid)) { Throw "You must supply a value for clientid" }
        if(-not($clientsecret)) { Throw "You must supply a value for clientsecret" }
        # Use Terraform ARM Backend config to authenticate to Azure
        $secureClientSecret = ConvertTo-SecureString $clientsecret -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ($clientid, $secureClientSecret)
        Connect-AzAccount -Tenant $tenantid -Subscription $subscription -ServicePrincipal -Credential $credential
    }
    Set-AzContext -Subscription $subscription -Tenant $tenantid
}

function DeleteArmResources () {
    # Delete resources created with ARM templates, Terraform doesn't know about those
    Invoke-Command -ScriptBlock {
        $Private:ErrorActionPreference = "Continue"
        $Script:armResourceIDs = terraform output -json arm_resource_ids 2>$null
    }
    if ($armResourceIDs) {
        Write-Host "Removing resources created in embedded ARM templates, this may take a while (no concurrency)..." -ForegroundColor Green
        # Log on to Azure if not already logged on
        AzLogin
        
        $stopWatch = New-Object -TypeName System.Diagnostics.Stopwatch       
        $armResourceIDs | ConvertFrom-Json | ForEach-Object {
            $resourceId = $_[0]
            Write-Host "Removing [id=$resourceId]..."
            $removed = $false
            $stopWatch.Reset()
            $stopWatch.Start()
            if ($force) {
                $removed = Remove-AzResource -ResourceId $resourceId -ErrorAction "SilentlyContinue" -Force
            } else {
                $removed = Remove-AzResource -ResourceId $resourceId -ErrorAction "SilentlyContinue"
            }
            $stopWatch.Stop()
            if ($removed) {
                # Mimic Terraform formatting
                $elapsed = $stopWatch.Elapsed.ToString("m'm's's'")
                Write-Host "Removed [id=$resourceId, ${elapsed} elapsed]" -ForegroundColor White
            }
        }
    }
}
function SetPipelineVariablesFromTerraform () {
    $json = terraform output -json | ConvertFrom-Json -AsHashtable
    foreach ($outputVariable in $json.keys) {
        $value = $json[$outputVariable].value
        if ($value) {
            # Write variable output in the format a Pipeline can understand
            # https://github.com/Microsoft/azure-pipelines-agent/blob/master/docs/preview/outputvariable.md
            Write-Host "##vso[task.setvariable variable=$outputVariable;isOutput=true]$value"
        }
    }
}

### Validation
if (!($workspace)) { Throw "You must supply a value for Workspace" }
#if (!(Get-Module Az)) { Throw "Az modules not loaded"}

### Main routine
# Configure instrumentation
Set-PSDebug -trace $trace
if ((${env:system.debug} -eq "true") -or ($env:system_debug -eq "true") -or ($env:SYSTEM_DEBUG -eq "true")) {
    # Increase debug information consistent with Azure Pipeline debug setting
    $trace = 2
}
switch ($trace) {
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
        #$env:TF_LOG="TRACE"
        #$env:TF_LOG_PATH="terraform.log"

        Get-ChildItem -Hidden -System Env:* | Sort-Object
    }
    Default {
        $Script:warningPreference = "Continue"
        $Script:informationPreference = "Continue"
        $Script:verbosePreference = "Continue"
        $Script:debugPreference   = "Continue"      
        #$env:TF_LOG="TRACE"
        #$env:TF_LOG_PATH="terraform.log"

        Get-ChildItem -Hidden -System Env:* | Sort-Object
    }
}
#if ($env:TF_LOG_PATH -and (Test-Path $env:TF_LOG_PATH))
#{
#    # Clear log file
#    Remove-Item $env:TF_LOG_PATH
#}
$Script:ErrorActionPreference = "Stop"

$pipeline = ![string]::IsNullOrEmpty($env:AGENT_VERSION)
if ($pipeline -or $force) {
    $env:TF_IN_AUTOMATION="true"
    $env:TF_INPUT=0
}
$workspaceLowercase = $workspace.ToLower()
$planFile           = "$workspace.tfplan".ToLower()
$varsFile           = "$workspace.tfvars".ToLower()

try {
    Push-Location $tfdirectory

    # Copy any secret files provided as part of an Azure Pipeline
    foreach ($file in $(Get-ChildItem Env:*SECUREFILEPATH))
    {
        Copy-Item $file.Value $tfdirectory
    }

    # Convert uppercased Terraform environment variables (Azure Pipeline Agent) to their original casing
    foreach ($tfvar in $(Get-ChildItem Env:TF_VAR_*)) {
        $properCaseName = "TF_VAR_" + $tfvar.Name.Substring(7).ToLowerInvariant()
        Invoke-Expression "`$env:$properCaseName = `$env:$($tfvar.Name)"  
    } 
    if (($trace -gt 0) -or (${env:system.debug} -eq "true")) {
        Get-ChildItem -Hidden -System Env:TF_VAR_* | Sort-Object
    }

    terraform -version
    if ($init) {
        if([string]::IsNullOrEmpty($env:TF_backend_storage_account))   { Throw "You must set environment variable TF_backend_storage_account" }
        $tfbackendArgs = "-backend-config=`"storage_account_name=${env:TF_backend_storage_account}`""
        Write-Host "`nterraform init $tfbackendArgs" -ForegroundColor Green 
        terraform init -backend-config="storage_account_name=${env:TF_backend_storage_account}"
    }

    # Workspace can only be selected after init 
    Invoke-Command -ScriptBlock {
        $Private:ErrorActionPreference = "Continue"
        terraform workspace new $workspaceLowercase 2>$null
    }
    terraform workspace select $workspaceLowercase
    Write-Host "Terraform workspaces:" -ForegroundColor White
    terraform workspace list
    Write-Host "Using Terraform workspace '$(terraform workspace show)'" 

    if ($validate) {
        Write-Host "`nterraform validate" -ForegroundColor Green 
        terraform validate
    }
    
    # Prepare common arguments
    if ($force) {
        $forceArgs = "-auto-approve"
    }

    if (!(Get-ChildItem Env:TF_VAR_*) -and (Test-Path $varsFile)) {
        # Load variables from file, if it exists and environment variables have not been set
        $varArgs = "-var-file='$varsFile'"
    }

    if ($plan -or $apply -or $destroy) {
        # For Terraform apply, plan & destroy stages we need access to resources, and for destroy as well sometimes
        Write-Host "`nStart VM's, some operations (e.g. adding VM extensions) may fail if they're not started" -ForegroundColor Green 
        & (Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "start_vms.ps1") 

        Write-Host "`nPunch hole in PaaS Firewalls, otherwise terraform plan stage may fail" -ForegroundColor Green 
        & (Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "punch_hole.ps1") 
    }

    if ($plan -or $apply) {
        $planCmd = "terraform plan $varArgs -parallelism=$parallelism -out='$planFile'"
        Write-Host "`n$planCmd" -ForegroundColor Green 
        Invoke-Expression "$planCmd"
    }

    if ($apply) {
        if (!$force) {
            # Prompt to continue
            $proceedanswer = Read-Host "If you wish to proceed executing Terraform plan $planFile in workspace $workspaceLowercase, please reply 'yes' - null or N aborts"

            if ($proceedanswer -ne "yes") {
                Write-Host "`nReply is not 'yes' - Aborting " -ForegroundColor Red
                Exit
            }
        }

        $applyCmd = "terraform apply $forceArgs -parallelism=$parallelism '$planFile'"
        Write-Host "`n$applyCmd" -ForegroundColor Green 
        Invoke-Expression $applyCmd

        # Export Terraform output as Pipeline output variables for subsequent tasks
        if ($pipeline) {
            SetPipelineVariablesFromTerraform
        }
    }

    if ($output) {
        Write-Host "`nterraform output" -ForegroundColor Green 
        terraform output
    }

    if ($destroy) {
        # Delete resources created with ARM templates, Terraform doesn't know about those
        DeleteArmResources

        # Now let Terraform do it's work
        $destroyCmd = "terraform destroy $forceArgs -parallelism=$parallelism"
        Write-Host "`n$destroyCmd" -ForegroundColor Green 
        Invoke-Expression $destroyCmd
    }
} finally {
    Pop-Location
}
