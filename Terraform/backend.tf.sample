# See https://www.terraform.io/docs/backends/types/azurerm.html

terraform {
  backend "azurerm" {
    resource_group_name        = "automation"
    # Use partial configuration, as we do not want to expose these details in source control
    #storage_account_name      = "tfbackend"
    container_name             = "vdc" 
    key                        = "terraform.tfstate"
  }
}

locals {
  state_key                    = terraform.workspace == "default" ? "terraform.tfstate" : "terraform.tfstateenv:${terraform.workspace}"
}

data "terraform_remote_state" "vdc" {
  backend = "azurerm"

  config                       = {
    resource_group_name        = "automation"
    storage_account_name       = var.backend_storage_account
    container_name             = "vdc"
    key                        = local.state_key
  }
}