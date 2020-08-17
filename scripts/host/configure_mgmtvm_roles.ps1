<# 
.SYNOPSIS 
    Script used to configure Management server roles
 
.DESCRIPTION 
    This script is downloaded and executed using the custom script VM extension
#> 

$dnsFeature = (Get-WindowsFeature | Where-Object {($_.Name -ieq "DNS") -and ($_.InstallState -ieq "Installed")})

if (!$dnsFeature) {
    Install-WindowsFeature DNS -IncludeManagementTools
    
    # Use conditional zone level forwarders instead
    # Add-DnsServerForwarder -IPAddress 168.63.129.16
}

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
            Add-DnsServerConditionalForwarderZone -Name $zone -MasterServers 168.63.129.16 #-PassThru
        }
    }
}

# List all configured zones
Get-DnsServerZone | Select-Object ZoneName, ZoneType, MasterServers