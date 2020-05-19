<# 
.SYNOPSIS 
    Script used to bootstrap Management server
 
.DESCRIPTION 
    This script is downloaded and executed during first logon

.EXAMPLE
    cmd.exe /c start PowerShell.exe -ExecutionPolicy Bypass -Noexit -Command "&amp; {Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('${scripturl}'))}"
#> 

$config = (Get-Content $env:SystemDrive\AzureData\CustomData.bin | ConvertFrom-Json)

# Capture bootstrap command as script
$localBatchScript = "$env:PUBLIC\setup.cmd"
Write-Output "PowerShell.exe -ExecutionPolicy Bypass -Noexit -Command `"`& {$($MyInvocation.MyCommand.Definition)}`"" | Out-File -FilePath $localBatchScript -Encoding OEM

# Schedule bootstrap command to run on every logon
schtasks.exe /create /f /rl HIGHEST /sc onlogon /tn "Bootstrap" /tr $localBatchScript

# Download PowerShell script
$localPSScript = "$env:PUBLIC\setup.ps1"
Invoke-WebRequest -UseBasicParsing -Uri $config.scripturl -OutFile $localPSScript

# Create Private DNS demo script
$lookupScript = "$env:USERPROFILE\Desktop\privatelink_lookup.cmd"
if ($config -and $config.privatelinkfqdns) {
    $privateLinkFQDNs = $config.privatelinkfqdns.Split(",")
    Write-Output "echo Private DNS resolved PaaS FQDNs:" | Out-File $lookupScript -Force -Encoding OEM
    foreach ($privateLinkFQDN in $privateLinkFQDNs) {
        Write-Output "nslookup $privateLinkFQDN" | Out-File $lookupScript -Append -Encoding OEM
    }
    Write-Output "pause" | Out-File $lookupScript -Append -Encoding OEM
}

# Invoke bootstrap script from bootstrap-os repository
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/geekzter/bootstrap-os/master/windows/bootstrap_windows.ps1'))

# Install software required for demo
choco install azure-data-studio microsoftazurestorageexplorer sql-server-management-studio vscode -r -y
choco install TelnetClient --source windowsfeatures -r -y

# Create shortcuts
$wsh = New-Object -ComObject WScript.Shell
$bootstrapShortcut = $wsh.CreateShortcut("$($env:USERPROFILE)\Desktop\Setup.lnk")
$bootstrapShortcut.TargetPath = $localBatchScript
$bootstrapShortcut.Save()
$ssmsPath = (Get-ItemProperty -Path HKLM:\SOFTWARE\WOW6432Node\Microsoft\AppEnv\15.0\Apps\ssms_15.0 | Select-Object -ExpandProperty StubExePath)
$ssmsShortcut = $wsh.CreateShortcut("$($env:USERPROFILE)\Desktop\$($config.sqldatabase).lnk")
$ssmsShortcut.TargetPath = $ssmsPath
# MFA switch not yet supported: https://docs.microsoft.com/en-us/sql/ssms/ssms-utility?view=sql-server-ver15
# $ssmsShortcut.Arguments = "-s $($config.sqlserver) -d $($config.sqlserver) -G"
#$ssmsShortcut.Arguments = "-d $($config.sqldatabase)"
$ssmsShortcut.Description = "$($config.sqlserver)/$($config.sqldatabase)"
$ssmsShortcut.Save()

# Clone VDC repository
$repoRoot = "~\Source\GitHub\geekzter"
$null = New-Item -ItemType Directory -Force -Path $repoRoot
Push-Location $repoRoot
git clone https://github.com/geekzter/azure-vdc