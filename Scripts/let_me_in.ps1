#!/usr/bin/env pwsh


### Arguments
param ( 
    [parameter(Mandatory=$false,HelpMessage="The Terraform workspace to use")][string] $Workspace,
    [parameter(Mandatory=$false)][switch]$All=$false,
    [parameter(Mandatory=$false)][switch]$ForceEntry=$false,
    [parameter(Mandatory=$false)][switch]$ShowCredentials=$false,
    [parameter(Mandatory=$false)][switch]$StartBastion=$false,
    [parameter(Mandatory=$false)][switch]$ConnectBastion=$false,
    [parameter(Mandatory=$false)][switch]$wait=$false,
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "Terraform"),
    [parameter(Mandatory=$false)][string]$subscription=$env:ARM_SUBSCRIPTION_ID,
    [parameter(Mandatory=$false)][string]$tenantid=$env:ARM_TENANT_ID,
    [parameter(Mandatory=$false)][string]$clientid=$env:ARM_CLIENT_ID,
    [parameter(Mandatory=$false)][string]$clientsecret=$env:ARM_CLIENT_SECRET
) 

# Provide at least one argument
if (!($All -or $ConnectBastion -or $ForceEntry -or $ShowCredentials -or $StartBastion)) {
    Write-Host "Please indicate what to do"
    Get-Help $MyInvocation.MyCommand.Definition
    exit
}

. (Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) functions.ps1)
AzLogin

try {
    # Terraform config
    Push-Location $tfdirectory
    if ($Workspace) {
        terraform workspace select $Workspace.ToLower()
        Write-Host "Terraform workspaces:" -ForegroundColor White
        terraform workspace list
    }
    Write-Host "Using Terraform workspace '$(terraform workspace show)'" 

    $bastionName = $(terraform output "bastion_name" 2>$null)
    $vdcResourceGroup = $(terraform output "vdc_resource_group" 2>$null)
    
    if ($All -or $StartBastion -or $ConnectBastion) {
        # Start bastion
        if ($bastionName) {
            Write-Host "`nStarting bastion" -ForegroundColor Green 
            Get-AzVM -Name $bastionName -ResourceGroupName $vdcResourceGroup -Status | Where-Object {$_.PowerState -notmatch "running"} | Start-AzVM -AsJob
        }
    }

    if ($All -or $ForceEntry) {

        # Punch hole in PaaS Firewalls
        Write-Host "`nPunch hole in PaaS Firewalls" -ForegroundColor Green 
        & (Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "punch_hole.ps1") 

        # Get public IP address
        Write-Host "`nPunch hole in Azure Firewall (for bastion)" -ForegroundColor Green 
        $ipAddress=$(Invoke-RestMethod https://ipinfo.io/ip) # Ipv4
        Write-Host "Public IP address is $ipAddress"

        # Get block(s) the public IP address belongs to
        # HACK: We need this to cater for changing public IP addresses e.g. Azure Pipelines Hosted Agents
        $ipPrefix = Invoke-RestMethod https://stat.ripe.net/data/network-info/data.json?resource=${ipAddress} | Select-Object -ExpandProperty data | Select-Object -ExpandProperty prefix
        Write-Host "Public IP prefix is $ipPrefix"

        # Add rule to Azure Firewall
        $azFWName = $(terraform output "iag_name" 2>$null)
        if ([string]::isNullOrEmpty($azFWName)) {
            Write-Host "`nAzure Firewall not found, nothing to get into" -ForegroundColor Yellow
            exit
        }
        $azFWPublicIPAddress = $(terraform output "iag_public_ip" 2>$null)
        #$azFWNATRulesName = $(terraform output "iag_nat_rules" 2>$null)
        $azFWNATRulesName = "$azFWName-letmein-rules"
        $bastionRuleName = "AllowInboundRDP"
        $bastionAddress = $(terraform output "bastion_address" 2>$null)
        $rdpPort = $(terraform output "bastion_rdp_port" 2>$null)

        $azFW = Get-AzFirewall -Name $azFWName -ResourceGroupName $vdcResourceGroup
        #$bastionRule = New-AzFirewallNatRule -Name $bastionRuleName -Protocol "TCP" -SourceAddress $ipAddress -DestinationAddress $azFWPublicIPAddress -DestinationPort $rdpPort -TranslatedAddress $bastionAddress -TranslatedPort "3389"
        $bastionRule = New-AzFirewallNatRule -Name $bastionRuleName -Protocol "TCP" -SourceAddress $ipPrefix -DestinationAddress $azFWPublicIPAddress -DestinationPort $rdpPort -TranslatedAddress $bastionAddress -TranslatedPort "3389"

        try {
            $ruleCollection = $azFW.GetNatRuleCollectionByName($azFWNATRulesName) 2>$null
        } catch {
            $ruleCollection = $null
        }
        if ($ruleCollection) {
            Write-Host "NAT Rule collection $azFWNATRulesName found, adding bastion rule..."
            $ruleCollection.RemoveRuleByName($bastionRuleName)
            $ruleCollection.AddRule($bastionRule)
        } else {
            Write-Host "NAT Rule collection $azFWNATRulesName not found, creating with bastion rule..."
            $ruleCollection = New-AzFirewallNatRuleCollection -Name $azFWNATRulesName -Priority 109 -Rule $bastionRule
            $azFw.AddNatRuleCollection($ruleCollection)
        }

        Write-Host "Updating Azure Firewall $azFWName..."
        $null = Set-AzFirewall -AzureFirewall $azFW
    }

    if ($All -or $ShowCredentials -or $ConnectBastion) {
        $Script:adminUser = $(terraform output admin_user)
        $Script:adminPassword = $(terraform output admin_password)
        $Script:bastionHost = "$(terraform output iag_public_ip):$(terraform output bastion_rdp_port)"
    }

    # TODO: Request JIT access to Bastion VM, once azurrm Terraform provuider supports it

    if ($All -or $ShowCredentials) {
        Write-Host "`nConnection information:" -ForegroundColor Green 
        # Display connectivity info
        Write-Host "Bastion VM RDP                 : $bastionHost"
        Write-Host "Admin user                     : $adminUser"
        Write-Host "Admin password                 : $adminPassword"
    }

    # Wait for bastion to start
    if ((($All -or $StartBastion) -and $wait) -or $ConnectBastion) {
        Get-AzVM -Name $bastionName -ResourceGroupName $vdcResourceGroup -Status | Where-Object {$_.PowerState -notmatch "running"} | Start-AzVM   
    }
    
    # Set up RDP session to Bastion
    if ($All -or $ConnectBastion) {
        if ($IsWindows) {
            cmdkey.exe /generic:${bastionHost} /user:${adminUser} /pass:${adminPassword}
            mstsc.exe /v:${bastionHost} /f
        }
        if ($IsMacOS) {
            open rdp://${adminUser}:${adminPassword}@${bastionHost}
        }
    }
} finally {
    Pop-Location
}