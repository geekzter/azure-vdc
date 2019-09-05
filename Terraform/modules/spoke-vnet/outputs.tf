output spoke_virtual_network_id {
  value                        = "${azurerm_virtual_network.spoke_vnet.id}"
}

output subnet_ids {
  value                        = "${zipmap(keys(var.subnets), azurerm_subnet.subnet.*.id)}"
}