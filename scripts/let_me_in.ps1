#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    This creates allow rules for the current connection, start management VM, and displays credentials needed

#> 
### Arguments
param ( 
    [parameter(Mandatory=$false,HelpMessage="The Terraform workspace to use")][string]$Workspace=$env:TF_WORKSPACE,
    [parameter(Mandatory=$false)][switch]$All=$false,
    [parameter(Mandatory=$false)][switch]$Network=$false,
    [parameter(Mandatory=$false)][switch]$ShowCredentials=$false,
    [parameter(Mandatory=$false)][switch]$SqlServer=$false,
    [parameter(Mandatory=$false,HelpMessage="Grants App Service MSI access to database (reset should no longer be needed)")][switch]$GrantMSIAccess=$false,
    [parameter(Mandatory=$false)][switch]$StartMgmtVM=$false,
    [parameter(Mandatory=$false)][switch]$ConnectMgmtVM=$false,
    [parameter(Mandatory=$false)][switch]$VpnClient=$false,
    [parameter(Mandatory=$false)][switch]$Wait=$false,
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "terraform")
) 

# Provide at least one argument
if (!($All -or $ConnectMgmtVM -or $Network -or $ShowCredentials -or $SqlServer -or $StartMgmtVM -or $VpnClient)) {
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
    
    if ($All -or $StartMgmtVM -or $ConnectMgmtVM) {
        $Script:mgmtVMName = $(terraform output "mgmt_name" 2>$null)
        # Start management VM
        if ($mgmtVMName) {
            Write-Host "`nStarting Management VM" -ForegroundColor Green 
            $null = Start-Job -Name "Start Management VM" -ScriptBlock {az vm start --ids $(az vm list -g $args --query "[?powerState!='VM running'].id" -o tsv)} -ArgumentList $vdcResourceGroup
        }
    }

    if ($All -or $Network) {
        # Punch hole in PaaS Firewalls
        Write-Host "`nPunch hole in PaaS Firewalls" -ForegroundColor Green 
        & (Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "punch_hole.ps1") 

        # Get public IP address
        Write-Host "`nPunch hole in Azure Firewall (for management VM)" -ForegroundColor Green 
        $ipAddress=$(Invoke-RestMethod -Uri https://ipinfo.io/ip -MaximumRetryCount 9) -replace "\n","" # Ipv4
        Write-Host "Public IP address is $ipAddress"

        # Get block(s) the public IP address belongs to
        # HACK: We need this (prefix) to cater for changing public IP addresses e.g. Azure Pipelines Hosted Agents
        $ipPrefix = Invoke-RestMethod -Uri https://stat.ripe.net/data/network-info/data.json?resource=${ipAddress} -MaximumRetryCount 9 | Select-Object -ExpandProperty data | Select-Object -ExpandProperty prefix
        Write-Host "Public IP prefix is $ipPrefix"

        # Add rule to Azure Firewall
        $azFWName = $(terraform output "iag_name" 2>$null)
        if ([string]::isNullOrEmpty($azFWName)) {
            Write-Host "`nAzure Firewall not found, nothing to get into" -ForegroundColor Yellow
            exit
        }
        $azFWPublicIPAddress = $(terraform output "iag_public_ip" 2>$null)
        $azFWNATRulesName = "$azFWName-letmein-rules"
        $mgmtVMAddress = $(terraform output "mgmt_address" 2>$null)
        $rdpPort = $(terraform output "mgmt_rdp_port" 2>$null)
        $mgmtVMRuleName = "AllowInboundRDP from $ipPrefix"

        az extension add --name azure-firewall 2>$null
        $ruleCollection = az network firewall nat-rule collection list -f $azFWName -g $vdcResourceGroup --query "[?name=='$azFWNATRulesName']" -o tsv
        if ($ruleCollection) {
            $mgmtVMRule = az network firewall nat-rule list -c $azFWNATRulesName -f $azFWName -g $vdcResourceGroup --query "rules[?name=='$mgmtVMRuleName']" 

            if ($mgmtVMRule) {
                Write-Host "NAT Rule collection $azFWNATRulesName found, rule '$mgmtVMRuleName' already exists"
            } else {
                Write-Host "NAT Rule collection $azFWNATRulesName found, adding management VM rule '$mgmtVMRuleName'..."
                az network firewall nat-rule create -c $azFWNATRulesName -f $azFWName -g $vdcResourceGroup -n $mgmtVMRuleName `
                                    --protocols TCP `
                                    --source-addresses $ipPrefix `
                                    --destination-addresses $azFWPublicIPAddress `
                                    --destination-ports $rdpPort `
                                    --translated-port 3389 `
                                    --translated-address $mgmtVMAddress
            }
        } else {
            Write-Host "NAT Rule collection $azFWNATRulesName not found, creating with management VM rule '$mgmtVMRuleName '..."
            az network firewall nat-rule create -c $azFWNATRulesName -f $azFWName -g $vdcResourceGroup -n $mgmtVMRuleName `
                                --protocols TCP `
                                --source-addresses $ipPrefix `
                                --destination-addresses $azFWPublicIPAddress `
                                --destination-ports $rdpPort `
                                --translated-port 3389 `
                                --translated-address $mgmtVMAddress `
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

    if ($All -or $VpnClient) {
        $gatewayId = $(terraform output vpn_gateway_id 2>$null)
        if ($gatewayId) {
            $vpnPackageUrl = $(az network vnet-gateway vpn-client generate --ids $gatewayId --authentication-method EAPTLS -o tsv)

            # Download VPN Profile
            $packageFile = New-TemporaryFile
            Invoke-WebRequest -UseBasicParsing -Uri $vpnPackageUrl -OutFile $packageFile
            $tempPackagePath = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
            $null = New-Item -ItemType "directory" -Path $tempPackagePath
            Expand-Archive -Path $packageFile -DestinationPath $tempPackagePath
            $vpnProfileTempFile = Join-Path $tempPackagePath AzureVPN azurevpnconfig.xml
            Write-Verbose "VPN Temp Profile ${vpnProfileTempFile}"

            # Edit VPN Profile
            $vpnProfileXml = [xml](Get-Content $vpnProfileTempFile)
            $clientconfig = $vpnProfileXml.SelectSingleNode("//*[name()='clientconfig']")
            $dnsservers = $vpnProfileXml.CreateElement("dnsservers", $vpnProfileXml.AzVpnProfile.xmlns)
            $dnsserver = $vpnProfileXml.CreateElement("dnsserver", $vpnProfileXml.AzVpnProfile.xmlns)
            $dnsserver.InnerText = $(terraform output "vdc_dns_server" 2>$null)
            $dnsservers.AppendChild($dnsserver) | Out-Null
            $clientconfig.AppendChild($dnsservers) | Out-Null
            $clientconfig.RemoveAttribute("nil","http://www.w3.org/2001/XMLSchema-instance")

            if ((Get-Command azurevpn -ErrorAction SilentlyContinue) -and $IsWindows) {
                $vpnProfileFile = (Join-Path $env:userprofile\AppData\Local\Packages\Microsoft.AzureVpn_8wekyb3d8bbwe\LocalState ("$vdcResourceGroup{0}" -f ".xml"))
                $vpnProfileXml.Save($vpnProfileFile)
                Write-Host "Azure VPN app importing profile '$vpnProfileFile'..."
                azurevpn -i (Split-Path $vpnProfileFile -Leaf) -f
            } else {
                $vpnProfileXml.Save($vpnProfileTempFile)
                Write-Host "Use the Azure VPN app (https://go.microsoft.com/fwlink/?linkid=2117554) to import this profile:`n${vpnProfileTempFile}"
            }
        } else {
            Write-Host "Virtual network gateway, required for VPN, does not exist" -ForegroundColor Yellow
        }
    }

    # TODO: Request JIT access to Management VM, once azurerm Terraform provider supports it
    if ($All -or $ShowCredentials -or $ConnectMgmtVM) {
        $Script:adminUser = $(terraform output admin_user 2>$null)
        $Script:adminPassword = $(terraform output admin_password 2>$null)
        $Script:mgmtVM = "$(terraform output iag_public_ip):$(terraform output mgmt_rdp_port)"

        Write-Host "`nConnection information:" -ForegroundColor Green 
        # Display connectivity info
        Write-Host "Management VM RDP              : $mgmtVM"
        Write-Host "Admin user                     : $adminUser"
        Write-Host "Admin password                 : $adminPassword"
    }

    # Wait for management VM to start
    if ((($All -or $StartMgmtVM) -and $wait) -or $ConnectMgmtVM) {
        az vm start --ids $(az vm list -g $vdcResourceGroup --query "[?powerState!='VM running'].id" -o tsv)
    }
    
    # Set up RDP session to management VM
    if ($All -or $ConnectMgmtVM) {
        if ($IsWindows) {
            cmdkey.exe /generic:${mgmtVM} /user:${adminUser} /pass:${adminPassword}
            mstsc.exe /v:${mgmtVM} /f
        }
        if ($IsMacOS) {
            $rdpUrl = "rdp://${adminUser}:${adminPassword}@${mgmtVM}"
            Write-Information "Opening $rdpUrl"
            open $rdpUrl
        }
    }
} finally {
    $null = SetWorkspace -Workspace $priorWorkspace
    Pop-Location
}