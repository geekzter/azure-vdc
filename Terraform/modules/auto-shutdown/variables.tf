variable resource_group {
  description                  = "The name of the resource group"
}
variable location {
  description                  = "The location/region where the virtual network is created. Changing this forces a new resource to be created."
}

variable resource_group_ids {
  type                         = "list"
}
variable resource_environment {
  description = "The logical environment (tier) resource will be deployed in"
}

variable tags {
  description = "A map of the tags to use for the resources that are deployed"
  type        = "map"
} 

variable app_resource_group {
  description                  = "The name of the app resource group"
}

variable app_storage_replication_type {
  description                  = "Defines the Replication Type to use for this storage account. Valid options include LRS, GRS etc."
}

variable deploy_auto_shutdown {
  description                  = "Whether to deploy the Auto shutdown function"
  type                         = bool
}

variable diagnostics_instrumentation_key {
  description                  = "The instrumentatinn key to use for application insights"
}
variable diagnostics_storage_id {
  description                  = "The id of the diagnostics storage account to use"
}
variable diagnostics_workspace_id {
  description                  = "The id of the Log Analytics workspace to use"
}