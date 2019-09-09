output "arm_resource_ids" {
  value       = [
    # Managed Bastion
    "${azurerm_template_deployment.managed_bastion.0.outputs["resourceGroupId"]}/providers/Microsoft.Network/bastionHosts/${local.managed_bastion_name}",
  ]
}

output spoke_virtual_network_id {
  value                        = "${azurerm_virtual_network.spoke_vnet.id}"
}

output subnet_ids {
  value                        = "${zipmap(azurerm_subnet.subnet.*.name, azurerm_subnet.subnet.*.id)}"
# value                        = "${local.subnet_id_map}"
}