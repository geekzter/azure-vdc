output "admin_user" {
  sensitive   = false
  description = "VDC Admin username"
  value       = "${var.admin_username}"
}
output "admin_password" {
  sensitive   = true
  description = "VDC Admin password"
  value       = "${local.password}"
}

output "app_storage_fqdns" {
  value       = [
    "${azurerm_firewall_application_rule_collection.iag_app_rules.rule.0.target_fqdns}"
    ]
}

# Export Resource ID's of resources created in embedded ARM templates
# This can be used in script to manage (e.g. clean up) these resources as Terraform doesn't know about them
output "arm_resource_ids" {
  value       = []
}

output "bastion_address" {
  value       = "${var.vdc_config["hub_bastion_address"]}"
}

output "bastion_firstlogoncommand" {
  value                  = templatefile("../Scripts/FirstLogonCommands.xml", { 
    username               = var.admin_username, 
    password               = local.password, 
    host1                  = element(var.app_web_vms, 0), 
    host2                  = element(var.app_web_vms, 1),
    scripturl              = azurerm_storage_blob.bastion_prepare_script.url,
    sqlserver              = module.paas_app.sql_server_fqdn
  })
}

output "bastion_name" {
  value = "${azurerm_virtual_machine.bastion.name}"
}

output "bastion_rdp" {
  value = "mstsc.exe /v:${azurerm_public_ip.iag_pip.ip_address}:${var.rdp_port}"
}

output "bastion_rdp_port" {
  value = "${var.rdp_port}"
}

output "bastion_rdp_vpn" {
  value = "mstsc.exe /v:${var.vdc_config["hub_bastion_address"]}"
}

output "iaas_app_resource_group" {
  value       = "${local.iaas_app_resource_group}"
}

output "iaas_app_url" {
  value       = "${local.iaas_app_url}"
} 

output "iaas_app_web_lb_address" {
  value       = "${var.vdc_config["iaas_spoke_app_web_lb_address"]}"
}

output "iag_private_ip" {
  value       = "${azurerm_firewall.iag.ip_configuration.0.private_ip_address}"
}
output "iag_public_ip" {
  value       = "${azurerm_public_ip.iag_pip.ip_address}"
}

output "iag_fqdn" {
  value       = "${azurerm_public_ip.iag_pip.fqdn}"
}

output "iag_name" {
  value       = "${azurerm_firewall.iag.name}"
}

output "iag_nat_rules" {
  value       = "${azurerm_firewall_nat_rule_collection.iag_nat_rules.name}"
}

output "location" {
  value       = "${var.location}"
}

output "paas_app_eventhub_namespace" {
  value       = "${module.paas_app.eventhub_namespace}"
}

output "paas_app_eventhub_namespace_key" {
  sensitive   = true
  value       = "${module.paas_app.eventhub_namespace_key}"
}

output "paas_app_eventhub_namespace_connection_string" {
  sensitive   = true
  value       = "${module.paas_app.eventhub_namespace_connection_string}"
}

output "paas_app_eventhub_namespace_fqdn" {
  value       = "${module.paas_app.eventhub_namespace_fqdn}"
}

output "paas_app_eventhub_name" {
  value       = "${module.paas_app.eventhub_name}"
}

output paas_app_service_fqdn {
    value = "${module.paas_app.app_service_fqdn}"
}

# output paas_app_service_msi_application_id1 {
#     value = "${module.paas_app.app_service_msi_application_id1}"
# }
# output paas_app_service_msi_application_id2 {
#     value = "${module.paas_app.app_service_msi_application_id2}"
# }
output paas_app_service_msi_object_id {
    value = "${module.paas_app.app_service_msi_object_id}"
}

output paas_app_service_name {
    value = "${module.paas_app.app_service_name}"
}

output "paas_app_sql_database" {
  value       = "${module.paas_app.sql_database}"
}

output "paas_app_sql_server" {
  value       = "${module.paas_app.sql_server}"
}

output "paas_app_sql_server_fqdn" {
  value       = "${module.paas_app.sql_server_fqdn}"
}

output "paas_app_sql_server_id" {
  value       = "${module.paas_app.sql_server_id}"
}

output "paas_app_storage_account_name" {
  value       = "${module.paas_app.storage_account_name}"
}

output "paas_app_resource_group" {
  value       = "${local.paas_app_resource_group}"
}

output paas_app_internal_url {
    value = "http://${module.paas_app.app_service_fqdn}/"
}

output "paas_app_url" {
  value       = "${local.paas_app_url}"
} 

output paas_vnet_guid {
    value     = "${module.paas_app.spoke_vnet_guid}"
}

output paas_vnet_name {
    value     = "${module.paas_spoke_vnet.spoke_virtual_network_name}"
}

output resource_group_ids {
  value       = [
                "${azurerm_resource_group.vdc_rg.id}",
                "${module.iis_app.app_resource_group_id}",
                "${module.paas_app.resource_group_id}"
  ]
}

output resource_prefix {
  value       = "${var.resource_prefix}"
}
output resource_environment {
  value       = "${local.environment}"
}
output resource_suffix {
  value       = "${local.suffix}"
}

output "vdc_resource_group" {
  value       = "${azurerm_resource_group.vdc_rg.name}"
}
