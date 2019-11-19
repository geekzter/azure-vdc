variable resource_group {
  description                  = "The name of the resource group"
}
variable vdc_resource_group_id {
  description                  = "The ID of the resource group"
}
variable location {
  description                  = "The location/region where the virtual network is created. Changing this forces a new resource to be created."
}
variable resource_environment {
  description = "The logical environment (tier) resource will be deployed in"
}

variable tags {
  description = "A map of the tags to use for the resources that are deployed"
  type        = map
} 

variable deploy_connection_monitors {
  description                  = "Whether to deploy connection monitors"
  default                      = false
  type                         = bool
}

variable diagnostics_storage_id {
  description                  = "The id of the diagnostics storage account to use"
}
variable diagnostics_workspace_resource_id {
  description                  = "The resource id of the Log Analytics workspace to use"
}
variable diagnostics_workspace_workspace_id {
  description                  = "The workspace id of the Log Analytics workspace to use"
}
variable diagnostics_workspace_key {}
variable diagnostics_watcher_id {
  description                  = "The id of the network watcher to use"
}

variable app_web_vms {}

variable app_db_vms {}

variable app_db_lb_address {}

########## Credentials #########
variable admin_username {
  description                  = "The admin user name"
}

variable admin_password {
  description                  = "The VDC admin password"
}

variable app_url {
  description                  = "The URL the app will be published at"
}

variable app_devops {
  type                         = map
}

variable app_storage_account_tier {
  description                  = "Defines the Tier of storage account to be created. Valid options are Standard and Premium."
  default                      = "Standard"
}

variable app_storage_replication_type {
  description                  = "Defines the Replication Type to use for this storage account. Valid options include LRS, GRS, ZRS etc."
  default                      = "ZRS"
}

variable app_web_vm_size {
  description                  = "Specifies the size of the Web virtual machines."
  default                      = "Standard_D2s_v3"
}
variable app_web_vm_number {}
variable app_web_image_publisher {
  description                  = "name of the publisher of the Web image (az vm image list)"
  default                      = "MicrosoftWindowsServer"
}
variable app_web_image_offer {
  description                  = "the name of the offer (az vm image list)"
  default                      = "WindowsServer"
}
variable app_web_image_sku {
  description                  = "image sku to apply (az vm image list)"
  default                      = "2019-Datacenter"
}
variable app_web_image_version {
  description                  = "version of the Web image to apply (az vm image list)"
  default                      = "latest"
}

variable app_db_vm_number {}
variable app_db_vm_size {
  description                  = "Specifies the size of the DB virtual machines."
  default                      = "Standard_D2s_v3"
}
variable app_db_image_publisher {
  description                  = "name of the publisher of the DB image (az vm image list)"
  default                      = "MicrosoftWindowsServer"
}
variable app_db_image_offer {
  description                  = "the name of the offer (az vm image list)"
  default                      = "WindowsServer"
}
variable app_db_image_sku {
  description                  = "image sku to apply (az vm image list)"
  default                      = "2019-Datacenter"
}
variable app_db_image_version {
  description                  = "version of the DB image to apply (az vm image list)"
  default                      = "latest"
}
variable app_subnet_id {
  description                  = "The id of the subnet to deploy app tier VM's in"
}
variable data_subnet_id {
  description                  = "The id of the subnet to deploy db tier VM's in"
}
variable vm_agent_dependency {
  description                  = "A dummy value that is used to force dependency"
}