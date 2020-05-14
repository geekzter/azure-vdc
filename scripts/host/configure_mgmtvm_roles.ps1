<# 
.SYNOPSIS 
    Script used to configure Management server roles
 
.DESCRIPTION 
    This script is downloaded and executed using the custom script VM extension
#> 

$dnsFeature = (Get-WindowsFeature | Where-Object {($_.Name -ieq "DNS") -and ($_.InstallState -ieq "Installed")})

if (!$dnsFeature) {
    Install-WindowsFeature DNS -IncludeManagementTools
    Add-DnsServerForwarder -IPAddress 168.63.129.16
}