variable resource_group_name {}
variable vdc_resource_group_id {}
variable location {}
variable tags {
  type                         = map
}
variable admin_ips {}
variable admin_ip_ranges {}
variable admin_login {}
variable admin_object_id {}
variable admin_username {}
#variable aad_auth_client_id {}
variable management_subnet_ids {
  type                         = list
}
variable database_import {
  type                         = bool
}
variable database_template_storage_key {
}
variable database_template_storage_uri {
  default                      = "https://ewimages.blob.core.windows.net/databasetemplates/vdcdevpaasappsqldb-2020-1-18-15-13.bacpac"
}
variable data_subnet_id {}
variable default_create_timeout {}
variable default_update_timeout {}
variable default_read_timeout {}
variable default_delete_timeout {}
variable deploy_app_service_network_integration {
  type                         = bool
}
variable deploy_private_dns_for_endpoint {
  type                         = bool
}
variable iag_subnet_id {}
variable integrated_subnet_range {}
variable integrated_subnet_id {}
variable integrated_vnet_id {}
variable shared_container_registry_name {}
variable shared_resources_group {}
variable storage_import {
  type                         = bool
}
variable storage_replication_type {}
variable vanity_url {}
variable waf_subnet_id {}

variable diagnostics_instrumentation_key {}
variable diagnostics_storage_id {}
variable diagnostics_workspace_resource_id {}