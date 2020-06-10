output app_resource_group {
  value       = azurerm_resource_group.app_rg.name
}
output app_service_fqdn {
    value = azurerm_app_service.paas_web_app.default_site_hostname
}
output app_service_scm_fqdn {
    value = replace(azurerm_app_service.paas_web_app.default_site_hostname,"azurewebsites.net","scm.azurewebsites.net")
}
output app_service_alias_fqdn {
    value = var.vanity_fqdn != null ? azurerm_app_service_custom_hostname_binding.alias_domain.0.hostname : azurerm_app_service.paas_web_app.default_site_hostname
}
output app_service_msi_client_id {
  value       = azurerm_user_assigned_identity.paas_web_app_identity.client_id 
}
output app_service_msi_object_id {
# value       = azurerm_app_service.paas_web_app.identity.0.principal_id
  value       = azurerm_user_assigned_identity.paas_web_app_identity.principal_id
}
output app_service_msi_name {
  value       = azurerm_user_assigned_identity.paas_web_app_identity.name
}
output app_service_name {
    value = azurerm_app_service.paas_web_app.name
}

output app_service_outbound_ip_addresses {
    value = azurerm_app_service.paas_web_app.outbound_ip_addresses
}

output dba_login {
    value = azurerm_sql_active_directory_administrator.dba.login
}

output dba_object_id {
    value = azurerm_sql_active_directory_administrator.dba.object_id
}

output eventhub_name {
    value = azurerm_eventhub.app_eventhub.name
}

output eventhub_namespace {
    value = azurerm_eventhub_namespace.app_eventhub.name
}

output eventhub_namespace_key {
    value = azurerm_eventhub_namespace.app_eventhub.default_primary_key
}

output eventhub_namespace_connection_string {
    value = azurerm_eventhub_namespace.app_eventhub.default_primary_connection_string
}

output eventhub_namespace_fqdn {
  value       = "${lower(azurerm_eventhub.app_eventhub.name)}.servicebus.windows.net"
}

output eventhub_storage_account_name {
    value = azurerm_storage_account.archive_storage.name
}

output primary_blob_host {
    value = azurerm_storage_account.app_storage.primary_blob_host
}
output primary_queue_host {
    value = azurerm_storage_account.app_storage.primary_queue_host
}
output primary_table_host {
    value = azurerm_storage_account.app_storage.primary_table_host
}
output primary_file_host {
    value = azurerm_storage_account.app_storage.primary_file_host
}
output primary_dfs_host {
    value = azurerm_storage_account.app_storage.primary_dfs_host
}
output primary_web_host {
    value = azurerm_storage_account.app_storage.primary_web_host
}

output sql_database {
    value = azurerm_sql_database.app_sqldb.name
}
output sql_server {
    value = azurerm_sql_server.app_sqlserver.name
}
output sql_server_endpoint_id {
    value = try(azurerm_private_endpoint.sqlserver_endpoint.0.id,null)
}
output sql_server_endpoint_fqdn {
    value = replace(try(azurerm_private_dns_a_record.sql_server_dns_record.0.fqdn,""),"/\\W*$/","")
}
output sql_server_fqdn {
  value       = azurerm_sql_server.app_sqlserver.fully_qualified_domain_name
}
output sql_server_id {
    value = azurerm_sql_server.app_sqlserver.id
}
output sql_server_private_ip_address {
    value = try(azurerm_private_endpoint.sqlserver_endpoint.0.private_service_connection[0].private_ip_address,null)
}
output storage_account_name {
    value = azurerm_storage_account.app_storage.name
}

output blob_storage_fqdn {
    value = azurerm_storage_account.app_storage.primary_blob_host
}

output storage_fqdns {
    value = [
        azurerm_storage_account.app_storage.primary_blob_host,
        # "${azurerm_storage_account.app_storage.secondary_blob_host}",
        azurerm_storage_account.app_storage.primary_queue_host,
        # "${azurerm_storage_account.app_storage.secondary_queue_host}",
        azurerm_storage_account.app_storage.primary_table_host,
        # "${azurerm_storage_account.app_storage.secondary_table_host}",
        azurerm_storage_account.app_storage.primary_file_host,
        # "${azurerm_storage_account.app_storage.secondary_file_host}",
        azurerm_storage_account.app_storage.primary_dfs_host,
        # "${azurerm_storage_account.app_storage.secondary_dfs_host}",
        azurerm_storage_account.app_storage.primary_web_host,
        # "${azurerm_storage_account.app_storage.secondary_web_host}",
    ]
}

output resource_group_id {
    value = azurerm_resource_group.app_rg.id
}