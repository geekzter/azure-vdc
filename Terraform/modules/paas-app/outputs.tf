output app_resource_group {
  value       = azurerm_resource_group.app_rg.name
}
output app_service_fqdn {
    value = azurerm_app_service.paas_web_app.default_site_hostname
}
# output app_service_msi_application_id1 {
#   value       = "${data.azuread_application.app_service_msi.application_id}"
# }
# output app_service_msi_application_id2 {
#   value       = "${data.azuread_service_principal.app_service_msi.application_id}"
# }
output app_service_msi_object_id {
  value       = azurerm_app_service.paas_web_app.identity.0.principal_id
}
output app_service_name {
    value = azurerm_app_service.paas_web_app.name
}

output app_service_outbound_ip_addresses {
    value = azurerm_app_service.paas_web_app.outbound_ip_addresses
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
# output sql_server_endpoint_id {
#     value = azurerm_private_link_endpoint.sqlserver_endpoint.id
# }
output sql_server_fqdn {
  value       = azurerm_sql_server.app_sqlserver.fully_qualified_domain_name
}
output sql_server_id {
    value = azurerm_sql_server.app_sqlserver.id
}
# output sql_server_private_ip_address {
#     value = azurerm_private_link_endpoint.sqlserver_endpoint.private_ip_address
# }
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