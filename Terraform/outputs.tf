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
  value       = "${var.vdc_config["hub_bastion_address"]}"
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

######### Example App #########
output "app_web_lb_address" {
  value       = "${var.vdc_config["iaas_spoke_app_web_lb_address"]}"
}

# output "app_url" {
#   value       = "${local.app_url}"
# } 

output "app_storage_fqdns" {
  value       = [
    "${azurerm_firewall_application_rule_collection.iag_app_rules.rule.0.target_fqdns}"
    ]
}
# output "app_eventhub_namespace_key" {
#   sensitive   = true
#   value       = "${module.paas_app.eventhub_namespace_key}"
# }

# output "app_eventhub_namespace_connection_string" {
#   sensitive   = true
#   value       = "${module.paas_app.eventhub_namespace_connection_string}"
# }

# output "app_eventhub_namespace_fqdn" {
#   value       = "${module.paas_app.eventhub_namespace_fqdn}"
# }

# output "app_eventhub_name" {
#   value       = "${module.paas_app.eventhub_name}"
# }

# output "app_storage_account_name" {
#   value       = "${module.paas_app.storage_account_name}"
# }

output "iaas_app_resource_group" {
  value       = "${local.iaas_app_resource_group}"
}

output "paas_app_resource_group" {
  value       = "${local.paas_app_resource_group}"
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

/* output spoke_vnet_guid {
    value     = "${module.paas_app.spoke_vnet_guid}"
}

# Export Resource ID's of resources created in embedded ARM templates
# This can be used in script to manage (e.g. clean up) these resources as Terraform doesn't know about them
output "arm_resource_ids" {
  value       = "${concat(module.managed_bastion_hub.arm_resource_ids,module.iaas_spoke_vnet.arm_resource_ids)}"
}

output resource_group_ids {
  value       = [
                "${azurerm_resource_group.vdc_rg.id}",
                "${module.iis_app.app_resource_group_id}",
                "${module.paas_app.resource_group_id}"
  ]
} */

output resource_prefix {
  value       = "${var.resource_prefix}"
}
output resource_environment {
  value       = "${local.environment}"
}
output resource_suffix {
  value       = "${local.suffix}"
}