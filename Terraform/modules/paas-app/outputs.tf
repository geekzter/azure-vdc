
output eventhub_name {
    value = "${azurerm_eventhub.app_eventhub.name}"
}

output eventhub_namespace_key {
    value = "${azurerm_eventhub_namespace.app_eventhub.default_primary_key}"
}

output eventhub_namespace_connection_string {
    value = "${azurerm_eventhub_namespace.app_eventhub.default_primary_connection_string}"
}

output "eventhub_namespace_fqdn" {
  value       = "${lower(azurerm_eventhub.app_eventhub.name)}.servicebus.windows.net"
}

output spoke_vnet_guid {
    value     = "${trimspace(file(local.spoke_vnet_guid_file))}"
}

output primary_blob_host {
    value = "${azurerm_storage_account.app_storage.primary_blob_host}"
}
output primary_queue_host {
    value = "${azurerm_storage_account.app_storage.primary_queue_host}"
}
output primary_table_host {
    value = "${azurerm_storage_account.app_storage.primary_table_host}"
}
output primary_file_host {
    value = "${azurerm_storage_account.app_storage.primary_file_host}"
}
output primary_dfs_host {
    value = "${azurerm_storage_account.app_storage.primary_dfs_host}"   
}
output primary_web_host {
    value = "${azurerm_storage_account.app_storage.primary_web_host}"
}

output storage_account_name {
    value = "${azurerm_storage_account.app_storage.name}"
}

output storage_fqdns {
    value = [
        "${azurerm_storage_account.app_storage.primary_blob_host}",
        # "${azurerm_storage_account.app_storage.secondary_blob_host}",
        "${azurerm_storage_account.app_storage.primary_queue_host}",
        # "${azurerm_storage_account.app_storage.secondary_queue_host}",
        "${azurerm_storage_account.app_storage.primary_table_host}",
        # "${azurerm_storage_account.app_storage.secondary_table_host}",
        "${azurerm_storage_account.app_storage.primary_file_host}",
        # "${azurerm_storage_account.app_storage.secondary_file_host}",
        "${azurerm_storage_account.app_storage.primary_dfs_host}",
        # "${azurerm_storage_account.app_storage.secondary_dfs_host}",
        "${azurerm_storage_account.app_storage.primary_web_host}",
        # "${azurerm_storage_account.app_storage.secondary_web_host}",
    ]
}

output resource_group_id {
    value = "${azurerm_resource_group.app_rg.id}"
}