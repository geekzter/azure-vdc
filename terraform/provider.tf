terraform {
  required_providers {
    azurerm                    = "~> 2.41"
    dns                        = "~> 2.2"
    external                   = "~> 1.2"
    http                       = "~> 1.2"
    null                       = "~> 2.1"
    random                     = "~> 2.3"
  }
  required_version             = "~> 0.14.3"
}

# Microsoft Azure Resource Manager Provider
#
# This provider block uses the following environment variables: 
# ARM_SUBSCRIPTION_ID, ARM_CLIENT_ID, ARM_CLIENT_SECRET and ARM_TENANT_ID
#
provider azurerm {
    # Pin Terraform version
    # Pipelines vdc-terraform-apply-ci/cd have a parameter unpinTerraformProviders ('=' -> '~>') to test forward compatibility
    features {
        virtual_machine {
            # Don't do this in production
            delete_os_disk_on_deletion = true
        }
    }
}