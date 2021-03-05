terraform {
  required_providers {
    azurerm                    = "~> 2.50"
    dns                        = "~> 3.0"
    external                   = "~> 2.0"
    http                       = "~> 2.0"
    null                       = "~> 3.0"
    random                     = "~> 3.0"
    time                       = "~> 0.6"
  }
  required_version             = "~> 0.13"
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
        key_vault {
            # BUG: "The user, group or application 'appid=00000000-0000-0000-0000-000000000000;oid=00000000-0000-0000-0000-000000000000;numgroups=144;iss=https://sts.windows.net/00000000-0000-0000-0000-000000000000/' does not have keys purge permission on key vault 'vdc-dflt-vault-xxxx'. ""
            purge_soft_delete_on_destroy = false
        }
        virtual_machine {
            # Don't do this in production
            delete_os_disk_on_deletion = true
        }
    }
}