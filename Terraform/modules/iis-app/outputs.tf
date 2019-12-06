
output arm_resource_ids {
  value       = [] #azurerm_network_connection_monitor.devops_watcher.*.id
}

output app_resource_group {
  value       = azurerm_resource_group.app_rg.name
}

output app_resource_group_id {
  value       = azurerm_resource_group.app_rg.id
}
