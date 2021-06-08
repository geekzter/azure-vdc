locals {
  hub_virtual_network_name     = element(split("/",var.hub_virtual_network_id),length(split("/",var.hub_virtual_network_id))-1)
  managed_bastion_name         = "${azurerm_virtual_network.spoke_vnet.name}-managed-bastion"
  subnet_id_map                = zipmap(azurerm_subnet.subnet.*.name, azurerm_subnet.subnet.*.id)
  resource_group_name          = element(split("/",var.resource_group_id),length(split("/",var.resource_group_id))-1)
}

resource azurerm_virtual_network spoke_vnet {
  name                         = var.spoke_virtual_network_name
  resource_group_name          = local.resource_group_name
  location                     = var.location
  address_space                = [var.address_space]
  dns_servers                  = var.dns_servers

  tags                         = var.tags
}

resource azurerm_monitor_diagnostic_setting vnet_logs {
  name                         = "${azurerm_virtual_network.spoke_vnet.name}-logs"
  target_resource_id           = azurerm_virtual_network.spoke_vnet.id
  storage_account_id           = var.diagnostics_storage_id
  log_analytics_workspace_id   = var.diagnostics_workspace_resource_id

  log {
    category                   = "VMProtectionAlerts"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }

  metric {
    category                   = "AllMetrics"

    retention_policy {
      enabled                  = false
    }
  }
}

# https://docs.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-peering-gateway-transit#resource-manager-to-resource-manager-peering-with-gateway-transit
resource azurerm_virtual_network_peering spoke_to_hub {
  name                         = "${azurerm_virtual_network.spoke_vnet.name}-spoke2hub"
  resource_group_name          = local.resource_group_name
  virtual_network_name         = azurerm_virtual_network.spoke_vnet.name
  remote_virtual_network_id    = var.hub_virtual_network_id

  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  allow_virtual_network_access = true
  use_remote_gateways          = var.use_hub_gateway

  depends_on                   = [azurerm_virtual_network_peering.hub_to_spoke]
}

resource azurerm_virtual_network_peering hub_to_spoke {
  name                         = "${azurerm_virtual_network.spoke_vnet.name}-hub2spoke"
  resource_group_name          = local.resource_group_name
  virtual_network_name         = local.hub_virtual_network_name
  remote_virtual_network_id    = azurerm_virtual_network.spoke_vnet.id

  allow_forwarded_traffic      = true
  allow_gateway_transit        = var.use_hub_gateway
  allow_virtual_network_access = true
  use_remote_gateways          = false
}

resource azurerm_route_table spoke_route_table {
  name                         = "${azurerm_virtual_network.spoke_vnet.name}-routes"
  resource_group_name          = local.resource_group_name
  location                     = var.location

  route {
    name                       = "VnetLocal"
    address_prefix             = var.address_space
    next_hop_type              = "VnetLocal"
  }

  route {
    name                       = "AllViaHub"
    address_prefix             = "0.0.0.0/0"
    next_hop_type              = "VirtualAppliance"
    next_hop_in_ip_address     = var.gateway_ip_address
  }

  tags                         = var.tags
}

resource azurerm_network_security_group spoke_nsg {
  name                         = "${azurerm_virtual_network.spoke_vnet.name}-nsg"
  resource_group_name          = local.resource_group_name
  location                     = var.location

  security_rule {
    name                       = "AllowAllfromVDC"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowAllfromRFC1918A"
    priority                   = 103
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "10.0.0.0/8"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowAllfromRFC1918B"
    priority                   = 104
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "192.168.0.0/16"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowAllfromRFC1918C"
    priority                   = 105
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "172.16.0.0/12"
    destination_address_prefix = "VirtualNetwork"
  }

  # security_rule {
  #   name                       = "DenyAllfromInternet"
  #   priority                   = 190
  #   direction                  = "Inbound"
  #   access                     = "Deny"
  #   protocol                   = "*"
  #   source_port_range          = "*"
  #   destination_port_range     = "*"
  #   source_address_prefix      = "Internet"
  #   destination_address_prefix = "VirtualNetwork"
  # }

  security_rule {
    name                       = "AllowAlltoVDC"
    priority                   = 201
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowAlltoRFC1918A"
    priority                   = 203
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "10.0.0.0/8"
  }

  security_rule {
    name                       = "AllowAlltoRFC1918B"
    priority                   = 204
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "192.168.0.0/16"
  }

  security_rule {
    name                       = "AllowAlltoRFC1918C"
    priority                   = 205
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "172.16.0.0/12"
  }

  security_rule {
    name                       = "AllowAlltoInternet"
    priority                   = 290
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "0-65535"
    destination_port_range     = "0-65535"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Internet"
  }

  tags                         = var.tags
}

resource azurerm_network_watcher_flow_log spoke_nsg {
  network_watcher_name         = var.network_watcher_name
  resource_group_name          = var.network_watcher_resource_group_name

  network_security_group_id    = azurerm_network_security_group.spoke_nsg.id
  storage_account_id           = var.diagnostics_storage_id
  enabled                      = true
  version                      = 2

  retention_policy {
    enabled                    = true
    days                       = 7
  }

  traffic_analytics {
    enabled                    = true
    workspace_id               = var.diagnostics_workspace_workspace_id
    workspace_region           = var.workspace_location
    workspace_resource_id      = var.diagnostics_workspace_resource_id
  }

  count                        = var.deploy_network_watcher ? 1 : 0
}

resource azurerm_subnet subnet {
  name                         = element(keys(var.subnets),count.index)
  virtual_network_name         = azurerm_virtual_network.spoke_vnet.name
  resource_group_name          = local.resource_group_name
  address_prefixes             = [element(values(var.subnets),count.index)]
  enforce_private_link_endpoint_network_policies = true
  count                        = length(var.subnets)
  
  # Create subnet delegation, if requested
  dynamic "delegation" {
    # Select the delegation for this subnet, if any
    for_each                   = {for k, v in var.subnet_delegations : k => v if k == element(keys(var.subnets),count.index)}
    content {
      name                     = "${delegation.key}_delegation"
      service_delegation {
        name                   = delegation.value
      }
    }
  }

  # Find list of service endpoints defined for subnet we're iterating over, use empty list if none defined
  service_endpoints            = lookup(var.service_endpoints,element(keys(var.subnets),count.index),null)

  timeouts {
    create                     = var.default_create_timeout
    update                     = var.default_update_timeout
    read                       = var.default_read_timeout
    delete                     = var.default_delete_timeout
  }  
}

resource azurerm_subnet_route_table_association subnet_routes {
  subnet_id                    = local.subnet_id_map[element(var.enable_routetable_for_subnets,count.index)]
  route_table_id               = azurerm_route_table.spoke_route_table.id
  count                        = length(var.enable_routetable_for_subnets)

  timeouts {
    create                     = var.default_create_timeout
    update                     = var.default_update_timeout
    read                       = var.default_read_timeout
    delete                     = var.default_delete_timeout
  }  

  depends_on                   = [azurerm_virtual_network_peering.spoke_to_hub]
}

resource azurerm_subnet_network_security_group_association subnet_nsg {
  subnet_id                    = element(azurerm_subnet.subnet.*.id,count.index)
  network_security_group_id    = azurerm_network_security_group.spoke_nsg.id
  count                        = length(var.subnets)

  timeouts {
    create                     = var.default_create_timeout
    update                     = var.default_update_timeout
    read                       = var.default_read_timeout
    delete                     = var.default_delete_timeout
  }  

  depends_on                   = [azurerm_virtual_network_peering.spoke_to_hub]
}

resource azurerm_monitor_diagnostic_setting nsg_logs {
  name                         = "${azurerm_network_security_group.spoke_nsg.name}-logs"
  target_resource_id           = azurerm_network_security_group.spoke_nsg.id
  storage_account_id           = var.diagnostics_storage_id
  log_analytics_workspace_id   = var.diagnostics_workspace_resource_id

  log {
    category                   = "NetworkSecurityGroupEvent"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }

  log {
    category                   = "NetworkSecurityGroupRuleCounter"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }
}

resource azurerm_private_dns_zone_virtual_network_link spoke_link {
  name                         = "${azurerm_virtual_network.spoke_vnet.name}-zone-link${count.index+1}"
  resource_group_name          = local.resource_group_name
  private_dns_zone_name        = element(var.private_dns_zones,count.index)
  virtual_network_id           = azurerm_virtual_network.spoke_vnet.id

  tags                         = var.tags
  count                        = length(var.private_dns_zones)
}