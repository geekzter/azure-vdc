#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    This creates allow rules for the current connection, start bastion, and displays credentials needed

#> 
### Arguments
param ( 
    [parameter(Mandatory=$false,HelpMessage="The Terraform workspace to use")][string]$Workspace=$env:TF_WORKSPACE,
    [parameter(Mandatory=$false)][switch]$All=$false,
    [parameter(Mandatory=$false)][switch]$Network=$false,
    [parameter(Mandatory=$false)][switch]$ShowCredentials=$false,
    [parameter(Mandatory=$false)][switch]$SqlServer=$false,
    [parameter(Mandatory=$false,HelpMessage="Grants App Service MSI access to database (reset should no longer be needed)")][switch]$GrantMSIAccess=$false,
    [parameter(Mandatory=$false)][switch]$StartBastion=$false,
    [parameter(Mandatory=$false)][switch]$ConnectBastion=$false,
    [parameter(Mandatory=$false)][switch]$Wait=$false,
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "Terraform"),
    [parameter(Mandatory=$false)][string]$subscription=$env:ARM_SUBSCRIPTION_ID,
    [parameter(Mandatory=$false)][string]$tenantid=$env:ARM_TENANT_ID
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
    $priorWorkspace = (SetWorkspace -Workspace $Workspace -ShowWorkspaceName).PriorWorkspaceName

    $vdcResourceGroup = $(terraform output "vdc_resource_group" 2>$null)
    $paasAppResourceGroup = $(terraform output "paas_app_resource_group" 2>$null)
    
    if ($All -or $StartBastion -or $ConnectBastion) {
        $Script:bastionName = $(terraform output "bastion_name" 2>$null)
        # Start bastion
        if ($bastionName) {
            Write-Host "`nStarting bastion" -ForegroundColor Green 
            $null = Start-Job -Name "Start Bastion" -ScriptBlock {az vm start --ids $(az vm list -g $args --query "[?powerState!='VM running'].id" -o tsv)} -ArgumentList $vdcResourceGroup
        }
    }

    if ($All -or $Network) {
        # Punch hole in PaaS Firewalls
        Write-Host "`nPunch hole in PaaS Firewalls" -ForegroundColor Green 
        # TODO
        #& (Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "punch_hole.ps1") 

        # Get public IP address
        Write-Host "`nPunch hole in Azure Firewall (for bastion)" -ForegroundColor Green 
        $ipAddress=$(Invoke-RestMethod https://ipinfo.io/ip) -replace "\n","" # Ipv4
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
        $bastionRuleName = "AllowInboundRDP from $ipPrefix"

        $ruleCollection = az network firewall nat-rule collection list -f $azFWName -g $vdcResourceGroup --query "[?name=='$azFWNATRulesName']" -o tsv
        if ($ruleCollection) {
            $bastionRule = az network firewall nat-rule list -c $azFWNATRulesName -f $azFWName -g $vdcResourceGroup --query "rules[?name=='$bastionRuleName']" 

            if ($bastionRule) {
                Write-Host "NAT Rule collection $azFWNATRulesName found, rule '$bastionRuleName' already exists"

            } else {
                Write-Host "NAT Rule collection $azFWNATRulesName found, adding bastion rule '$bastionRuleName'..."
                az network firewall nat-rule create -c $azFWNATRulesName -f $azFWName -g $vdcResourceGroup -n $bastionRuleName `
                                    --protocols TCP `
                                    --source-addresses $ipPrefix `
                                    --destination-addresses $azFWPublicIPAddress `
                                    --destination-ports $rdpPort `
                                    --translated-port 3389 `
                                    --translated-address $bastionAddress
            }
        } else {
            Write-Host "NAT Rule collection $azFWNATRulesName not found, creating with bastion rule '$bastionRuleName '..."
            az network firewall nat-rule create -c $azFWNATRulesName -f $azFWName -g $vdcResourceGroup -n $bastionRuleName `
                                --protocols TCP `
                                --source-addresses $ipPrefix `
                                --destination-addresses $azFWPublicIPAddress `
                                --destination-ports $rdpPort `
                                --translated-port 3389 `
                                --translated-address $bastionAddress `
                                --priority 109 `
                                --action Dnat
        }
    }

    if ($All -or $SqlServer -or $GrantMSIAccess) {
        $tries = 0
        $maxTries = 2
        do {
            $tries++
            $user = az account show --query "user" | ConvertFrom-Json
            if ($user.type -ieq "user") {
                $sqlAADUser = $user.name
            } else {
                Write-Host "Current user $($user.name) is a $($user.type), setting SQL Server Active Directory Administrator will likely fail (unless identity has sufficient Graph access)." 
                Write-Host "Prompting for Azure credentials to be able to switch AAD Admin..."
                AzLogin
            }
        } while ([string]::IsNullOrEmpty($sqlAADUser) -and ($tries -lt $maxTries))

        if ([string]::IsNullOrEmpty($sqlAADUser)) {
            Write-Host "No valid account found or provided to access AAD and Azure SQL Server, skipping configuration" -ForegroundColor Yellow
        } else {
            $msiClientId   = $(terraform output paas_app_service_msi_client_id 2>$null)
            $msiName       = $(terraform output paas_app_service_msi_name      2>$null)
            $sqlDB         = $(terraform output paas_app_sql_database          2>$null)
            $sqlServerName = $(terraform output paas_app_sql_server            2>$null)
            $sqlServerFQDN = $(terraform output paas_app_sql_server_fqdn       2>$null)

            Write-Information "Determening current Azure Active Directory DBA for SQL Server $sqlServerName..."
            az sql server ad-admin list -g $paasAppResourceGroup -s $sqlServerName
            
            $dba = az sql server ad-admin list -g $paasAppResourceGroup -s $sqlServerName --query "[?login=='${sqlAADUser}']" -o json | ConvertFrom-Json
            if ($dba) {
                Write-Host "$($dba.login) is already current Azure Active Directory DBA for SQL Server $sqlServerName"
            } else {
                $dba = az sql server ad-admin create -u "ericvan@microsoft.com" -i "115c3ab3-943b-4e0c-96ed-1a1763fbaa44" -g $paasAppResourceGroup -s $sqlServerName -o json | ConvertFrom-Json
                Write-Host "$($dba.login) is now Azure Active Directory DBA for SQL Server $sqlServerName"
            }

            if ($GrantMSIAccess) {
                if ($IsWindows) {
                    Write-Information "Adding Managed Identity $msiName to $sqlServerName/$sqlDB..."
                    $queryFile = (Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) grant-msi-database-access.sql)
                    $msiSID = ConvertTo-Sid $msiClientId
                    $query = (Get-Content $queryFile) -replace "@msi_name",$msiName -replace "@msi_sid",$msiSID -replace "\-\-.*$",""
                    sqlcmd -S $sqlServerFQDN -d $sqlDB -Q "$query" -G -U $sqlAADUser
                } else {
                    Write-Host "Unfortunately sqlcmd (currently) only supports AAD MFA login on Windows, skipping SQL Server access configuration" -ForegroundColor Yellow
                }
            }
        }
    }

    if ($All -or $ShowCredentials -or $ConnectBastion) {
        $Script:adminUser = $(terraform output admin_user 2>$null)
        $Script:adminPassword = $(terraform output admin_password 2>$null)
        $Script:bastionHost = "$(terraform output iag_public_ip):$(terraform output bastion_rdp_port)"
    }

    # TODO: Request JIT access to Bastion VM, once azurrm Terraform provuider supports it

    if ($All -or $ShowCredentials -or $ConnectBastion) {
        Write-Host "`nConnection information:" -ForegroundColor Green 
        # Display connectivity info
        Write-Host "Bastion VM RDP                 : $bastionHost"
        Write-Host "Admin user                     : $adminUser"
        Write-Host "Admin password                 : $adminPassword"
    }

    # Wait for bastion to start
    if ((($All -or $StartBastion) -and $wait) -or $ConnectBastion) {
        az vm start --ids $(az vm list -g $vdcResourceGroup --query "[?powerState!='VM running'].id" -o tsv)
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
    $null = SetWorkspace -Workspace $priorWorkspace
    Pop-Location
}