resource "azurerm_subnet" "vpn_subnet" {
  name                         = "GatewaySubnet"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  virtual_network_name         = "${azurerm_virtual_network.vnet.name}"
  address_prefix               = "${var.vdc_vnet["vpn_subnet"]}"
}

resource "azurerm_public_ip" "vpn_pip" {
  name                         = "${local.vdc_resource_group}-vpn-pip"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"

  allocation_method            = "Dynamic"
}

resource "azurerm_virtual_network_gateway" "vpn_gw" {
  name                         = "${local.vdc_resource_group}-vpn"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  location                     = "${azurerm_resource_group.vdc_rg.location}"

  type                         = "Vpn"
  vpn_type                     = "RouteBased"

  active_active                = false
  enable_bgp                   = false
  sku                          = "VpnGw1"

  ip_configuration {
    name                       = "vnetGatewayConfig"
    public_ip_address_id       = "${azurerm_public_ip.vpn_pip.id}"
    private_ip_address_allocation = "Dynamic"
    subnet_id                  = "${azurerm_subnet.vpn_subnet.id}"
  }


  vpn_client_configuration {
    address_space              = ["${var.vdc_vnet["vpn_range"]}"]

    root_certificate {
      name                     = "${var.vpn_root_cert_name}"

      public_cert_data         = "${base64encode(file(var.vpn_root_cert_file))}" # load cert from file
    }

  }
}