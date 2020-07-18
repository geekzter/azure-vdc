# Microsoft Azure Resource Manager Provider

#
# This provider block uses the following environment variables: 
# ARM_SUBSCRIPTION_ID, ARM_CLIENT_ID, ARM_CLIENT_SECRET and ARM_TENANT_ID
#
provider azurerm {
    # Pin Terraform version, pipelines vdc-terraform-apply-cicd unpin as part of the pipeline
    # Ignore versions that have this issue:
    # https://github.com/terraform-providers/terraform-provider-azurerm/issues/7691
    version = "= 2.17, != 2.18, != 2.19"
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