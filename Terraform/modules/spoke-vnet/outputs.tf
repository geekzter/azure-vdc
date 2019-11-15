output access_dependencies {
  value                        = concat(azurerm_subnet_route_table_association.subnet_routes.*.id,
                                 [
                                 azurerm_virtual_network_peering.spoke_to_hub.id,
                                 azurerm_virtual_network_peering.hub_to_spoke.id
  ])
}

output bastion_subnet_id {
  value = azurerm_subnet.managed_bastion_subnet.id
}

output spoke_virtual_network_id {
  value                        = azurerm_virtual_network.spoke_vnet.id
}

output spoke_virtual_network_name {
  value                        = azurerm_virtual_network.spoke_vnet.name
}

output subnet_ids {
  value                        = zipmap(azurerm_subnet.subnet.*.name, azurerm_subnet.subnet.*.id)
}
