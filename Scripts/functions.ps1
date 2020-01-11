function AzLogin () {
    if (!(Get-AzContext)) {
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

function GetCurrentBranch () {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Invoke-Command -ScriptBlock {
            $Private:ErrorActionPreference = "Continue"
            return git rev-parse --abbrev-ref HEAD 2>$null
        }
    }
}
function PrintCurrentBranch () {
    $branch = GetCurrentBranch
    if (![string]::IsNullOrEmpty($branch)) {
        Write-Host "Using branch '$branch'"
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

function LoadPrivateDnsModule () {
    if (!(Get-Command 'New-AzPrivateDnsRecordConfig' -ErrorAction SilentlyContinue)) {
        #Get-InstalledModule Az.PrivateDns -AllVersions -ErrorAction SilentlyContinue
        #Install-Module -Name Az.PrivateDns -Scope CurrentUser -Force -AllowClobber
        Import-Module Az.PrivateDns
        #Get-Module Az.PrivateDns
        #Get-Command 'New-AzPrivateDnsRecordConfig'
    }
}

function RemoveResourceGroups (
    [parameter(Mandatory=$false)][object[]]$resourceGroups,
    [parameter(Mandatory=$false)][bool]$Force=$false
) {
    if ($resourceGroups) {
        $resourceGroupNames = $resourceGroups | Select-Object -ExpandProperty ResourceGroupName
        if (!$Force) {
            Write-Host "If you wish to proceed removing these resource groups:`n$resourceGroupNames `nplease reply 'yes' - null or N aborts" -ForegroundColor Cyan
            $proceedanswer = Read-Host
            if ($proceedanswer -ne "yes") {
                Write-Host "`nSkipping $resourceGroupNames" -ForegroundColor Yellow
                return $false
            }
        }
        $resourceGroups | Remove-AzResourceGroup -AsJob -Force
        return $true
    } else {
        return $false
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

function SetSuffix () {
    # Don't change the suffix on paln/apply
    # BUG: This can cause problems when cycling apply/destroy repeatedly within the same shell lifetime
    #      TF_VAR_resource_suffix will be used for subsequent apply's, including different workspaces
    Invoke-Command -ScriptBlock {
        $Private:ErrorActionPreference = "Continue"
        $script:resourceSuffix = $(terraform output "resource_suffix" 2>$null)
    }

    if (![string]::IsNullOrEmpty($resourceSuffix)) {
        # Re-use previously defined suffix, to prevent resources from being recreated
        $env:TF_VAR_resource_suffix=$resourceSuffix
        Write-Host "Suffix already set. TF_VAR_resource_suffix=$env:TF_VAR_resource_suffix"
    }
}
function UnsetSuffix () {
    $env:TF_VAR_resource_suffix=$null    
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