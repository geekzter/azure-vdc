output gateway_id {
  value       = azurerm_virtual_network_gateway.vpn_gw.id
}

output gateway_fqdn {
  value       = azurerm_public_ip.vpn_pip.fqdn
}

output gateway_ip {
  value       = azurerm_public_ip.vpn_pip.ip_address
}