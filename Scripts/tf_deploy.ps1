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

param  
( 
    [parameter(Mandatory=$false)][switch]$init=$false,
    [parameter(Mandatory=$false)][switch]$plan=$false,
    [parameter(Mandatory=$false)][switch]$validate=$false,
    [parameter(Mandatory=$false)][switch]$apply=$false,
    [parameter(Mandatory=$false)][switch]$destroy=$false,
    [parameter(Mandatory=$false)][switch]$output=$false,
    [parameter(Mandatory=$false)][switch]$force=$false,
    [parameter(Mandatory=$false,HelpMessage="The Terraform workspace to use")][string] $Workspace = "default",
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "Terraform"),
    [parameter(Mandatory=$false)][int]$trace=0
) 
if(-not($Workspace))    { Throw "You must supply a value for Workspace" }

# Configure instrumentation
Set-PSDebug -trace $trace
if (($trace -gt 0) -or (${env:system.debug} -eq "true"))
{
    $warningPreference = "Continue"
    $verbosePreference = "Continue"
    $debugPreference   = "Continue"

    Get-ChildItem -Hidden -System Env:* | Sort-Object
}
else {
    $warningPreference = "SilentlyContinue"
    $verbosePreference = "SilentlyContinue"
    $debugPreference   = "SilentlyContinue"
}
$ErrorActionPreference = "Stop"

#$pipeline = ![string]::IsNullOrEmpty($env:RELEASE_DEFINITIONID)
$workspaceLowercase = $Workspace.ToLower()
$planFile           = "$Workspace.tfplan".ToLower()

try {
    Push-Location $tfdirectory

    # Copy any secret files provided as part of an Azure Pipeline
    foreach ($file in $(Get-ChildItem Env:*SECUREFILEPATH))
    {
        Copy-Item $file.Value $tfdirectory
    }

    # Convert uppercased Terraform environment variables (Azure Pipeline Agent) to their original casing
    foreach ($tfvar in $(Get-ChildItem Env:TF_VAR_*))
    {
        $properCaseName = "TF_VAR_" + $tfvar.Name.Substring(7).ToLowerInvariant()
        Invoke-Expression "`$env:$properCaseName = `$env:$($tfvar.Name)"  
    }
    if (($trace -gt 0) -or (${env:system.debug} -eq "true"))
    {
        Get-ChildItem -Hidden -System Env:TF_VAR_* | Sort-Object
    }

    terraform -version
    if ($init) 
    {
        if([string]::IsNullOrEmpty($env:TF_VAR_backend_storage_account))   { Throw "You must set environment variable TF_VAR_backend_storage_account" }
        if([string]::IsNullOrEmpty($env:TF_VAR_backend_storage_container)) { Throw "You must set environment variable TF_VAR_backend_storage_container" }
        $tfbackendArgs = "-backend-config=`"container_name=${env:TF_VAR_backend_storage_container}`" -backend-config=`"storage_account_name=${env:TF_VAR_backend_storage_account}`""
        Write-Host "`nterraform init $tfbackendArgs" -ForegroundColor Green 
        terraform init -backend-config="container_name=${env:TF_VAR_backend_storage_container}" -backend-config="storage_account_name=${env:TF_VAR_backend_storage_account}"
    }

    # Workspace can only be selected after init 
    Invoke-Command -ScriptBlock {
        $Private:ErrorActionPreference = "Continue"
        terraform workspace new $workspaceLowercase 2>$null
    }
    terraform workspace select $workspaceLowercase
    terraform workspace list
    Write-Host "`nUsing Terraform workspace '$(terraform workspace show)'" -ForegroundColor Green 

    if ($validate) 
    {
        Write-Host "`nterraform validate" -ForegroundColor Green 
        terraform validate
    }

    if ($plan -or $apply -or $destroy)
    {
        # For Terraform apply & plan stages we need access to resources
        Write-Host "`nStart VM's, some operations (e.g. adding VM extensions) may fail if they're not started" -ForegroundColor Green 
        & (Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "start_vms.ps1") 

        Write-Host "`nPunch hole in PaaS Firewalls, otherwise terraform plan stage may fail" -ForegroundColor Green 
        & (Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "punch_hole.ps1") 

        Write-Host "`nterraform plan -out='$planFile'" -ForegroundColor Green 
        terraform plan -out="$planFile" #-input="$(!$force.ToString().ToLower())" 
    }
    
    if ($force)
    {
        $forceArgs = "-auto-approve"
    }
    if ($apply) 
    {
        if (!$force)
        {
            # Prompt to continue
            $proceedanswer = Read-Host "If you wish to proceed executing Terraform plan $planFile in workspace $workspaceLowercase, please reply 'yes' - null or N aborts"

            if ($proceedanswer -ne "yes")
            {
                Write-Host "`nReply is not 'yes' - Aborting " -ForegroundColor Red
                Exit
            }
        }

        Write-Host "`nterraform apply $forceArgs '$planFile'" -ForegroundColor Green 
        terraform apply $forceArgs "$planFile"
    }

    if ($output) 
    {
        Write-Host "`nterraform output" -ForegroundColor Green 
        terraform output
    }

    if ($destroy) 
    {
        Write-Host "`nterraform destroy" -ForegroundColor Green 
        terraform destroy $forceArgs
    }
}
finally 
{
    Pop-Location
}