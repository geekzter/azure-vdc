# Microsoft Azure Resource Manager Provider

#
# This provider block uses the following environment variables: 
# ARM_SUBSCRIPTION_ID, ARM_CLIENT_ID, ARM_CLIENT_SECRET and ARM_TENANT_ID
#
provider "azurerm" {
    version = "~> 2.16"
    features {
        virtual_machine {
            # Don't do this in production
            delete_os_disk_on_deletion = true
        }
    }
}
