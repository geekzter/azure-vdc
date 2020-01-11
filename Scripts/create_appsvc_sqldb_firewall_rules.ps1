#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    Intended to be used from Terraform local-exec provisioner
 
.DESCRIPTION 
    This is intended to be run from Terraform, and works around the terraform limitation "value of 'count' cannot be computed"
#> 
### Arguments
param ( 
    [parameter(Mandatory=$true)][string]$SqlServerName,
    [parameter(Mandatory=$true)][string]$ResourceGroupName,
    [parameter(Mandatory=$true)][string[]]$OutboundIPAddresses
) 

$ruleNamePrefix = "AllowAppService"

# Remove existing rules
Write-Host "Removing existing Firewall rules for $SqlServerName matching '$ruleNamePrefix'..."
Get-AzSqlServerFirewallRule -ServerName $SqlServerName -ResourceGroupName $ResourceGroupName | Where-Object -Property FirewallRuleName -match $ruleNamePrefix | Remove-AzSqlServerFirewallRule -Force | Select-Object -ExpandProperty StartIpAddress

$index = 1
foreach ($ipAddress in $OutboundIPAddresses) {
    $ruleName = "${ruleNamePrefix}$index"
    Write-Host "Creating Firewall rule $ruleName for $SqlServerName to allow $ipAddress..."
    $rule = New-AzSqlServerFirewallRule -FirewallRuleName $ruleName -StartIpAddress $ipAddress -EndIpAddress $ipAddress -ServerName $SqlServerName -ResourceGroupName $ResourceGroupName
    $index++
}