# Microsoft Azure Resource Manager Provider

#
# Uncomment this provider block if you have set the following environment variables: 
# ARM_SUBSCRIPTION_ID, ARM_CLIENT_ID, ARM_CLIENT_SECRET and ARM_TENANT_ID
#
provider "azurerm" {
    version = "~> 1.32" # 1.29 required for Azure FW NAT rules
}

#
# Uncomment this provider block if you are using variables (NOT environment variables)
# to provide the azurerm provider requirements.
# Make sure you exclude secrets from source control!
#
#provider "azurerm" {
#  subscription_id             = "ffffffff-ffff-ffff-ffff-ffffffffffff"
#  client_id                   = "ffffffff-ffff-ffff-ffff-ffffffffffff"
#  client_secret               = "ffffffff-ffff-ffff-ffff-ffffffffffff"
#  tenant_id                   = "ffffffff-ffff-ffff-ffff-ffffffffffff"
#}