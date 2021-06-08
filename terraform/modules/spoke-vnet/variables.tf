variable resource_group_id {}
variable location {}
variable tags {
  type                         = map
}

variable address_space {}
variable bastion_subnet_range {}
variable default_create_timeout {}
variable default_update_timeout {}
variable default_read_timeout {}
variable default_delete_timeout {}
variable deploy_network_watcher {
  type                         = bool
}
variable dns_servers {
  default                      = []
}
variable gateway_ip_address {}
variable hub_virtual_network_id {}
variable enable_routetable_for_subnets {
  type                         = list
}
variable private_dns_zones {
  type                         = list
}
variable spoke_virtual_network_name {}
variable service_endpoints {
  type                         = map
}
variable subnets {
  type                         = map
}
variable subnet_delegations {
  type                         = map
}
variable use_hub_gateway {
  type                         = bool
}

variable diagnostics_storage_id {}
variable diagnostics_workspace_resource_id {}
variable diagnostics_workspace_workspace_id {}
variable network_watcher_name {}
variable network_watcher_resource_group_name {}
variable workspace_location {}