# ******************* NSG's ******************* #
resource "azurerm_network_security_group" "mgmt_nsg" {
  name                        = "${azurerm_resource_group.vdc_rg.name}-mgmt-nsg"
  location                    = azurerm_resource_group.vdc_rg.location
  resource_group_name         = azurerm_resource_group.vdc_rg.name

  security_rule {
    name                      = "AllowAllTCPfromVPN"
    priority                  = 104
    direction                 = "Inbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "*"
    source_address_prefix     = var.vdc_config["vpn_range"]
    destination_address_prefix= var.vdc_config["hub_mgmt_subnet"]
  }
  
  security_rule {
    name                      = "AllowRDPOutbound"
    priority                  = 105
    direction                 = "Outbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "3389"
    source_address_prefix     = var.vdc_config["hub_mgmt_subnet"]
    destination_address_prefix= "VirtualNetwork"
  }

  security_rule {
    name                      = "AllowSSHOutbound"
    priority                  = 106
    direction                 = "Outbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "22"
    source_address_prefix     = var.vdc_config["hub_mgmt_subnet"]
    destination_address_prefix= "VirtualNetwork"
  }
}

resource azurerm_network_watcher_flow_log mgmt_nsg {
  network_watcher_name         = local.network_watcher_name
  resource_group_name          = local.network_watcher_resource_group

  network_security_group_id    = azurerm_network_security_group.mgmt_nsg.id
  storage_account_id           = azurerm_storage_account.vdc_diag_storage.id
  enabled                      = true

  retention_policy {
    enabled                    = true
    days                       = 7
  }

  traffic_analytics {
    enabled                    = true
    workspace_id               = azurerm_log_analytics_workspace.vcd_workspace.workspace_id
    workspace_region           = local.workspace_location
    workspace_resource_id      = azurerm_log_analytics_workspace.vcd_workspace.id
  }

  count                        = var.deploy_network_watcher ? 1 : 0
}

# ******************* Routing ******************* #
resource "azurerm_route_table" "mgmt_route_table" {
  name                        = "${azurerm_resource_group.vdc_rg.name}-mgmt-routes"
  location                    = azurerm_resource_group.vdc_rg.location
  resource_group_name         = azurerm_resource_group.vdc_rg.name

  route {
    name                      = "InternetViaIAG"
    address_prefix            = "0.0.0.0/0"
    next_hop_type             = "VirtualAppliance"
    next_hop_in_ip_address    = azurerm_firewall.iag.ip_configuration.0.private_ip_address
  }
}
# ******************* VNET ******************* #
resource "azurerm_virtual_network" "hub_vnet" {
  name                        = "${azurerm_resource_group.vdc_rg.name}-hub-network"
  location                    = var.location
  address_space               = [var.vdc_config["hub_range"]]
  resource_group_name         = azurerm_resource_group.vdc_rg.name
}

resource "azurerm_subnet" "iag_subnet" {
  name                        = "AzureFirewallSubnet"
  virtual_network_name        = azurerm_virtual_network.hub_vnet.name
  resource_group_name         = azurerm_resource_group.vdc_rg.name
  address_prefix              = var.vdc_config["hub_iag_subnet"]
  service_endpoints           = [
                                "Microsoft.EventHub",
                                "Microsoft.Sql",
                                "Microsoft.Storage"
  ]
}

resource "azurerm_subnet" "waf_subnet" {
  name                        = "WAFSubnet1"
  virtual_network_name        = azurerm_virtual_network.hub_vnet.name
  resource_group_name         = azurerm_resource_group.vdc_rg.name
  address_prefix              = var.vdc_config["hub_waf_subnet"]
  service_endpoints           = [
                                "Microsoft.Web"
  ]
}

resource "azurerm_subnet" "mgmt_subnet" {
  name                         = "Management"
  virtual_network_name         = azurerm_virtual_network.hub_vnet.name
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  address_prefix               = var.vdc_config["hub_mgmt_subnet"]
  network_security_group_id    = azurerm_network_security_group.mgmt_nsg.id # Redundant bit still needed
  route_table_id              = azurerm_route_table.mgmt_route_table.id # Redundant bit still needed

  service_endpoints            = [
                                 "Microsoft.Web"
  ]
}

resource "azurerm_subnet_route_table_association" "mgmt_subnet_routes" {
  subnet_id                   = azurerm_subnet.mgmt_subnet.id
  route_table_id              = azurerm_route_table.mgmt_route_table.id

  depends_on                   = [azurerm_firewall.iag]
}

resource "azurerm_subnet_network_security_group_association" "mgmt_subnet_nsg" {
  subnet_id                    = azurerm_subnet.mgmt_subnet.id
  network_security_group_id    = azurerm_network_security_group.mgmt_nsg.id

  depends_on                   = [azurerm_subnet_route_table_association.mgmt_subnet_routes,
                                  azurerm_firewall_application_rule_collection.iag_app_rules,
                                  azurerm_firewall_network_rule_collection.iag_net_outbound_rules
  ]
}

resource "azurerm_private_dns_zone" "zone" {
  for_each                     = {
    sqldb                      = "privatelink.database.windows.net"
    blob                       = "privatelink.blob.core.windows.net"
  }
  name                         = each.value
  resource_group_name          = azurerm_resource_group.vdc_rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "link" {
  for_each                     = azurerm_private_dns_zone.zone
  name                         = "${azurerm_virtual_network.hub_vnet.name}-dns-${each.key}"
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  private_dns_zone_name        = each.value.name
  virtual_network_id           = azurerm_virtual_network.hub_vnet.id
}
