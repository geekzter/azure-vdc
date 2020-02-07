
output arm_resource_ids {
  value       = [] #azurerm_network_connection_monitor.devops_watcher.*.id
}

output app_resource_group {
  value       = azurerm_resource_group.app_rg.name
}

output app_resource_group_id {
  value       = azurerm_resource_group.app_rg.id
}

output virtual_machine_ids {
  value       = concat(azurerm_virtual_machine.app_db_vm.*.id,azurerm_virtual_machine.app_web_vm.*.id)
}

output monitoring_agent_ids {
  value       = concat(azurerm_virtual_machine_extension.app_web_vm_monitor.*.id,azurerm_virtual_machine_extension.app_db_vm_monitor.*.id)
}