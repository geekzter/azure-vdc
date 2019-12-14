<# 
.SYNOPSIS 
    Script used to bootstrap Bastion server
 
.DESCRIPTION 
    This script is downloaded and executed during first logon

.EXAMPLE
    cmd.exe /c start PowerShell.exe -ExecutionPolicy Bypass -Noexit -Command "&amp; {Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('${scripturl}'))}"
#> 

# Invoke bootstrap script from bootstrap-os repository
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/geekzter/bootstrap-os/master/windows/bootstrap_windows.ps1'))

# Install software required for demo
choco install azure-data-studio microsoftazurestorageexplorer sql-server-management-studio vscode -r -y
choco install TelnetClient --source windowsfeatures -r -y

# Clone VDC repository
Push-Location ~\Source\Public
git clone https://github.com/geekzter/azure-vdc