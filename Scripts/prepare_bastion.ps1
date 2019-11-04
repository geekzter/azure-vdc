<# 
.SYNOPSIS 
    
 
.DESCRIPTION 
    

.EXAMPLE
    cmd.exe /c start PowerShell.exe -ExecutionPolicy Bypass -Noexit -Command "&amp; {Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('${scripturl}'))}"
#> 

# Invoke bootstrap script from bootstrap-os repository
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/geekzter/bootstrap-os/master/windows/bootstrap_windows.ps1'))

# Install software required for demo
choco.exe install azure-data-studio microsoftazurestorageexplorer sql-server-management-studio vscode -r -y

# Clone VDC repository
Push-Location ~\Source\Public
git clone https://github.com/geekzter/bootstrap-os