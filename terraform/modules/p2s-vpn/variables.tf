variable resource_group_id {
  description                  = "The id of the resource group"
}
variable location {
  description                  = "The location/region where the virtual network is created. Changing this forces a new resource to be created."
}
variable tags {
  description = "A map of the tags to use for the resources that are deployed"
  type        = map
} 

variable default_create_timeout {}
variable default_update_timeout {}
variable default_read_timeout {}
variable default_delete_timeout {}

variable diagnostics_storage_id {
  description                  = "The id of the diagnostics storage account to use"
}
variable diagnostics_workspace_resource_id {
  description                  = "The id of the Log Analytics workspace to use"
}

variable virtual_network_id {
    description                = "The id of the Virtual Network to connect the VPN to"
}

variable subnet_range {
    description                = "The subnet range for the VPN GW subnet"
}
variable tenant_id {}
variable vpn_range {
    description                = "The client subnet range for VPN"
}

variable vpn_root_cert_name {
  default                      = "P2SRootCert" 
}

variable vpn_root_cert_file {
  description                  = "The relative path to the certificate CER file used for P2S root"
}


variable deploy_vpn {
  description                  = "Whether to deploy the point to Site VPN"
  type                         = bool
}