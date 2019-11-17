locals {
  managed_bastion_name         = "${local.virtual_network_name}-managed-bastion"
  resource_group_name          = element(split("/",var.resource_group_id),length(split("/",var.resource_group_id))-1)
  virtual_network_name         = element(split("/",var.virtual_network_id),length(split("/",var.virtual_network_id))-1)
}

# This is the tempale for Managed Bastion, IaaS bastion is defined in management.tf
resource "azurerm_subnet" "managed_bastion_subnet" {
  name                         = "AzureBastionSubnet"
  virtual_network_name         = local.virtual_network_name
  resource_group_name          = local.resource_group_name
  address_prefix               = var.subnet_range
}

resource "azurerm_public_ip" "managed_bastion_pip" {
  name                         = "${local.virtual_network_name}-managed-bastion-pip"
  location                     = var.location
  resource_group_name          = local.resource_group_name
  allocation_method            = "Static"
  sku                          = "Standard" # Zone redundant
}

resource "azurerm_bastion_host" "managed_bastion" {
  name                         = "${replace(local.virtual_network_name,"-","")}managedbastion"
  location                     = var.location
  resource_group_name          = local.resource_group_name

  ip_configuration {
    name                       = "configuration"
    subnet_id                  = azurerm_subnet.managed_bastion_subnet.id
    public_ip_address_id       = azurerm_public_ip.managed_bastion_pip.id
  }

  count                        = var.deploy_managed_bastion ? 1 : 0
}

resource "azurerm_monitor_diagnostic_setting" "bastion_logs" {
  name                         = "${azurerm_bastion_host.managed_bastion[count.index].name}-logs"
  target_resource_id           = azurerm_bastion_host.managed_bastion[count.index].id
  storage_account_id           = var.diagnostics_storage_id
  log_analytics_workspace_id   = var.diagnostics_workspace_resource_id

  log {
    category                   = "BastionAuditLogs"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }

  count                        = var.deploy_managed_bastion ? 1 : 0
} 