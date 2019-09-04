variable "resource_group" {
  description                  = "The name of the resource group"
}
variable "location" {
  description                  = "The location/region where the virtual network is created. Changing this forces a new resource to be created."
}
variable "tags" {
  description = "A map of the tags to use for the resources that are deployed"
  type        = "map"
} 

variable "diagnostics_storage_id" {
  description                  = "The id of the diagnostics storage account to use"
}
variable "diagnostics_workspace_id" {
  description                  = "The id of the Log Analytics workspace to use"
}

variable "subnet_range" {}

variable "virtual_network_name" {
    description                = "The name of the Virtual Network to connect the VPN to"
}

variable "deploy_managed_bastion" {
  description                  = "Whether to deploy the Managed Bastion (preview)"
  default                      = true
  type                         = bool
}