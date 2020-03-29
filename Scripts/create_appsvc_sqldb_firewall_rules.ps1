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
az sql server firewall-rule list -g $ResourceGroupName -s $SqlServerName --query "[?starts_with(name,'$ruleNamePrefix')].id" -o tsv | Tee-Object -Variable sqlFWRuleIDs
if ($sqlFWRuleIDs) {
    az sql server firewall-rule delete --ids $sqlFWRuleIDs -o none
}

$index = 1
foreach ($ipAddress in $OutboundIPAddresses) {
    $sqlFWRuleName = "${ruleNamePrefix}$index"
    Write-Host "Creating Firewall rule $sqlFWRuleName for $SqlServerName to allow... " -NoNewLine
    az sql server firewall-rule create -g $ResourceGroupName -s $SqlServerName -n $sqlFWRuleName --start-ip-address $ipAddress --end-ip-address $ipAddress --query "startIpAddress" -o tsv
    $index++
}