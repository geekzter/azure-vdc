# Runs ppst create commands to prep Codespace for project

# Update relevant packages
sudo apt-get upgrade -y azure-cli powershell

# Set up terraform with tfenv
if [ ! -d ~/.tfenv ]; then
    echo $'\nInstalling tfenv...'
    git clone https://github.com/tfutils/tfenv.git ~/.tfenv
    sudo ln -s ~/.tfenv/bin/* /usr/local/bin
else
    echo $'\nUpdating tfenv...'
    git -C ~/.tfenv pull
fi
tfenv install $(cat ~/workspace/terraform/.terraform-version)

pushd ~/workspace/terraform
terraform init
popd