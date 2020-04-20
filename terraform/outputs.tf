output admin_user {
  sensitive   = false
  description = "VDC Admin username"
  value       = var.admin_username
}
output admin_password {
  sensitive   = true
  description = "VDC Admin password"
  value       = local.password
}

output application_insights_id {
  value       = azurerm_application_insights.vdc_insights.app_id
}

output app_storage_fqdns {
  value       = [
    azurerm_firewall_application_rule_collection.iag_app_rules.rule.0.target_fqdns
    ]
}

# Export Resource ID's of resources created in embedded ARM templates
# This can be used in script to manage (e.g. clean up) these resources as Terraform doesn't know about them
output arm_resource_ids {
  value       = concat(module.iis_app.arm_resource_ids,
                       #azurerm_network_connection_monitor.eventhub_watcher.*.id,azurerm_network_connection_monitor.storage_watcher.*.id
                       )
}

output automation_account {
  value       = azurerm_automation_account.automation.name
}

output automation_account_resource_group {
  value       = azurerm_automation_account.automation.resource_group_name
}

output mgmt_address {
  value       = var.vdc_config["hub_mgmt_address"]
}

# output mgmt_firstlogoncommand {
#   value                  = templatefile("../scripts/host/ManagementFirstLogonCommands.xml", { 
#     username               = var.admin_username, 
#     password               = local.password, 
#     hosts                  = concat(var.app_web_vms,var.app_web_vms),
#     scripturl              = azurerm_storage_blob.mgmt_prepare_script.url,
#     sqlserver              = module.paas_app.sql_server_fqdn
#   })
# }

output mgmt_name {
  value = azurerm_windows_virtual_machine.mgmt.name
}

output mgmt_rdp {
  value = "mstsc.exe /v:${azurerm_public_ip.iag_pip.fqdn}:${local.rdp_port}"
}

output mgmt_rdp_port {
  value = local.rdp_port
}

output mgmt_rdp_vpn {
  value = "mstsc.exe /v:${var.vdc_config["hub_mgmt_address"]}"
}

output devops_org_url {
  value = try("https://dev.azure.com/${var.app_devops["account"]}",null)
}

output devops_project {
  value = var.app_devops["team_project"]
}

output dashboard_id {
  value = azurerm_dashboard.vdc_dashboard.id
}

output iaas_app_resource_group {
  value       = module.iis_app.app_resource_group
}

output iaas_app_url {
  value       = local.iaas_app_url
} 

output iaas_app_web_lb_address {
  value       = var.vdc_config["iaas_spoke_app_web_lb_address"]
}

output iag_private_ip {
  value       = azurerm_firewall.iag.ip_configuration.0.private_ip_address
}
output iag_public_ip {
  value       = azurerm_public_ip.iag_pip.ip_address
}

output iag_fqdn {
  value       = azurerm_public_ip.iag_pip.fqdn
}

output iag_name {
  value       = azurerm_firewall.iag.name
}

output iag_nat_rules {
  value       = azurerm_firewall_nat_rule_collection.iag_nat_rules.name
}

output location {
  value       = var.location
}

output network_watcher_resource_group {
  value       = local.network_watcher_resource_group
}

output network_watcher_name {
  value       = local.network_watcher_name
}

output paas_app_eventhub_namespace {
  value       = module.paas_app.eventhub_namespace
}

output paas_app_eventhub_namespace_key {
  sensitive   = true
  value       = module.paas_app.eventhub_namespace_key
}

output paas_app_eventhub_namespace_connection_string {
  sensitive   = true
  value       = module.paas_app.eventhub_namespace_connection_string
}

output paas_app_eventhub_namespace_fqdn {
  value       = module.paas_app.eventhub_namespace_fqdn
}

output paas_app_eventhub_name {
  value       = module.paas_app.eventhub_name
}

output paas_app_service_fqdn {
  value       = module.paas_app.app_service_fqdn
}

output paas_app_service_outbound_ip_addresses {
  value       = module.paas_app.app_service_outbound_ip_addresses
}

output paas_app_service_msi_client_id {
  value       = module.paas_app.app_service_msi_client_id
}
output paas_app_service_msi_name {
  value       = module.paas_app.app_service_msi_name
}
output paas_app_service_msi_object_id {
  value       = module.paas_app.app_service_msi_object_id
}

output paas_app_service_name {
  value       = module.paas_app.app_service_name
}

output paas_app_sql_database {
  value       = module.paas_app.sql_database
}

output paas_app_sql_server {
  value       = module.paas_app.sql_server
}

output paas_app_sql_server_endpoint_id {
  value       = module.paas_app.sql_server_endpoint_id
}

output paas_app_sql_server_endpoint_fqdn {
  value       = azurerm_private_dns_a_record.sql_server_dns_record.fqdn
}

output paas_app_sql_server_fqdn {
  value       = module.paas_app.sql_server_fqdn
}

output paas_app_sql_server_id {
  value       = module.paas_app.sql_server_id
}

output paas_app_storage_account_name {
  value       = module.paas_app.storage_account_name
}

output paas_app_resource_group {
  value       = module.paas_app.app_resource_group
}

output paas_app_resource_group_short {
  value       = local.paas_app_resource_group_short
}

output paas_app_internal_url {
    value = "http://${module.paas_app.app_service_fqdn}/"
}

output paas_app_url {
  value       = local.paas_app_url
} 

output paas_vnet_name {
    value     = module.paas_spoke_vnet.spoke_virtual_network_name
}

output release_web_url {
  value       = var.release_web_url
}

output resource_group_ids {
  value       = [
                azurerm_resource_group.vdc_rg.id,
                module.iis_app.app_resource_group_id,
                module.paas_app.resource_group_id
  ]
}

output resource_prefix {
  value       = var.resource_prefix
}
output resource_environment {
  value       = local.environment
}
output resource_suffix {
  value       = local.suffix
}

output shared_resources_group {
  value       = var.shared_resources_group
}

output vdc_resource_group {
  value       = azurerm_resource_group.vdc_rg.name
}

output virtual_machine_ids {
  value       = local.virtual_machine_ids
}

output virtual_machine_ids_string {
  value       = local.virtual_machine_ids_string
}
