# Microsoft Azure Resource Manager Provider

#
# This provider block uses the following environment variables: 
# ARM_SUBSCRIPTION_ID, ARM_CLIENT_ID, ARM_CLIENT_SECRET and ARM_TENANT_ID
#
provider azurerm {
    # Pin Terraform version
    # Pipelines vdc-terraform-apply-ci/cd have a parameter unpinTerraformProviders ('=' -> '~>') to test forward compatibility
    version = "= 2.33"
    features {
        virtual_machine {
            # Don't do this in production
            delete_os_disk_on_deletion = true
        }
    }
}

provider dns {
    version = "~> 2.2"
}

provider external {
    version = "~> 1.2"
}

provider http {
    version = "~> 1.2"
}

provider null {
    version = "~> 2.1"
}

provider random {
    version = "~> 2.3"
}