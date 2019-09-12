variable resource_group {}
variable vdc_resource_group {}
variable location {}
variable tags {
  type                         = map
}

variable admin_ips {}
variable admin_ip_ranges {}
variable appsvc_subnet_range {}
variable appsvc_subnet_id {}
variable endpoint_subnet_id {}
variable integrated_subnet_name {}
variable integrated_vnet_id {}
variable storage_replication_type {}
variable waf_subnet_id {}

variable diagnostics_instrumentation_key {}
variable diagnostics_storage_id {}
variable diagnostics_workspace_id {}
