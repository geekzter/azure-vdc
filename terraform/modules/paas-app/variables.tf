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
variable aad_auth_client_id_map {}
variable app_subnet_id {}
variable container {}
variable container_registry {}
variable container_registry_spn_app_id {}
variable container_registry_spn_secret {}
variable management_subnet_ids {
  type                         = list
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
variable disable_public_database_access {
  type                         = bool
}
variable enable_private_link {
  type                         = bool
}
variable enable_aad_auth {
  type                         = bool
}
variable grant_database_access {
  type                         = bool
}
variable iag_subnet_id {}
variable integrated_subnet_range {}
variable integrated_subnet_id {}
variable integrated_vnet_id {}
variable shared_resources_group {}
variable storage_import {
  type                         = bool
}
variable storage_replication_type {}
variable vanity_certificate_name {}
variable vanity_certificate_password {}
variable vanity_certificate_path {}
variable vanity_dns_zone_id {}
variable vanity_domainname {}
variable vanity_fqdn {}
variable vanity_url {}
variable waf_subnet_id {}

variable diagnostics_instrumentation_key {}
variable diagnostics_storage_id {}
variable diagnostics_workspace_resource_id {}