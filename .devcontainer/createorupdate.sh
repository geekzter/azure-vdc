# Runs ppst create commands to prep Codespace for project

# Update relevant packages
#sudo apt-get update && sudo apt-get install --only-upgrade -y azure-cli powershell

# Set up terraform with tfenv
if [ ! -d ~/.tfenv ]; then
    echo $'\nInstalling tfenv...'
    git clone https://github.com/tfutils/tfenv.git ~/.tfenv
    sudo ln -s ~/.tfenv/bin/* /usr/local/bin
else
    echo $'\nUpdating tfenv...'
    git -C ~/.tfenv pull
fi
TF_VERSION=$(cat ~/workspace/terraform/.terraform-version)
tfenv install $TF_VERSION
tfenv use $TF_VERSION

pushd ~/workspace/terraform
terraform init
popd