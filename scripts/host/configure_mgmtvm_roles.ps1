<# 
.SYNOPSIS 
    Script used to configure Management server roles
 
.DESCRIPTION 
    This script is downloaded and executed using the custom script VM extension
#> 
#Set-PSDebug -Trace 1 # Trace in the case the extension doesn't successfully load

$privateDNS = "168.63.129.16" # Azure Private DNS
$publicDNS = @("8.8.8.8","8.8.4.4") # Google Public DNS

$dnsFeature = (Get-WindowsFeature | Where-Object {($_.Name -ieq "DNS") -and ($_.InstallState -ieq "Installed")})

if (!$dnsFeature) {
    Install-WindowsFeature DNS -IncludeManagementTools
}

Add-DnsServerForwarder -IPAddress $publicDNS

# Configure conditional zone forwarders
# For a full and up to date list of zones see:
# https://docs.microsoft.com/en-us/azure/private-link/private-endpoint-dns

$zoneListFile = (Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "private_link_zones.conf")

if (!(Test-Path $zoneListFile)) {
    Write-Error "$zoneListFile not found, quiting..."
    exit
}

foreach ($zone in (Get-Content $zoneListFile)) {
    if ($zone -match "^[\.\-\w]*$"){
        if (!(Get-DnsServerZone $zone -ErrorAction SilentlyContinue)) {
            # https://docs.microsoft.com/en-us/powershell/module/dnsserver/add-dnsserverconditionalforwarderzone
            Add-DnsServerConditionalForwarderZone -Name $zone -MasterServers $privateDNS
        }
    }
}

# Clear cache, so we start using new configuration immediately
Clear-DnsServerCache -Force

# Show configuration
Get-DnsServerZone | Select-Object ZoneName, ZoneType, MasterServers
Get-DnsServerForwarder | Format-Table
