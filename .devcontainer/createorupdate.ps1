#!/usr/bin/env pwsh
# Runs post create commands to prep Codespace for project

# Update relevant packages
#sudo apt-get update && sudo apt-get install --only-upgrade -y azure-cli powershell

$repoDirectory = (Split-Path (get-childitem README.md -Path ~ -Recurse).FullName -Parent)
$terraformDirectory = Join-Path $repoDirectory "terraform"
$terraformVersion = $(Get-Content $terraformDirectory/.terraform-version)


if (Get-Command tfenv -ErrorAction SilentlyContinue) {
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
terraform init
Pop-Location
