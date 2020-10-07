#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    This creates allow rules for the current connection, start management VM, and displays credentials needed

#> 
#Requires -Version 7

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
. (Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) get_tf_version.ps1) -ValidateInstalledVersion
AzLogin

try {
    # Terraform config
    Push-Location $tfdirectory
    $priorWorkspace = (SetWorkspace -Workspace $Workspace -ShowWorkspaceName).PriorWorkspaceName

    $vdcResourceGroup = (GetTerraformOutput "vdc_resource_group")
    $paasAppResourceGroup = (GetTerraformOutput "paas_app_resource_group")
    
    if ($All -or $StartMgmtVM -or $ConnectMgmtVM -or $VpnClient) {
        $Script:mgmtVMName = (GetTerraformOutput "mgmt_name")
        # Start management VM
        if ($mgmtVMName) {
            Write-Host "`nStarting Management & DNS Server (async)" -ForegroundColor Green 
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

        # Add IP prefix to Admin IP Group
        $adminIPGroup = (GetTerraformOutput "admin_ipgroup")
        az extension add --name ip-group 2>$null
        if ($adminIPGroup) {
            if ($(az network ip-group show -n $adminIPGroup -g $vdcResourceGroup --query "contains(ipAddresses,'$ipPrefix')") -ieq "false") {
                Write-Host "Adding $ipPrefix to admin ip group $adminIPGroup..."
                az network ip-group update -n $adminIPGroup -g $vdcResourceGroup --add ipAddresses $ipPrefix -o none
            } else {
                Write-Information "$ipPrefix is already in admin ip group $adminIPGroup"
            }
        } else {
            Write-Warning "Admin IP group not found, not updating Azure Firewall"
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
            $msiClientId   = (GetTerraformOutput paas_app_service_msi_client_id)
            $msiName       = (GetTerraformOutput paas_app_service_msi_name)
            $sqlDB         = (GetTerraformOutput paas_app_sql_database)
            $sqlServerName = (GetTerraformOutput paas_app_sql_server)
            $sqlServerFQDN = (GetTerraformOutput paas_app_sql_server_fqdn)

            Write-Information "Determening current Azure Active Directory DBA for SQL Server $sqlServerName..."
            $dba = az sql server ad-admin list -g $paasAppResourceGroup -s $sqlServerName --query "[?login=='${sqlAADUser}']" -o json | ConvertFrom-Json
            if ($dba) {
                Write-Host "$($dba.login) is already current Azure Active Directory DBA for SQL Server $sqlServerName"
            } else {
                $loggedInUser = (az ad signed-in-user show --query "{ObjectId:objectId,UserName:userPrincipalName}" | ConvertFrom-Json)
                $dba = az sql server ad-admin create -u $loggedInUser.UserName -i $loggedInUser.ObjectId -g $paasAppResourceGroup -s $sqlServerName -o json | ConvertFrom-Json
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
        $gatewayId = (GetTerraformOutput vpn_gateway_id)
        if ($gatewayId) {
            $vpnPackageUrl = $(az network vnet-gateway vpn-client generate --ids $gatewayId --authentication-method EAPTLS -o tsv)

            # Download VPN Profile
            Write-Host "Generating VPN profile..."
            $packageFile = New-TemporaryFile
            Invoke-WebRequest -UseBasicParsing -Uri $vpnPackageUrl -OutFile $packageFile
            $tempPackagePath = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
            $null = New-Item -ItemType "directory" -Path $tempPackagePath
            Expand-Archive -Path $packageFile -DestinationPath $tempPackagePath
            $vpnProfileTempFile = Join-Path $tempPackagePath AzureVPN azurevpnconfig.xml
            Write-Verbose "VPN Temp Profile ${vpnProfileTempFile}"

            # Edit VPN Profile
            Write-Host "Modifying VPN profile DNS configuration..."
            $vpnProfileXml = [xml](Get-Content $vpnProfileTempFile)
            $clientconfig = $vpnProfileXml.SelectSingleNode("//*[name()='clientconfig']")
            $dnsservers = $vpnProfileXml.CreateElement("dnsservers", $vpnProfileXml.AzVpnProfile.xmlns)
            $dnsserver = $vpnProfileXml.CreateElement("dnsserver", $vpnProfileXml.AzVpnProfile.xmlns)
            $dnsserver.InnerText = (GetTerraformOutput "vdc_dns_server")
            $dnsservers.AppendChild($dnsserver) | Out-Null
            $clientconfig.AppendChild($dnsservers) | Out-Null
            $clientconfig.RemoveAttribute("nil","http://www.w3.org/2001/XMLSchema-instance")

            if ((Get-Command azurevpn -ErrorAction SilentlyContinue) -and $IsWindows) {
                $vpnProfileFile = (Join-Path $env:userprofile\AppData\Local\Packages\Microsoft.AzureVpn_8wekyb3d8bbwe\LocalState ("$vdcResourceGroup{0}" -f ".xml"))
                $vpnProfileXml.Save($vpnProfileFile)
                Write-Host "Azure VPN app importing profile '$vpnProfileFile'..."
                azurevpn -i (Split-Path $vpnProfileFile -Leaf) -f
                #Get-DnsClientNrptPolicy
            } else {
                $vpnProfileXml.Save($vpnProfileTempFile)
                Write-Host "Use the Azure VPN app (https://go.microsoft.com/fwlink/?linkid=2117554) to import this profile:`n${vpnProfileTempFile}"
            }
        } else {
            Write-Host "VPN is not enabled, did set deploy_vpn = true?" -ForegroundColor Yellow
        }
    }

    # TODO: Request JIT access to Management VM, once azurerm Terraform provider supports it
    if ($All -or $ShowCredentials -or $ConnectMgmtVM) {
        $Script:adminUser = (GetTerraformOutput admin_user)
        $Script:adminPassword = (GetTerraformOutput admin_password)
        $Script:mgmtVM = "$(GetTerraformOutput iag_public_ip):$(GetTerraformOutput mgmt_rdp_port)"

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