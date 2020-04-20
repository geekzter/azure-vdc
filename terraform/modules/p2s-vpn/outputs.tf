output gateway_id {
  value       = length(azurerm_virtual_network_gateway.vpn_gw) > 0 ? azurerm_virtual_network_gateway.vpn_gw[0].id : null
}