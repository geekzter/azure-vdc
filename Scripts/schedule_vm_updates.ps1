#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    Schedule VM Operating System Updates
 
.DESCRIPTION 
    Create an Azure Automation Update Management schedule
#> 
param (    
    [parameter(Mandatory=$false)][string]$StartTime="21:00",
    [parameter(Mandatory=$false)][string[]]$VMResourceId,
    [parameter(Mandatory=$false)][string]$AutomationAccountName,
    [parameter(Mandatory=$false)][string]$ResourceGroupName,
    [parameter(Mandatory=$false)][string[]]$UpdateClassification=@("Critical", "Security", "UpdateRollup")
) 

# From https://docs.microsoft.com/en-us/powershell/module/az.automation/new-azautomationschedule
$duration = New-TimeSpan -Hours 2
$schedule = New-AzAutomationSchedule -ResourceGroupName $ResourceGroupName `
                                                  -AutomationAccountName $AutomationAccountName `
                                                  -Name Daily `
                                                  -StartTime $StartTime `
                                                  -TimeZone "Etc/UTC"`
                                                  -DaysOfWeek 	Sunday,Monday,Tuesday,Wednesday,Thursday,Friday,Saturday `
                                                  -WeekInterval 1 `
                                                  -ForUpdateConfiguration

New-AzAutomationSoftwareUpdateConfiguration -ResourceGroupName $ResourceGroupName `
                                                 -AutomationAccountName $AutomationAccountName `
                                                 -Schedule $schedule `
                                                 -Windows `
                                                 -AzureVMResourceId $VMResourceId `
                                                 -IncludedUpdateClassification $UpdateClassification `
                                                 -Duration $duration

