#!/usr/bin/env pwsh

# Clean up Azure resources left over

### Arguments
param ( 
    [parameter(Mandatory=$false)][string]$subscription=$env:ARM_SUBSCRIPTION_ID,
    [parameter(Mandatory=$false)][string]$tenantid=$env:ARM_TENANT_ID,
    [parameter(Mandatory=$false)][string]$clientid=$env:ARM_CLIENT_ID,
    [parameter(Mandatory=$false)][string]$clientsecret=$env:ARM_CLIENT_SECRET,
    [parameter(Mandatory=$false)][string[]]$suffixes,
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "Terraform")
) 

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

function RemoveResourceGroups (
    [parameter(Mandatory=$false)][object[]]$resourceGroups
) {
    if ($resourceGroups) {
        $resourceGroupNames = $resourceGroups | Select-Object -ExpandProperty ResourceGroupName
        $proceedanswer = Read-Host "If you wish to proceed removing these resource groups:`n$resourceGroupNames `nplease reply 'yes' - null or N aborts"
        if ($proceedanswer -ne "yes") {
            Write-Host "`nSkipping $resourceGroupNames" -ForegroundColor Red
            continue
        }
        $resourceGroups | Remove-AzResourceGroup -AsJob -Force
        return $true
    } else {
        return $false
    }
}

AzLogin

if ($suffixes) {
    foreach ($suffix in $suffixes) {
        # Use suffix wildcard
        $prefix = "vdc"
        $matchWildcard = "$prefix-*-$suffix"

        Get-AzResourceGroup | Where-Object {$_.ResourceGroupName -like "$prefix-*-*"} | Select-Object -Property ResourceGroupName, Location | Format-Table

        Write-Host "Looking for resource groups that match $matchWildcard.."
        $resourceGroups = Get-AzResourceGroup | Where-Object {$_.ResourceGroupName -like $matchWildcard}

        if (!(RemoveResourceGroups $resourceGroups)) {
            Write-Host "Nothing found to delete for wildcard $matchWildcard"
        }
    }

    Get-Job | Where-Object {$_.Command -like "Remove-AzResourceGroup"} | Format-Table -Property Id, Name, State
} else {
    # Use Terraform by enumerating workspaces 
    try {
        Push-Location $tfdirectory
        $activeWorkspace = $(terraform workspace show)

        #terraform init -reconfigure # Initialize backend
        terraform workspace new temp 2>$null
        terraform workspace select temp
        $stderrfile = [system.io.path]::GetTempFileName()
        $suffixes = @()
        foreach($workspace in ($(terraform workspace list)).Trim())
        {
            if ($workspace.StartsWith("*") -or $workspace -notmatch "\w") {
                # Skip active workspace
                Write-Information "Skipping workspace with illegal name '$workspace'"
                continue
            }

            Write-Host "Switching to workspace '$workspace'"
            terraform workspace select $workspace
            $tfWorkspace = $(terraform workspace show)
            if ($workspace -ne $tfWorkspace) {
                # Panic
                Write-Host "`n'$workspace' does not match current Terreform workspace '$tfWorkspace', exiting" -ForegroundColor Red
                exit
            }

            Invoke-Command -ScriptBlock {
                $Private:ErrorActionPreference = "Continue"
                $Script:prefix           = $(terraform output "resource_prefix" 2>$null)
                $Script:environment      = $(terraform output "resource_environment" 2>$null)
                $Script:suffix           = $(terraform output "resource_suffix" 2>$null)
                if ($suffix) {
                    $suffixes += $suffix
                    Write-Host "Added $suffix to suffix list $suffixes"
                }

                $Script:outputAvailable  = (![string]::IsNullOrEmpty($prefix) -and ![string]::IsNullOrEmpty($environment) -and ![string]::IsNullOrEmpty($suffix))
            }

            $Script:isWorkspaceEmpty = [string]::IsNullOrEmpty($(terraform output "arm_resource_ids" 2>$stderrfile))
            # Detect locked workspace
            $stderr = $(Get-Content $stderrfile)
            if ($stderr -and ($stderr -match "The output variable requested could not be found")) {
                Write-Host "Could not read output from workspace '$workspace', the state may be locked. Skipping workspace '$workspace'"
                continue
            }
        
            $resourceGroups = $null
            if ($isWorkspaceEmpty) {
                # Remove everything according to known conventions
                $prefix = "vdc"
                $environment = $workspace
                $matchWildcard = "*$prefix-$environment-*"

                Write-Host "Workspace $workspace is empty, looking for resource groups that match $matchWildcard.."
                $resourceGroups = Get-AzResourceGroup | Where-Object {$_.ResourceGroupName -like $matchWildcard}
            } else {
                if ($outputAvailable) {
                    $matchWildcard = "*$prefix-$environment-*"
                    $notMatchWildcard = "*-$suffix"
        
                    Write-Host "Workspace $workspace is not empty, looking for resource groups that match $matchWildcard, but don't match $notMatchWildcard.."
                    $resourceGroups = Get-AzResourceGroup | Where-Object {$_.ResourceGroupName -like $matchWildcard} | Where-Object {$_.ResourceGroupName -notlike $notMatchWildcard}
                }
            }

            if (!(RemoveResourceGroups $resourceGroups)) {
                Write-Host "Nothing found to delete for workspace '$workspace'"
            }
        }

        $notMatchSuffixes = $suffixes -join '|'
        $resourceGroups = Get-AzResourceGroup | Where-Object {$_.ResourceGroupName -like "vdc-*"} | Where-Object {$_.ResourceGroupName -notmatch $notMatchSuffixes}
        if (!(RemoveResourceGroups $resourceGroups)) {
            Write-Host "No VDC resource groups found not matching suffixes $suffixes"
        }

        Get-Job | Where-Object {$_.Command -like "Remove-AzResourceGroup"} | Format-Table -Property Id, Name, State
    } finally {
        terraform workspace select $activeWorkspace
        Pop-Location
    }
}