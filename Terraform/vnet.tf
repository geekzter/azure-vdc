# ******************* NSG's ******************* #
resource "azurerm_network_security_group" "app_nsg" {
  name                        = "${azurerm_resource_group.vdc_rg.name}-app-nsg"
  location                    = "${azurerm_resource_group.vdc_rg.location}"
  resource_group_name         = "${azurerm_resource_group.vdc_rg.name}"

  security_rule {
    name                      = "AllowRDPfromManagement"
    priority                  = 101
    direction                 = "Inbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "3389"
    source_address_prefix     = "${var.vdc_vnet["mgmt_subnet"]}"
    destination_address_prefix= "${var.vdc_vnet["app_subnet"]}"
  }

  security_rule {
    name                      = "AllowSSHfromManagement"
    priority                  = 102
    direction                 = "Inbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "22"
    source_address_prefix     = "${var.vdc_vnet["mgmt_subnet"]}"
    destination_address_prefix= "${var.vdc_vnet["app_subnet"]}"
  }

  security_rule {
    name                      = "AllowAllTCPfromVPN"
    priority                  = 103
    direction                 = "Inbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "*"
    source_address_prefix     = "${var.vdc_vnet["vpn_range"]}"
    destination_address_prefix= "${var.vdc_vnet["app_subnet"]}"
  }

  # Via Azure Firewall
  # security_rule {
  #   name                      = "AllowHTTPtoInternet"
  #   priority                  = 104
  #   direction                 = "Outbound"
  #   access                    = "Allow"
  #   protocol                  = "Tcp"
  #   source_port_range         = "*"
  #   destination_port_range    = "80"
  #   source_address_prefix     = "${var.vdc_vnet["app_subnet"]}"
  #   destination_address_prefix= "Internet"
  # }

  # Via Azure Firewall
  # security_rule {
  #   name                      = "AllowHTTPStoInternet"
  #   priority                  = 105
  #   direction                 = "Outbound"
  #   access                    = "Allow"
  #   protocol                  = "Tcp"
  #   source_port_range         = "*"
  #   destination_port_range    = "443"
  #   source_address_prefix     = "${var.vdc_vnet["app_subnet"]}"
  #   destination_address_prefix= "Internet"
  # }

  security_rule {
    name                      = "AllowMSSQLtoData"
    priority                  = 106
    direction                 = "Outbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "1443"
    source_address_prefix     = "${var.vdc_vnet["app_subnet"]}"
    destination_address_prefix= "${var.vdc_vnet["data_subnet"]}"
  }

  security_rule {
    name                      = "AllowORAtoData"
    priority                  = 107
    direction                 = "Outbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "1523"
    source_address_prefix     = "${var.vdc_vnet["app_subnet"]}"
    destination_address_prefix= "${var.vdc_vnet["data_subnet"]}"
  }
}

resource "azurerm_network_security_group" "data_nsg" {
  name                        = "${azurerm_resource_group.vdc_rg.name}-data-nsg"
  location                    = "${azurerm_resource_group.vdc_rg.location}"
  resource_group_name         = "${azurerm_resource_group.vdc_rg.name}"

  security_rule {
    name                      = "AllowRDPfromManagement"
    priority                  = 101
    direction                 = "Inbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "3389"
    source_address_prefix     = "${var.vdc_vnet["mgmt_subnet"]}"
    destination_address_prefix= "${var.vdc_vnet["data_subnet"]}"
  }

  security_rule {
    name                      = "AllowSSHfromManagement"
    priority                  = 102
    direction                 = "Inbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "22"
    source_address_prefix     = "${var.vdc_vnet["mgmt_subnet"]}"
    destination_address_prefix= "${var.vdc_vnet["data_subnet"]}"
  }

   security_rule {
    name                      = "AllowAllTCPfromVPN"
    priority                  = 103
    direction                 = "Inbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "*"
    source_address_prefix     = "${var.vdc_vnet["vpn_range"]}"
    destination_address_prefix= "${var.vdc_vnet["data_subnet"]}"
  }

  security_rule {
    name                      = "AllowMSSQLfromApp"
    priority                  = 104
    direction                 = "Inbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "1433"
    source_address_prefix     = "${var.vdc_vnet["app_subnet"]}"
    destination_address_prefix= "${var.vdc_vnet["data_subnet"]}"
  }

  security_rule {
    name                      = "AllowORAfromApp"
    priority                  = 105
    direction                 = "Inbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "1523"
    source_address_prefix     = "${var.vdc_vnet["app_subnet"]}"
    destination_address_prefix= "${var.vdc_vnet["data_subnet"]}"
  }
}

resource "azurerm_network_security_group" "mgmt_nsg" {
  name                        = "${azurerm_resource_group.vdc_rg.name}-mgmt-nsg"
  location                    = "${azurerm_resource_group.vdc_rg.location}"
  resource_group_name         = "${azurerm_resource_group.vdc_rg.name}"

  security_rule {
    name                      = "AllowAllTCPfromVPN"
    priority                  = 104
    direction                 = "Inbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "*"
    source_address_prefix     = "${var.vdc_vnet["vpn_range"]}"
    destination_address_prefix= "${var.vdc_vnet["mgmt_subnet"]}"
  }
  
  security_rule {
    name                      = "AllowRDPOutbound"
    priority                  = 105
    direction                 = "Outbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "3389"
    source_address_prefix     = "${var.vdc_vnet["mgmt_subnet"]}"
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
    source_address_prefix     = "${var.vdc_vnet["mgmt_subnet"]}"
    destination_address_prefix= "VirtualNetwork"
  }
}

# ******************* Routing ******************* #
resource "azurerm_route_table" "app_route_table" {
  name                        = "${azurerm_resource_group.vdc_rg.name}-app-routes"
  location                    = "${azurerm_resource_group.vdc_rg.location}"
  resource_group_name         = "${azurerm_resource_group.vdc_rg.name}"

  route {
    name                      = "InternetViaIAG"
    address_prefix            = "0.0.0.0/0"
    next_hop_type             = "VirtualAppliance"
    next_hop_in_ip_address    = "${azurerm_firewall.iag.ip_configuration.0.private_ip_address}"
  }
}

resource "azurerm_route_table" "data_route_table" {
  name                        = "${azurerm_resource_group.vdc_rg.name}-data-routes"
  location                    = "${azurerm_resource_group.vdc_rg.location}"
  resource_group_name         = "${azurerm_resource_group.vdc_rg.name}"

  route {
    name                      = "InternetViaIAG"
    address_prefix            = "0.0.0.0/0"
    next_hop_type             = "VirtualAppliance"
    next_hop_in_ip_address    = "${azurerm_firewall.iag.ip_configuration.0.private_ip_address}"
  }
}

resource "azurerm_route_table" "mgmt_route_table" {
  name                        = "${azurerm_resource_group.vdc_rg.name}-mgmt-routes"
  location                    = "${azurerm_resource_group.vdc_rg.location}"
  resource_group_name         = "${azurerm_resource_group.vdc_rg.name}"

  route {
    name                      = "InternetViaIAG"
    address_prefix            = "0.0.0.0/0"
    next_hop_type             = "VirtualAppliance"
    next_hop_in_ip_address    = "${azurerm_firewall.iag.ip_configuration.0.private_ip_address}"
  }
}
# ******************* VNET ******************* #
resource "azurerm_virtual_network" "hub_vnet" {
  name                        = "${azurerm_resource_group.vdc_rg.name}-network"
  location                    = "${var.location}"
  address_space               = ["${var.vdc_vnet["vdc_range"]}"]
  resource_group_name         = "${azurerm_resource_group.vdc_rg.name}"
}

resource "azurerm_subnet" "iag_subnet" {
  name                        = "AzureFirewallSubnet"
  virtual_network_name        = "${azurerm_virtual_network.hub_vnet.name}"
  resource_group_name         = "${azurerm_resource_group.vdc_rg.name}"
  address_prefix              = "${var.vdc_vnet["iag_subnet"]}"
  service_endpoints           = [
                                "Microsoft.EventHub", 
                                "Microsoft.Storage"
  ]
}

resource "azurerm_subnet" "waf_subnet" {
  name                        = "WAFSubnet1"
  virtual_network_name        = "${azurerm_virtual_network.hub_vnet.name}"
  resource_group_name         = "${azurerm_resource_group.vdc_rg.name}"
  address_prefix              = "${var.vdc_vnet["waf_subnet"]}"
}

resource "azurerm_subnet" "app_subnet" {
  name                        = "Application"
  virtual_network_name        = "${azurerm_virtual_network.hub_vnet.name}"
  resource_group_name         = "${azurerm_resource_group.vdc_rg.name}"
  address_prefix              = "${var.vdc_vnet["app_subnet"]}"
}

resource "azurerm_subnet_route_table_association" "app_subnet_routes" {
  subnet_id                   = "${azurerm_subnet.app_subnet.id}"
  route_table_id              = "${azurerm_route_table.app_route_table.id}"
}

resource "azurerm_subnet_network_security_group_association" "app_subnet_nsg" {
  subnet_id                   = "${azurerm_subnet.app_subnet.id}"
  network_security_group_id   = "${azurerm_network_security_group.app_nsg.id}"
}

resource "azurerm_subnet" "data_subnet" {
  name                        = "Data"
  virtual_network_name        = "${azurerm_virtual_network.hub_vnet.name}"
  resource_group_name         = "${azurerm_resource_group.vdc_rg.name}"
  address_prefix              = "${var.vdc_vnet["data_subnet"]}"
}

resource "azurerm_subnet_route_table_association" "data_subnet_routes" {
  subnet_id                   = "${azurerm_subnet.data_subnet.id}"
  route_table_id              = "${azurerm_route_table.data_route_table.id}"
}

resource "azurerm_subnet_network_security_group_association" "data_subnet_nsg" {
  subnet_id                   = "${azurerm_subnet.data_subnet.id}"
  network_security_group_id   = "${azurerm_network_security_group.data_nsg.id}"
}

resource "azurerm_subnet" "mgmt_subnet" {
  name                         = "Management"
  virtual_network_name         = "${azurerm_virtual_network.hub_vnet.name}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  address_prefix               = "${var.vdc_vnet["mgmt_subnet"]}"
}

resource "azurerm_subnet_route_table_association" "mgmt_subnet_routes" {
  subnet_id                   = "${azurerm_subnet.mgmt_subnet.id}"
  route_table_id              = "${azurerm_route_table.mgmt_route_table.id}"
}

resource "azurerm_subnet_network_security_group_association" "mgmt_subnet_nsg" {
  subnet_id                    = "${azurerm_subnet.mgmt_subnet.id}"
  network_security_group_id    = "${azurerm_network_security_group.mgmt_nsg.id}"
}