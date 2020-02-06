#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    Schedule VM Operating System Updates
 
.DESCRIPTION 
    Create an Azure Automation Update Management schedule
#> 
param (    
    [parameter(Mandatory=$false)][string]$StartTime=(Get-Date).AddMinutes(6).ToString("hh:mm"),
    [parameter(Mandatory=$false)][ValidateSet("Daily", "Once")][string[]]$Frequency=@("Once"),
    [parameter(Mandatory=$false)][string[]]$VMResourceId,
    [parameter(Mandatory=$false)][string]$AutomationAccountName,
    [parameter(Mandatory=$false)][string]$ResourceGroupName,
    [parameter(Mandatory=$false)][string[]]$UpdateClassification=@("Critical", "Security", "UpdateRollup"),
    [parameter(Mandatory=$false)][string]$Workspace,
    [parameter(Mandatory=$false)][string]$subscription=$env:ARM_SUBSCRIPTION_ID,
    [parameter(Mandatory=$false)][string]$tenantid=$env:ARM_TENANT_ID,
    [parameter(Mandatory=$false)][string]$clientid=$env:ARM_CLIENT_ID,
    [parameter(Mandatory=$false)][string]$clientsecret=$env:ARM_CLIENT_SECRET,
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "Terraform")
) 

if (!$VMResourceId) {
  # Retrieve Azure resources config using Terraform
  try {
      Push-Location $tfdirectory

      if ($Workspace) {
          $currentWorkspace = $(terraform workspace show)
          terraform workspace select $Workspace
      } else {
          $Workspace = $(terraform workspace show)
      }
      Write-Host "Using Terraform workspace '$Workspace'..."

      Invoke-Command -ScriptBlock {
          $Private:ErrorActionPreference = "Continue"
          $Script:AutomationAccountName  = $(terraform output "automation_account" 2>$null)
          if ([string]::IsNullOrEmpty($AutomationAccountName)) {
            throw "Terraform output automation_account is empty"
          }

          $Script:ResourceGroupName      = $(terraform output "automation_account_resource_group" 2>$null)
          if ([string]::IsNullOrEmpty($ResourceGroupName)) {
            throw "Terraform output automation_account_resource_group is empty"
          }
   
          $vmResourceIdString              = $(terraform output "virtual_machine_ids_string" 2>$null)
          if ([string]::IsNullOrEmpty($vmResourceIdString)) {
            throw "Terraform output virtual_machine_ids_string is empty"
          }
          $Script:VMResourceId            = $vmResourceIdString.Split(",")
      }
  } finally {
      if ($currentWorkspace) {
        terraform workspace select $currentWorkspace
      }
      Pop-Location
  }
}

# From https://docs.microsoft.com/en-us/powershell/module/az.automation/new-azautomationschedule
$duration = New-TimeSpan -Hours 2
$scheduleName = "$Frequency at $StartTime" -Replace ":",""
Write-Host $scheduleName
$schedule = New-AzAutomationSchedule -ResourceGroupName $ResourceGroupName `
                                                  -AutomationAccountName $AutomationAccountName `
                                                  -Name $scheduleName `
                                                  -StartTime $StartTime `
                                                  -TimeZone "Etc/UTC"`
                                                  -DaysOfWeek Sunday,Monday,Tuesday,Wednesday,Thursday,Friday,Saturday `
                                                  -WeekInterval 1 `
                                                  -ForUpdateConfiguration

New-AzAutomationSoftwareUpdateConfiguration -ResourceGroupName $ResourceGroupName `
                                                 -AutomationAccountName $AutomationAccountName `
                                                 -Schedule $schedule `
                                                 -Windows `
                                                 -AzureVMResourceId $VMResourceId `
                                                 -IncludedUpdateClassification $UpdateClassification `
                                                 -Duration $duration
