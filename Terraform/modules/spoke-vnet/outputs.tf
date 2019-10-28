output access_dependencies {
  value                        = concat(azurerm_subnet_route_table_association.subnet_routes.*.id,
                                 [
                                 "${azurerm_virtual_network_peering.spoke_to_hub.id}",
                                 "${azurerm_virtual_network_peering.hub_to_spoke.id}"
  ])
}

output bastion_subnet_id {
  value = "${azurerm_subnet.managed_bastion_subnet.id}"
}

output "arm_resource_ids" {
  value                        = [
    # Managed Bastion
    for b in azurerm_template_deployment.managed_bastion : "${b.outputs["resourceGroupId"]}/providers/Microsoft.Network/bastionHosts/${local.managed_bastion_name}"
  ]
}

output spoke_virtual_network_id {
  value                        = "${azurerm_virtual_network.spoke_vnet.id}"
}

output subnet_ids {
  value                        = "${zipmap(azurerm_subnet.subnet.*.name, azurerm_subnet.subnet.*.id)}"
}
