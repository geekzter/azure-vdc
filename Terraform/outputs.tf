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

output "vdc_resource_group" {
  value       = "${azurerm_resource_group.vdc_rg.name}"
}

output "bastion_address" {
  value       = "${var.vdc_vnet["bastion_address"]}"
}

output "iag_private_ip" {
  value       = "${azurerm_firewall.iag.ip_configuration.0.private_ip_address}"
}
output "iag_public_ip" {
  value       = "${data.azurerm_public_ip.iag_pip_created.ip_address}"
}

output "iag_fqdn" {
  value       = "${data.azurerm_public_ip.iag_pip_created.fqdn}"
}


######### Example App #########
output "app_web_lb_address" {
  value       = "${var.vdc_vnet["app_web_lb_address"]}"
}

output "app_url" {
  value       = "https://${azurerm_dns_cname_record.waf_pip_cname.name}.${azurerm_dns_cname_record.waf_pip_cname.zone_name}/default.aspx"
} 

output "app_storage_fqdns" {
  value       = [
    "${azurerm_firewall_application_rule_collection.iag_app_rules.rule.0.target_fqdns}"
    ]
}
output "app_eventhub_namespace_key" {
  sensitive   = true
  value       = "${azurerm_eventhub_namespace.app_eventhub.default_primary_key}"
}

output "app_eventhub_namespace_connection_string" {
  sensitive   = true
  value       = "${azurerm_eventhub_namespace.app_eventhub.default_primary_connection_string }"
}

output "app_eventhub_namespace_fqdn" {
  value       = "${lower(azurerm_eventhub_namespace.app_eventhub.name)}.servicebus.windows.net"
}

output "app_eventhub_name" {
  value       = "${azurerm_eventhub.app_eventhub.name}"
}

output "app_storage_account_name" {
  value       = "${azurerm_storage_account.app_storage.name}"
}

output "app_resource_group" {
  value       = "${azurerm_resource_group.app_rg.name}"
}

/*
# TDODO
output "vm_fqdn" {
  value = "${azurerm_public_ip.app_web_lbpip.fqdn}"
}
*/

output "bastion_rdp" {
  value = "mstsc.exe /v:${data.azurerm_public_ip.iag_pip_created.ip_address}:${var.rdp_port}"
}

output "bastion_rdp_vpn" {
  value = "mstsc.exe /v:${var.vdc_vnet["bastion_address"]}"
}
