# Microsoft Azure Resource Manager Provider

#
# This provider block uses the following environment variables: 
# ARM_SUBSCRIPTION_ID, ARM_CLIENT_ID, ARM_CLIENT_SECRET and ARM_TENANT_ID
#
provider "azurerm" {
    version = "~> 1.32, != 1.33.0, != 1.33.1, < 2.0"  # 1.29 required for Azure FW NAT rules, 1.33 is broken :-(, ignore v2 for now
}
