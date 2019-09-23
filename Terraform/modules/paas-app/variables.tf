variable resource_group_name {}
variable vdc_resource_group_id {}
variable location {}
variable tags {
  type                         = map
}

variable admin_ips {}
variable admin_ip_ranges {}
variable admin_username {}
variable database_template_storage_key {
}
variable database_template_storage_uri {
  default = "https://ewimages.blob.core.windows.net/databasetemplates/DotNetAppSqlDb20181207093001_db-2018-12-7-10-37.bacpac"
}
variable dba_login {}
variable dba_object_id {}
variable iag_subnet_id {}
variable integrated_subnet_range {}
variable integrated_subnet_id {}
variable integrated_vnet_id {}
variable storage_replication_type {}
variable waf_subnet_id {}

variable diagnostics_instrumentation_key {}
variable diagnostics_storage_id {}
variable diagnostics_workspace_id {}
