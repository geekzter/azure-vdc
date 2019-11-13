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
    [parameter(Mandatory=$false,HelpMessage="Initialize Terraform backend, modules & provider")][switch]$init=$false,
    [parameter(Mandatory=$false,HelpMessage="Perform Terraform plan stage")][switch]$plan=$false,
    [parameter(Mandatory=$false,HelpMessage="Perform Terraform validate stage")][switch]$validate=$false,
    [parameter(Mandatory=$false,HelpMessage="Perform Terraform apply stage (implies plan)")][switch]$apply=$false,
    [parameter(Mandatory=$false,HelpMessage="Perform Terraform destroy stage")][switch]$destroy=$false,
    [parameter(Mandatory=$false,HelpMessage="Show Terraform output variables")][switch]$output=$false,
    [parameter(Mandatory=$false,HelpMessage="Don't show prompts")][switch]$force=$false,
    [parameter(Mandatory=$false,HelpMessage="Initialize Terraform backend, upgrade modules & provider")][switch]$upgrade=$false,
    [parameter(Mandatory=$false,HelpMessage="Clears Terraform worksoace before starting")][switch]$clear=$false,
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
        Write-Host "Reconnecting to Azure with SPN..."
        if(-not($clientid)) { Throw "You must supply a value for clientid" }
        if(-not($clientsecret)) { Throw "You must supply a value for clientsecret" }
        # Use Terraform ARM Backend config to authenticate to Azure
        $secureClientSecret = ConvertTo-SecureString $clientsecret -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ($clientid, $secureClientSecret)
        $null = Connect-AzAccount -Tenant $tenantid -Subscription $subscription -ServicePrincipal -Credential $credential
    }
    $null = Set-AzContext -Subscription $subscription -Tenant $tenantid
}

function DeleteArmResources () {
    # Delete resources created with ARM templates, Terraform doesn't know about those
    Invoke-Command -ScriptBlock {
        $Private:ErrorActionPreference = "Continue"
        $Script:armResourceIDs = terraform output -json arm_resource_ids 2>$null
    }
    if ($armResourceIDs) {
        Write-Host "`nRemoving resources created in embedded ARM templates, this may take a while (no concurrency)..." -ForegroundColor Green
        # Log on to Azure if not already logged on
        AzLogin
        
        $stopWatch = New-Object -TypeName System.Diagnostics.Stopwatch       
        $resourceIds = $armResourceIDs | ConvertFrom-Json
        foreach ($resourceId in $resourceIds) {
            if (![string]::IsNullOrEmpty($resourceId)) {
                $resource = Get-AzResource -ResourceId $resourceId -ErrorAction "SilentlyContinue"
                if ($resource) {
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
                } else {
                    Write-Host "Resource [id=$resourceId] does not exist, nothing to remove"
                }
            }
        }
    }
}

function SetDatabaseImport () {
    Invoke-Command -ScriptBlock {
        $Private:ErrorActionPreference = "Continue"
        $script:sqlDatabase = $(terraform output "paas_app_sql_database" 2>$null)
    }

    if ([string]::IsNullOrEmpty($sqlDatabase)) {
        # Database does not exist, import on create
        $env:TF_VAR_paas_app_database_import="true"
        Write-Host "Database paas_app_sql_database does not exist. TF_VAR_paas_app_database_import=$env:TF_VAR_paas_app_database_import"
    } else {
        # Database already exists, don't import anything
        $env:TF_VAR_paas_app_database_import="false"
        Write-Host "Database $sqlDatabase already exists. TF_VAR_paas_app_database_import=$env:TF_VAR_paas_app_database_import"
    }
}

function Invoke (
    [string]$cmd
) {
    Write-Host "`n$cmd" -ForegroundColor Green 
    Invoke-Expression $cmd
    if ($LASTEXITCODE -ne 0) {
        exit
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

$MyInvocation.line
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
        $env:TF_LOG="TRACE"
        $env:TF_LOG_PATH="terraform.log"

        Get-ChildItem -Hidden -System Env:* | Sort-Object
    }
    Default {
        $Script:warningPreference = "Continue"
        $Script:informationPreference = "Continue"
        $Script:verbosePreference = "Continue"
        $Script:debugPreference   = "Continue"      
        $env:TF_LOG="TRACE"
        $env:TF_LOG_PATH="terraform.log"

        Get-ChildItem -Hidden -System Env:* | Sort-Object
    }
}
if ($env:TF_LOG_PATH -and (Test-Path $env:TF_LOG_PATH))
{
   # Clear log file
   Remove-Item $env:TF_LOG_PATH
}
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
    foreach ($tfvar in $(Get-ChildItem -Path Env: -Recurse -Include TF_CFG_*,TF_VAR_*)) {
        $properCaseName = $tfvar.Name.Substring(0,7) + $tfvar.Name.Substring(7).ToLowerInvariant()
        Invoke-Expression "`$env:$properCaseName = `$env:$($tfvar.Name)"  
    } 
    if (($trace -gt 0) -or (${env:system.debug} -eq "true")) {
        Get-ChildItem -Path Env: -Recurse -Include ARM_*,TF_CFG_*,TF_VAR_* | Sort-Object -Property Name
    }

    terraform -version
    if ($init -or $upgrade) {
        if([string]::IsNullOrEmpty($env:TF_CFG_backend_storage_account))   { Throw "You must set environment variable TF_CFG_backend_storage_account" }
        $tfbackendArgs = "-backend-config=`"storage_account_name=${env:TF_CFG_backend_storage_account}`""
        $initCmd = "terraform init $tfbackendArgs"
        if ($upgrade) {
            $initCmd += " -upgrade"
        }
        Invoke "`n$initCmd" 
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
        Invoke "`nterraform validate" 
    }
    
    # Prepare common arguments
    if ($force) {
        $forceArgs = "-auto-approve"
    }

    if (!(Get-ChildItem Env:TF_VAR_* -Exclude TF_VAR_paas_app_database_import) -and (Test-Path $varsFile)) {
        # Load variables from file, if it exists and environment variables have not been set
        $varArgs = "-var-file='$varsFile'"
    }

    if ($clear) {
        # Clear Terraform workspace
        Write-Host "`nClearing workspace..." -ForegroundColor Green 
        & (Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "tf_clear_state.ps1") 
    }

    if ($plan -or $apply -or $destroy) {
        # For Terraform apply, plan & destroy stages we need access to resources, and for destroy as well sometimes
        Write-Host "`nStart VM's, some operations (e.g. adding VM extensions) may fail if they're not started" -ForegroundColor Green 
        & (Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "start_vms.ps1") 

        Write-Host "`nPunch hole in PaaS Firewalls, otherwise terraform plan stage may fail" -ForegroundColor Green 
        & (Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "punch_hole.ps1") 

        # HACK: Create file to be used in Terraform to capture VNet ResourceGuid (not supported directly)
        # "modules/paas-app/paas-spoke-vnet-resourceguid.tmp"
        $paasSpokeResourceGuidFile = $(Join-Path modules paas-app paas-spoke-vnet-resourceguid.tmp)
        Write-Debug "PaaS Spoke VNet ResourceGuid: $paasSpokeResourceGuidFile"
        if (!(Test-Path $paasSpokeResourceGuidFile)) {
            Set-Content -Path ($paasSpokeResourceGuidFile) -Value ($null)
        }
    }

    if ($plan -or $apply) {
        SetDatabaseImport
        Invoke "terraform plan $varArgs -parallelism=$parallelism -out='$planFile'" 
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

        Invoke "terraform apply $forceArgs -parallelism=$parallelism '$planFile'"
    }

    if ($output) {
        Write-Host "`nterraform output" -ForegroundColor Green 
        terraform output
    }

    if (($apply -or $output) -and $pipeline) {
        # Export Terraform output as Pipeline output variables for subsequent tasks
        SetPipelineVariablesFromTerraform
    }

    if ($destroy) {
        # Delete resources created with ARM templates, Terraform doesn't know about those
        DeleteArmResources

        # Now let Terraform do it's work
        Invoke "terraform destroy $forceArgs -parallelism=$parallelism"
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
