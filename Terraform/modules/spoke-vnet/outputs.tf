output "arm_resource_ids" {
  value                        = [
    # Managed Bastion
    "${azurerm_template_deployment.managed_bastion.0.outputs["resourceGroupId"]}/providers/Microsoft.Network/bastionHosts/${local.managed_bastion_name}",
  ]
}

output spoke_virtual_network_id {
  value                        = "${azurerm_virtual_network.spoke_vnet.id}"
}

output subnet_ids {
  value                        = "${zipmap(azurerm_subnet.subnet.*.name, azurerm_subnet.subnet.*.id)}"
}

output access_dependencies {
  value                        = concat(azurerm_subnet_route_table_association.subnet_routes.*.id,
                                 [
                                 "${azurerm_virtual_network_peering.spoke_to_hub.id}",
                                 "${azurerm_virtual_network_peering.hub_to_spoke.id}"
  ])
}