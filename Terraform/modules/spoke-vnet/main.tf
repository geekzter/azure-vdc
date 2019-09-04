resource "azurerm_virtual_network" "spoke_vnet" {
  name                         = "${var.spoke_virtual_network_name}"
  resource_group_name          = "${var.resource_group}"
  location                     = "${var.location}"
  address_space                = ["${var.address_space}"]
  dns_servers                  = "${var.dns_servers}"

  tags                         = "${var.tags}"
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                         = "${azurerm_virtual_network.spoke_vnet.name}-spoke2hub"
  resource_group_name          = "${var.resource_group}"
  virtual_network_name         = "${azurerm_virtual_network.spoke_vnet.name}"
  remote_virtual_network_id    = "${var.hub_virtual_network_id}"

  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  allow_virtual_network_access = true
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                         = "${azurerm_virtual_network.spoke_vnet.name}-hub2spoke"
  resource_group_name          = "${var.resource_group}"
  virtual_network_name         = "${var.hub_virtual_network_name}"
  remote_virtual_network_id    = "${azurerm_virtual_network.spoke_vnet.id}"

  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  allow_virtual_network_access = true
  use_remote_gateways          = false
}

resource "azurerm_subnet" "subnet" {
  name                         = "${element(keys(var.subnets),count.index)}"
  virtual_network_name         = "${azurerm_virtual_network.spoke_vnet.name}"
  resource_group_name          = "${var.resource_group}"
  address_prefix               = "${element(values(var.subnets),count.index)}"
  count                        = "${length(var.subnets)}"
}

resource "azurerm_monitor_diagnostic_setting" "vnet_logs" {
  name                         = "${azurerm_virtual_network.spoke_vnet.name}-logs"
  target_resource_id           = "${azurerm_virtual_network.spoke_vnet.id}"
  storage_account_id           = "${var.diagnostics_storage_id}"
  log_analytics_workspace_id   = "${var.diagnostics_workspace_id}"

  log {
    category                   = "VMProtectionAlerts"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }
}