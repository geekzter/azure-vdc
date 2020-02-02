#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    This creates allow rules for the current connection, start bastion, and displays credentials needed

#> 
### Arguments
param ( 
    [parameter(Mandatory=$false,HelpMessage="The Terraform workspace to use")][string] $Workspace,
    [parameter(Mandatory=$false)][switch]$All=$false,
    [parameter(Mandatory=$false)][switch]$Network=$false,
    [parameter(Mandatory=$false)][switch]$ShowCredentials=$false,
    [parameter(Mandatory=$false)][switch]$SqlServer=$false,
    [parameter(Mandatory=$false)][switch]$StartBastion=$false,
    [parameter(Mandatory=$false)][switch]$ConnectBastion=$false,
    [parameter(Mandatory=$false)][switch]$Wait=$false,
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "Terraform"),
    [parameter(Mandatory=$false)][string]$subscription=$env:ARM_SUBSCRIPTION_ID,
    [parameter(Mandatory=$false)][string]$tenantid=$env:ARM_TENANT_ID,
    [parameter(Mandatory=$false)][string]$clientid=$env:ARM_CLIENT_ID,
    [parameter(Mandatory=$false)][string]$clientsecret=$env:ARM_CLIENT_SECRET
) 

# Provide at least one argument
if (!($All -or $ConnectBastion -or $Network -or $ShowCredentials -or $SqlServer -or $StartBastion)) {
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

    $vdcResourceGroup = $(terraform output "vdc_resource_group" 2>$null)
    $paasAppResourceGroup = $(terraform output "paas_app_resource_group" 2>$null)
    
    if ($All -or $StartBastion -or $ConnectBastion) {
        $Script:bastionName = $(terraform output "bastion_name" 2>$null)
        # Start bastion
        if ($bastionName) {
            Write-Host "`nStarting bastion" -ForegroundColor Green 
            Get-AzVM -Name $bastionName -ResourceGroupName $vdcResourceGroup -Status | Where-Object {$_.PowerState -notmatch "running"} | Start-AzVM -AsJob
        }
    }

    if ($All -or $Network) {
        # Punch hole in PaaS Firewalls
        Write-Host "`nPunch hole in PaaS Firewalls" -ForegroundColor Green 
        & (Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "punch_hole.ps1") 

        # Get public IP address
        Write-Host "`nPunch hole in Azure Firewall (for bastion)" -ForegroundColor Green 
        $ipAddress=$(Invoke-RestMethod https://ipinfo.io/ip) # Ipv4
        Write-Host "Public IP address is $ipAddress"

        # Get block(s) the public IP address belongs to
        # HACK: We need this (prefix) to cater for changing public IP addresses e.g. Azure Pipelines Hosted Agents
        $ipPrefix = Invoke-RestMethod https://stat.ripe.net/data/network-info/data.json?resource=${ipAddress} | Select-Object -ExpandProperty data | Select-Object -ExpandProperty prefix
        Write-Host "Public IP prefix is $ipPrefix"

        # Add rule to Azure Firewall
        $azFWName = $(terraform output "iag_name" 2>$null)
        if ([string]::isNullOrEmpty($azFWName)) {
            Write-Host "`nAzure Firewall not found, nothing to get into" -ForegroundColor Yellow
            exit
        }
        $azFWPublicIPAddress = $(terraform output "iag_public_ip" 2>$null)
        $azFWNATRulesName = "$azFWName-letmein-rules"
        $bastionAddress = $(terraform output "bastion_address" 2>$null)
        $rdpPort = $(terraform output "bastion_rdp_port" 2>$null)

        $azFW = Get-AzFirewall -Name $azFWName -ResourceGroupName $vdcResourceGroup
        $bastionRule = New-AzFirewallNatRule -Name "AllowInboundRDP from $ipPrefix" -Protocol "TCP" -SourceAddress $ipPrefix -DestinationAddress $azFWPublicIPAddress -DestinationPort $rdpPort -TranslatedAddress $bastionAddress -TranslatedPort "3389"

        try {
            $ruleCollection = $azFW.GetNatRuleCollectionByName($azFWNATRulesName) 2>$null
        } catch {
            $ruleCollection = $null
        }
        if ($ruleCollection) {
            Write-Host "NAT Rule collection $azFWNATRulesName found, adding bastion rule..."
            $ruleCollection.RemoveRuleByName($bastionRule.Name)
            $ruleCollection.AddRule($bastionRule)
        } else {
            Write-Host "NAT Rule collection $azFWNATRulesName not found, creating with bastion rule..."
            $ruleCollection = New-AzFirewallNatRuleCollection -Name $azFWNATRulesName -Priority 109 -Rule $bastionRule
            $azFw.AddNatRuleCollection($ruleCollection)
        }

        Write-Host "Updating Azure Firewall $azFWName..."
        $null = Set-AzFirewall -AzureFirewall $azFW
    }

    if ($All -or $SqlServer) {
        if ($IsWindows) {
            $loggedInAccount = (Get-AzContext).Account
            if ($loggedInAccount.Type -eq "User") {
                $sqlAADUser = $loggedInAccount.Id
            } else {
                Write-Host "Current user $($loggedInAccount.Id) is a $($loggedInAccount.Type), Set-AzSqlServerActiveDirectoryAdministrator may fail..." -ForegroundColor Yellow
                do {
                    Write-Host "Type email address of user to sign into Azure SQL Server (empty to skip):" -ForegroundColor Cyan
                    $sqlAADUser = Read-Host
                } until (($sqlAADUser -match "^[a-zA-Z0-9.!£#$%&'^_`{}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)*$") -or [string]::IsNullOrEmpty($sqlAADUser))
            }
            if ([string]::IsNullOrEmpty($sqlAADUser)) {
                Write-Host "No valid account found or provided to access Azure SQL Server, skipping configuration" -ForegroundColor Yellow
            } else {
                $msiClientId   = $(terraform output paas_app_service_msi_client_id 2>$null)
                $msiName       = $(terraform output paas_app_service_msi_name      2>$null)
                $sqlDB         = $(terraform output paas_app_sql_database          2>$null)
                $sqlServerName = $(terraform output paas_app_sql_server            2>$null)
                $sqlServerFQDN = $(terraform output paas_app_sql_server_fqdn       2>$null)
    
                Write-Host "Determening current Azure Active Directory DBA for SQL Server $sqlServerName..."
                $dba = Get-AzSqlServerActiveDirectoryAdministrator -ServerName $sqlServerName -ResourceGroupName $paasAppResourceGroup
                if ($dba.DisplayName -ne $sqlAADUser) {
                    $previousDBA = $dba.DisplayName
                    Write-Host "Replacing $($dba.DisplayName) with $sqlAADUser as Azure Active Directory DBA for SQL Server $sqlServerName..."
                    # BUG: Forbidden when logged in with Service Principal
                    $dba = Set-AzSqlServerActiveDirectoryAdministrator -DisplayName $sqlAADUser -ServerName $sqlServerName -ResourceGroupName $paasAppResourceGroup
                }
                Write-Host "$($dba.DisplayName) is Azure Active Directory DBA for SQL Server $sqlServerName"
    
                Write-Host "Adding Managed Identity $msiName to $sqlServerName/$sqlDB..."
                $queryFile = (Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) grant-msi-database-access.sql)
                $msiSID = ConvertTo-Sid $msiClientId
                $query = (Get-Content $queryFile) -replace "@msi_name",$msiName -replace "@msi_sid",$msiSID -replace "\-\-.*$",""
                sqlcmd -S $sqlServerFQDN -d $sqlDB -Q "$query" -G -U $sqlAADUser
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "Sign-in dialog aborted/cancelled" -ForegroundColor Yellow
                    if ($previousDBA) {
                        # Revert DBA change back to where we started
                        Write-Host "Replacing $($dba.DisplayName) back to $previousDBA as Azure Active Directory DBA for SQL Server $sqlServerName..."              
                        $dba = Set-AzSqlServerActiveDirectoryAdministrator -DisplayName $previousDBA -ServerName $sqlServerName -ResourceGroupName $paasAppResourceGroup
                        Write-Host "$($dba.DisplayName) is Azure Active Directory DBA for SQL Server $sqlServerName"
                    }
                }
            }
        } else {
            Write-Host "Unfortunately sqlcmd (currently) only supports AAD MFA login on Windows, skipping SQL Server access configuration" -ForegroundColor Yellow
        }
    }


    if ($All -or $ShowCredentials -or $ConnectBastion) {
        $Script:adminUser = $(terraform output admin_user 2>$null)
        $Script:adminPassword = $(terraform output admin_password 2>$null)
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