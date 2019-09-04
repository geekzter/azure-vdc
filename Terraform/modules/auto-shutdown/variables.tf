variable "resource_group" {
  description                  = "The name of the resource group"
}

variable "app_resource_group" {
  description                  = "The name of the app resource group"
}

variable "resource_group_ids" {
  type                         = "list"
}
variable "resource_environment" {
  description = "The logical environment (tier) resource will be deployed in"
  default     = "" # Empty string defaults to workspace name
}

variable "tags" {
  description = "A map of the tags to use for the resources that are deployed"
  type        = "map"

  default = {
    application                = "Automated VDC"
    provisioner                = "terraform"
  }
} 

variable "app_storage_replication_type" {
  description                  = "Defines the Replication Type to use for this storage account. Valid options include LRS, GRS etc."
  default                      = "ZRS"
}

######### Resource Group #########
variable "location" {
  description                  = "The location/region where the virtual network is created. Changing this forces a new resource to be created."
  default                      = "westeurope"
}

variable "app_insights_key" {
  description                  = "The instrumentatinn key to use for application insights"
}
variable "diagnostics_storage_id" {
  description                  = "The id of the diagnostics storage account to use"
}
variable "workspace_id" {
  description                  = "The id of the Log Analytics workspace to use"
}

variable "deploy_auto_shutdown" {
  description                  = "Whether to deploy the Auto shutdown function"
  default                      = true
  type                         = bool
}
