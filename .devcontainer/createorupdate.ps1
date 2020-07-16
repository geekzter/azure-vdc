#!/usr/bin/env pwsh
# Runs post create commands to prep Codespace for project

# Update relevant packages
sudo apt-get update
#sudo apt-get install --only-upgrade -y azure-cli powershell
if (!(Get-Command tmux -ErrorAction SilentlyContinue)) {
    sudo apt-get install -y tmux
}

$repoDirectory = (Split-Path (get-childitem README.md -Path ~ -Recurse).FullName -Parent)
$terraformDirectory = Join-Path $repoDirectory "terraform"
$terraformVersion = (Get-Content $terraformDirectory/.terraform-version)
$profileTemplate = (Join-Path (Split-Path -Parent -Path $MyInvocation.MyCommand.Path) profile.ps1)

if (!(Get-Command tfenv -ErrorAction SilentlyContinue)) {
    Write-Host 'Installing tfenv...'
    git clone https://github.com/tfutils/tfenv.git ~/.tfenv
    sudo ln -s ~/.tfenv/bin/* /usr/local/bin
} else {
    Write-Host 'Installing tfenv...'
    git -C ~/.tfenv pull
}

tfenv install $terraformVersion
tfenv use $terraformVersion

Push-Location $terraformDirectory
terraform init -upgrade
Pop-Location

# PowerShell setup
if (!(Test-Path ~/bootstrap-os)) {
    git clone https://github.com/geekzter/bootstrap-os.git ~/bootstrap-os
} else {
    git -C ~/bootstrap-os pull
}
& ~/bootstrap-os/common/common_setup.ps1 -NoPackages
AddorUpdateModule Posh-Git

# PowerShell Profile
if (!(Test-Path $Profile)) {
    New-Item -ItemType symboliclink -Path $Profile -Target $profileTemplate -Force | Select-Object -ExpandProperty Name
}