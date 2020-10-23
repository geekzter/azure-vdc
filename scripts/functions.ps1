function AzLogin (
    [parameter(Mandatory=$false)][switch]$DisplayMessages=$false
) {
    # Azure CLI
    Invoke-Command -ScriptBlock {
        $Private:ErrorActionPreference = "Continue"
        # Test whether we are logged in
        $Script:loginError = $(az account show -o none 2>&1)
        if (!$loginError) {
            $Script:userType = $(az account show --query "user.type" -o tsv)
            if ($userType -ieq "user") {
                # Test whether credentials have expired
                $Script:userError = $(az ad signed-in-user show -o none 2>&1)
            } 
        }
    }
    $login = ($loginError -or $userError)
    # Set Azure CLI context
    if ($login) {
        if ($env:ARM_TENANT_ID) {
            az login -t $env:ARM_TENANT_ID -o none
        } else {
            az login -o none
        }
    }

    if ($DisplayMessages) {
        if ($env:ARM_SUBSCRIPTION_ID -or ($(az account list --query "length([])" -o tsv) -eq 1)) {
            Write-Host "Using subscription '$(az account show --query "name" -o tsv)'"
        } else {
            if ($env:TF_IN_AUTOMATION -ine "true") {
                # Active subscription may not be the desired one, prompt the user to select one
                $subscriptions = (az account list --query "sort_by([].{id:id, name:name},&name)" -o json | ConvertFrom-Json) 
                $index = 0
                $subscriptions | Format-Table -Property @{name="index";expression={$script:index;$script:index+=1}}, id, name
                Write-Host "Set `$env:ARM_SUBSCRIPTION_ID to the id of the subscription you want to use to prevent this prompt" -NoNewline

                do {
                    Write-Host "`nEnter the index # of the subscription you want Terraform to use: " -ForegroundColor Cyan -NoNewline
                    $occurrence = Read-Host
                } while (($occurrence -notmatch "^\d+$") -or ($occurrence -lt 1) -or ($occurrence -gt $subscriptions.Length))
                $env:ARM_SUBSCRIPTION_ID = $subscriptions[$occurrence-1].id
            
                Write-Host "Using subscription '$($subscriptions[$occurrence-1].name)'" -ForegroundColor Yellow
                Start-Sleep -Seconds 1
            } else {
                Write-Host "Using subscription '$(az account show --query "name" -o tsv)', set `$env:ARM_SUBSCRIPTION_ID if you want to use another one"
            }
        }
    }

    if ($env:ARM_SUBSCRIPTION_ID) {
        az account set -s $env:ARM_SUBSCRIPTION_ID -o none
    }

    # Populate Terraform azurerm variables where possible
    if ($userType -ine "user") {
        # Pass on pipeline service principal credentials to Terraform
        $env:ARM_CLIENT_ID       ??= $env:servicePrincipalId
        $env:ARM_CLIENT_SECRET   ??= $env:servicePrincipalKey
        $env:ARM_TENANT_ID       ??= $env:tenantId
        # Get from Azure CLI context
        $env:ARM_TENANT_ID       ??= $(az account show --query tenantId -o tsv)
        $env:ARM_SUBSCRIPTION_ID ??= $(az account show --query id -o tsv)
    }
    # Variables for Terraform azurerm Storage backend
    if (!$env:ARM_ACCESS_KEY -and !$env:ARM_SAS_TOKEN) {
        if ($env:TF_VAR_backend_storage_account -and $env:TF_VAR_backend_storage_container) {
            $env:ARM_SAS_TOKEN=$(az storage container generate-sas -n $env:TF_VAR_backend_storage_container --as-user --auth-mode login --account-name $env:TF_VAR_backend_storage_account --permissions acdlrw --expiry (Get-Date).AddDays(7).ToString("yyyy-MM-dd") -o tsv)
        }
    }
}

# From: https://blog.bredvid.no/handling-azure-managed-identity-access-to-azure-sql-in-an-azure-devops-pipeline-1e74e1beb10b
function ConvertTo-Sid {
    param (
        [string]$appId
    )
    [guid]$guid = [System.Guid]::Parse($appId)
    foreach ($byte in $guid.ToByteArray()) {
        $byteGuid += [System.String]::Format("{0:X2}", $byte)
    }
    return "0x" + $byteGuid
}

function Execute-Sql (
    [parameter(Mandatory=$true)][string]$QueryFile,
    [parameter(Mandatory=$false)][hashtable]$Parameters,
    [parameter(Mandatory=$false)][string]$SqlDatabaseName,
    [parameter(Mandatory=$false)][string]$SqlServer=$SqlServerFQDN.Split(".")[0],
    [parameter(Mandatory=$true)][string]$SqlServerFQDN,
    [parameter(Mandatory=$false)][string]$UserName,
    [parameter(Mandatory=$false)][SecureString]$SecurePassword
) {
    if ([string]::IsNullOrEmpty($SqlServerFQDN)) {
        Write-Error "No SQL Server specified" -ForeGroundColor Red
        return 
    }
    $result = $null

    # Prepare SQL Connection
    $conn = New-Object System.Data.SqlClient.SqlConnection
    if ($SqlDatabaseName -and ($SqlDatabaseName -ine "master")) {
        $conn.ConnectionString = "Data Source=tcp:$($SqlServerFQDN),1433;Initial Catalog=$($SqlDatabaseName);Encrypt=True;Connection Timeout=30;" 
    } else {
        $SqlDatabaseName = "Master"
        $conn.ConnectionString = "Data Source=tcp:$($SqlServerFQDN),1433;Encrypt=True;Connection Timeout=30;" 
    }

    if ($UserName -and $SecurePassword) {
        Write-Verbose "Using credentials for user '${UserName}'"
        # Use https://docs.microsoft.com/en-us/dotnet/api/system.data.sqlclient.sqlcredential if credential is passed, below (AAD) if not
        $credentials = New-Object System.Data.SqlClient.SqlCredential($UserName,$SecurePassword)
        $conn.Credential = $credentials
    } else {
        # Use AAD auth
        $conn.AccessToken = GetAccessToken
    }

    try {
        # Prepare SQL Command
        $query = Get-Content $QueryFile
        if ($Parameters){
            foreach ($parameterName in $Parameters.Keys) {
                $query = $query -replace "@$parameterName",$Parameters[$parameterName]
                # TODO: Use parameterized query to protect against SQL injection
                #$sqlParameter = $command.Parameters.AddWithValue($parameterName,$Parameters[$parameterName])
                #Write-Debug $sqlParameter
            }
        }
        $query = $query -replace "$","`n" # Preserve line feeds
        $command = New-Object -TypeName System.Data.SqlClient.SqlCommand($query, $conn)
 
        # Execute SQL Command
        Write-Host "Connecting to database ${SqlServerFQDN}/${SqlDatabaseName}..."
        Write-Debug "Executing query:`n$query"
        $conn.Open()
        $result = $command.ExecuteScalar()
    } finally {
        $conn.Close()
    }
    return $result
}

function GetAccessToken (
    [parameter(Mandatory=$false)][string]$Resource="https://database.windows.net/"
) {
    # Don't rely on ARM_*
    if ($env:ARM_TENANT_ID) {
        $tenantId = $env:ARM_TENANT_ID
    } else {
        $tenantId = $(az account show --query "tenantId" -o tsv)
    }

    $resourceAppIdURI = 'https://database.windows.net/'
    $token = $(az account get-access-token --tenant $tenantId --resource $Resource --query "accessToken" -o tsv)
    if (!$token) {
        Write-Error "Could not obtain token for resource '$Resource' and tenant '$tenantId'"
        return
    }

    return $token
}

function GetCurrentBranch () {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Invoke-Command -ScriptBlock {
            $Private:ErrorActionPreference = "Continue"
            return git rev-parse --abbrev-ref HEAD 2>$null
        }
    }
}

function GetEmailAddress () {
    $emailRegex = "[A-Z0-9_\-.]+@[A-Z0-9.-]+$"
    
    $emailAddress = $(az account show --query "user.name" -o tsv)
    if ($emailAddress -match $emailRegex) {
        return $emailAddress
    }
    
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Invoke-Command -ScriptBlock {
            $Private:ErrorActionPreference = "Continue"
            $emailAddress = $(git config user.email 2>$null)
            if ($emailAddress -match $emailRegex) {
                return $emailAddress
            }
        }
    }
    return $null
}

function GetTerraformOutput (
    [parameter(Mandatory=$true)][string]$OutputVariable
) {
    Invoke-Command -ScriptBlock {
        $Private:ErrorActionPreference    = "SilentlyContinue"
        Write-Verbose "terraform output ${OutputVariable}: evaluating..."
        $result = $(terraform output $OutputVariable 2>$null)
        if ($result -match "\[\d+m") {
            # Terraform warning, return null for missing output
            Write-Verbose "terraform output ${OutputVariable}: `$null (${result})"
            return $null
        } else {
            Write-Verbose "terraform output ${OutputVariable}: ${result}"
            return $result
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
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        Write-Warning "'$cmd' exited with status $exitCode"
        exit $exitCode
    }
}

# This creates a worksoace if it doesn't exist yet (even needed with TF_WORKSPACE)
function SetWorkspace (
    [parameter(Mandatory=$false,HelpMessage="The Terraform workspace to use")][string]$Workspace,
    [parameter(Mandatory=$false)][switch]$ShowWorkspaceName
) {
    Write-Information "Terraform workspaces:"
    terraform workspace list | Write-Information

    $priorWorkspace = $(terraform workspace show)

    if ($Workspace -and ($Workspace -ine $priorWorkspace)) {
        # Create workspace if it does not exist (even needed with TF_WORKSPACE)
        Invoke-Command -ScriptBlock {
            $Private:ErrorActionPreference = "Continue"
            terraform workspace new $Workspace 2>$null
        }
        if ($env:TF_WORKSPACE) {
            if ($Workspace -ine $env:TF_WORKSPACE) {
                Write-Error "Can't use workspace '$Workspace' if it is different from TF_WORKSPACE ($env:TF_WORKSPACE)"
            }
        } else {
            terraform workspace select $Workspace
        }
    }
    if ($ShowWorkspaceName) {
        Write-Host "Using Terraform workspace '$(terraform workspace show)'" 
    }

    $returnObject = New-Object PSObject -Property @{
        WorkspaceName      = $(terraform workspace show)
        PriorWorkspaceName = $priorWorkspace
    }

    return $returnObject
}

function SetSuffix () {
    # Don't change the suffix on plan/apply
    # NOTE: This can cause problems when cycling apply/destroy repeatedly within the same shell lifetime
    #       Environment variable TF_VAR_resource_suffix will be used for subsequent apply's, including different workspaces
    Invoke-Command -ScriptBlock {
        $Private:ErrorActionPreference = "Continue"
        $script:resourceSuffix = (GetTerraformOutput "resource_suffix")
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

function WaitForJobs (
    [parameter(Mandatory=$true)][object[]]$Jobs,
    [parameter(Mandatory=$false)][int]$TimeoutMinutes=5
) {
    if ($Jobs) {
        $updateIntervalSeconds = 10 # Same as Terraform
        $stopWatch = New-Object -TypeName System.Diagnostics.Stopwatch     
        $stopWatch.Start()
    
        Write-Host "Waiting for jobs to complete..."
    
        do {
            $runningJobs = $Jobs | Where-Object {$_.State -like "Running"}
            $elapsed = $stopWatch.Elapsed.ToString("m'm's's'")
            Write-Host "$($runningJobs.Count) jobs in running state [$elapsed elapsed]"
            $null = Wait-Job -Job $Jobs -Timeout $updateIntervalSeconds
        } while ($runningJobs -and ($stopWatch.Elapsed.TotalMinutes -lt $TimeoutMinutes)) 
    
        $jobs | Format-Table -Property Id, Name, State
        if ($waitStatus) {
            Write-Warning "Jobs did not complete before timeout (${TimeoutMinutes}m) expired"
        } else {
            # Timeout expired before jobs completed
            $elapsed = $stopWatch.Elapsed.ToString("m'm's's'")
            Write-Host "Jobs completed in $elapsed"
        }
    }
}