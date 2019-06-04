# See https://www.terraform.io/docs/backends/types/azurerm.html

terraform {
  backend "azurerm" {
    resource_group_name  = "automation"
    # Use partial configuration, as we do not want to expose these details
    #storage_account_name = "tfbackend"
    #container_name       = "tfcontainer" 
    key                  = "terraform.tfstate"
  }
}

/* Not used
data "terraform_remote_state" "shared" {
  backend = "azurerm"

  config {
    resource_group_name  = "automation"
    container_name       = "shared"
    key                  = "terraform.tfstateenv:${terraform.workspace}"
  }
}
*/