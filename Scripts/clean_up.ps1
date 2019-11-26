#!/usr/bin/env pwsh

# Clean up Azure resources left over

### Arguments
param ( 
    [parameter(Mandatory=$false)][string]$subscription=$env:ARM_SUBSCRIPTION_ID,
    [parameter(Mandatory=$false)][string]$tenantid=$env:ARM_TENANT_ID,
    [parameter(Mandatory=$false)][string]$clientid=$env:ARM_CLIENT_ID,
    [parameter(Mandatory=$false)][string]$clientsecret=$env:ARM_CLIENT_SECRET,
    [parameter(Mandatory=$false)][string[]]$Suffixes,
    [parameter(Mandatory=$false)][string]$Environment="*",
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "Terraform")
) 
. (Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) functions.ps1)


AzLogin

if ($Environment -and ($Environment -notlike "\*") -and !($Suffixes)) {
    # Workspace constraint, no Suffix constraint, set Suffix to wildcard
    $Suffixes = "*"
}

if ($Suffixes) {
    foreach ($suffix in $Suffixes) {
        # Use suffix wildcard
        $prefix = "vdc"
        $matchWildcard = "$prefix-$Environment-$suffix"

        Get-AzResourceGroup | Where-Object {$_.ResourceGroupName -like "$prefix-$Environment-*"} | Select-Object -Property ResourceGroupName, Location | Format-Table

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
        $Suffixes = @()
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
                    $Suffixes += $suffix
                    Write-Host "Added $suffix to suffix list $Suffixes"
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

        $notMatchSuffixes = $Suffixes -join '|'
        $resourceGroups = Get-AzResourceGroup | Where-Object {$_.ResourceGroupName -like "vdc-*"} | Where-Object {$_.ResourceGroupName -notmatch $notMatchSuffixes}
        if (!(RemoveResourceGroups $resourceGroups)) {
            Write-Host "No VDC resource groups found not matching Suffixes $Suffixes"
        }

        Get-Job | Where-Object {$_.Command -like "Remove-AzResourceGroup"} | Format-Table -Property Id, Name, State
    } finally {
        terraform workspace select $activeWorkspace
        Pop-Location
    }
}