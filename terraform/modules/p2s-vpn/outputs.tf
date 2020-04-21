output gateway_id {
  value       = length(azurerm_virtual_network_gateway.vpn_gw) > 0 ? azurerm_virtual_network_gateway.vpn_gw[0].id : null
}

output gateway_fqdn {
  value       = azurerm_public_ip.vpn_pip.fqdn
}

output gateway_ip {
  value       = azurerm_public_ip.vpn_pip.ip_address
}