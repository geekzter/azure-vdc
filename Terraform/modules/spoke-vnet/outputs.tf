output spoke_virtual_network_id {
  value                        = "${azurerm_virtual_network.spoke_vnet.id}"
}

output subnet_ids {
  value                        = "${local.subnet_id_map}"
}