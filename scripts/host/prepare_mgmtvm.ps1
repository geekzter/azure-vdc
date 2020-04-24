<# 
.SYNOPSIS 
    Script used to bootstrap Management server
 
.DESCRIPTION 
    This script is downloaded and executed during first logon

.EXAMPLE
    cmd.exe /c start PowerShell.exe -ExecutionPolicy Bypass -Noexit -Command "&amp; {Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('${scripturl}'))}"
#> 

# PowerShell.exe -ExecutionPolicy Bypass -Noexit -Command "& {Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://vdcdevovkoautstorage.blob.core.windows.net/scripts/prepare_mgmtvm.ps1'))}"

# Capture bootstrap command as script
$localScript = "$env:PUBLIC\bootstrap.cmd"
Write-Output "PowerShell.exe -ExecutionPolicy Bypass -Noexit -Command `"`& {$($MyInvocation.MyCommand.Definition)}`"" | Out-File "$env:PUBLIC\bootstrapu.cmd"
Write-Output "PowerShell.exe -ExecutionPolicy Bypass -Noexit -Command `"`& {$($MyInvocation.MyCommand.Definition)}`"" | Out-File -FilePath $localScript -Encoding OEM

# Schedule bootstrap command to run on every logon
schtasks.exe /create /f /sc onlogon /tn "Bootstrap" /tr $localScript

# Create shortcut
# $wsh = New-Object -ComObject WScript.Shell
# $bootstrapShortcut = $wsh.CreateShortcut("$($env:USERPROFILE)\Desktop\Bootstrap.lnk")
# $bootstrapShortcut.TargetPath = $localScript
# $bootstrapShortcut.Save()

# Invoke bootstrap script from bootstrap-os repository
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/geekzter/bootstrap-os/master/windows/bootstrap_windows.ps1'))

# Install software required for demo
choco install azure-data-studio microsoftazurestorageexplorer sql-server-management-studio vscode -r -y
choco install TelnetClient --source windowsfeatures -r -y

# Clone VDC repository
Push-Location ~\Source\Public
git clone https://github.com/geekzter/azure-vdc