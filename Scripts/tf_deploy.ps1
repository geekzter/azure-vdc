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
    [parameter(Mandatory=$false)][string]$backendStorageAccount=$env:TF_VAR_BACKEND_STORAGE_ACCOUNT, # Uppercase so it works in Azure Pipelines (uppercase) as well as in PowerShell Core client (case insensitive)
    [parameter(Mandatory=$false)][string]$backendStorageContainer="vdc",
    [parameter(Mandatory=$false)][int]$trace=0
) 
if(-not($workspace))    { Throw "You must supply a value for Workspace" }

# Configure instrumentation
Set-PSDebug -trace $trace
if (${env:system.debug} -eq "true") {
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

$pipeline = ![string]::IsNullOrEmpty($env:RELEASE_DEFINITIONID)
if ($pipeline -or $force) {
    $env:TF_IN_AUTOMATION="true"
    $env:TF_INPUT=0
}
$workspaceLowercase = $workspace.ToLower()
$planFile           = "$workspace.tfplan".ToLower()
$varsFile           = "$workspace.tfvars".ToLower()

# HACK: Make sure we're (still) using Terraform 0.11
if ($IsMacOS) {
    $terraformPath = "/usr/local/opt/terraform@0.11/bin"
    if (!$env:PATH.Contains($terraformPath))
    {
        # Insert Terraform 0.11 into path
        [System.Collections.ArrayList]$pathArray = $env:PATH.Split(":")
        $pathArray.Insert(1,$terraformPath)
        $env:PATH = $pathArray -Join ":"
    }
}

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
        if([string]::IsNullOrEmpty($backendStorageAccount))   { Throw "You pass argument backendStorageAccount" }
        if([string]::IsNullOrEmpty($backendStorageContainer)) { Throw "You pass argument backendStorageContainer" }
        $tfbackendArgs = "-backend-config=`"container_name=${backendStorageContainer}`" -backend-config=`"storage_account_name=${backendStorageAccount}`""
        Write-Host "`nterraform init $tfbackendArgs" -ForegroundColor Green 
        terraform init -backend-config="container_name=${backendStorageContainer}" -backend-config="storage_account_name=${backendStorageAccount}"
    }

    # Workspace can only be selected after init 
    Invoke-Command -ScriptBlock {
        $Private:ErrorActionPreference = "Continue"
        terraform workspace new $workspaceLowercase 2>$null
    }
    terraform workspace select $workspaceLowercase
    terraform workspace list
    Write-Host "`nUsing Terraform workspace '$(terraform workspace show)'" -ForegroundColor Green 

    if ($validate) {
        Write-Host "`nterraform validate" -ForegroundColor Green 
        terraform validate
    }
    
    # Prepare common arguments
    if ($force) {
        $forceArgs = "-auto-approve"
    }
    if ($(Test-Path $varsFile)) {
        $varArgs = "-var-file=$varsFile"
    }

    if ($plan -or $apply -or $destroy) {
        # For Terraform apply & plan stages we need access to resources, and for destroy as well sometimes
        Write-Host "`nStart VM's, some operations (e.g. adding VM extensions) may fail if they're not started" -ForegroundColor Green 
        & (Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "start_vms.ps1") 

        Write-Host "`nPunch hole in PaaS Firewalls, otherwise terraform plan stage may fail" -ForegroundColor Green 
        & (Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "punch_hole.ps1") 

        Write-Host "`nterraform plan $varArgs -out='$planFile'" -ForegroundColor Green 
        terraform plan $varArgs -out="$planFile" #-input="$(!$force.ToString().ToLower())" 
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

        Write-Host "`nterraform apply $forceArgs '$planFile'" -ForegroundColor Green 
        terraform apply $forceArgs "$planFile"
    }

    if ($output) {
        Write-Host "`nterraform output" -ForegroundColor Green 
        terraform output
    }

    if ($destroy) {
        Write-Host "`nterraform destroy" -ForegroundColor Green 
        terraform destroy $forceArgs
    }
} finally {
    Pop-Location
}