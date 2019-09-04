variable resource_group {}
variable location {}
variable tags {
  type                         = map
}

variable address_space {}
variable dns_servers {
  default                      = []
}
variable hub_virtual_network_id {}
variable hub_virtual_network_name {}
variable spoke_virtual_network_name {}
variable subnets {
  type                         = map
}

variable diagnostics_storage_id {}
variable diagnostics_workspace_id {}