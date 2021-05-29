<# 
.SYNOPSIS 
    Script used to bootstrap Management server
 
.DESCRIPTION 
    This script is downloaded and executed during first logon

.EXAMPLE
    cmd.exe /c start PowerShell.exe -ExecutionPolicy Bypass -Noexit -Command "&amp; {Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('{scripturl}'))}"
#> 

# Propagate Terraform templatefile() provided variables
$privateLinkFQDNsConfig = 'vdcdfltpaasapprcbmsqlserver.database.windows.net,vdcdfltrcbmdiagstor.blob.core.windows.net,vdcdfltrcbmdiagstor.table.core.windows.net,vdc-dflt-paasapp-rcbm-appsvc-app.azurewebsites.net,vdc-dflt-paasapp-rcbm-appsvc-app.scm.azurewebsites.net'
$paasAppURL             = 'https://vdc-dflt-paasapp-rcbm-appsvc-app.azurewebsites.net'
$portalURL              = 'https://portal.azure.com/#dashboard/arm/subscriptions/84c1a2c7-585a-4753-ad28-97f69618cf12/resourceGroups/vdc-dflt-rcbm/providers/Microsoft.Portal/dashboards/VDC-dflt-default'
$scmURL                 = 'https://vdc-dflt-paasapp-rcbm-appsvc-app.scm.azurewebsites.net'
$sqlDatabase            = 'vdcdfltpaasapprcbmsqldb'
$sqlServer              = 'vdcdfltpaasapprcbmsqlserver.database.windows.net'

# Capture bootstrap command as script
$localBatchScript = "$env:PUBLIC\setup.cmd"
$localPSScript = $PSCommandPath
Write-Output "PowerShell.exe -ExecutionPolicy Bypass -Noexit -File $localPSScript" | Out-File -FilePath $localBatchScript -Encoding OEM
schtasks.exe /create /f /rl HIGHEST /sc onlogon /tn "Bootstrap" /tr $localBatchScript

# Create Private DNS demo script
$lookupScript = "$env:USERPROFILE\Desktop\privatelink_lookup.cmd"
if ($privateLinkFQDNsConfig) {
    $privateLinkFQDNs = $privateLinkFQDNsConfig.Split(",")
    Write-Output "echo Private DNS resolved PaaS FQDNs:" | Out-File $lookupScript -Force -Encoding OEM
    foreach ($privateLinkFQDN in $privateLinkFQDNs) {
        Write-Output "nslookup $privateLinkFQDN" | Out-File $lookupScript -Append -Encoding OEM
    }
    Write-Output "pause" | Out-File $lookupScript -Append -Encoding OEM
}

# Invoke bootstrap script from bootstrap-os repository
$bootstrapScript = "$env:PUBLIC\bootstrap_windows.ps1"
(New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/geekzter/bootstrap-os/master/windows/bootstrap_windows.ps1') | Out-File $bootstrapScript -Force
. $bootstrapScript

# Install software required for demo
choco install azure-data-studio microsoftazurestorageexplorer sql-server-management-studio vscode -r -y
choco install TelnetClient --source windowsfeatures -r -y

# Create shortcuts
$wsh = New-Object -ComObject WScript.Shell

$bootstrapShortcut = $wsh.CreateShortcut("$($env:USERPROFILE)\Desktop\Setup.lnk")
$bootstrapShortcut.TargetPath = $localBatchScript
$bootstrapShortcut.Save()

$paasAppShortcut = $wsh.CreateShortcut("$($env:USERPROFILE)\Desktop\PaaSApp.url")
$paasAppShortcut.TargetPath = $paasAppURL
$paasAppShortcut.Save()

$paasAppShortcut = $wsh.CreateShortcut("$($env:USERPROFILE)\Desktop\Portal Dashboard.url")
$paasAppShortcut.TargetPath = $portalURL
$paasAppShortcut.Save()

$scmShortcut = $wsh.CreateShortcut("$($env:USERPROFILE)\Desktop\SCM.url")
$scmShortcut.TargetPath = $scmURL 
$scmShortcut.Save() 

$ssmsPath = (Get-ItemProperty -Path HKLM:\SOFTWARE\WOW6432Node\Microsoft\AppEnv\15.0\Apps\ssms_15.0 | Select-Object -ExpandProperty StubExePath)
$ssmsShortcut = $wsh.CreateShortcut("$($env:USERPROFILE)\Desktop\$($sqlDatabase).lnk")
$ssmsShortcut.TargetPath = $ssmsPath
# MFA switch not yet supported: https://docs.microsoft.com/en-us/sql/ssms/ssms-utility?view=sql-server-ver15
# $ssmsShortcut.Arguments = "-s sqlServer -d sqlDatabase -G"
#$ssmsShortcut.Arguments = "-d $sqlDatabase"
$ssmsShortcut.Description = "$($sqlServer)/$($sqlDatabase)"
$ssmsShortcut.Save()

# Clone VDC repository
$repoRoot = "~\Source\GitHub\geekzter"
$null = New-Item -ItemType Directory -Force -Path $repoRoot
Push-Location $repoRoot
git clone https://github.com/geekzter/azure-vdc