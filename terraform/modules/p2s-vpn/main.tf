data "azurerm_client_config" "current" {}

locals {
  tenant_url                   = "https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/"
  issuer_url                   = "https://sts.windows.net/${data.azurerm_client_config.current.tenant_id}/"
  resource_group_name          = element(split("/",var.resource_group_id),length(split("/",var.resource_group_id))-1)
  virtual_network_name         = element(split("/",var.virtual_network_id),length(split("/",var.virtual_network_id))-1)
}

resource "azurerm_subnet" "vpn_subnet" {
  name                         = "GatewaySubnet"
  resource_group_name          = local.resource_group_name
  virtual_network_name         = local.virtual_network_name
  address_prefix               = var.subnet_range
}

resource "random_string" "vpn_domain_name_label" {
  length                       = 16
  upper                        = false
  lower                        = true
  number                       = false
  special                      = false
}

resource "azurerm_public_ip" "vpn_pip" {
  name                         = "${local.resource_group_name}-vpn-pip"
  location                     = var.location
  resource_group_name          = local.resource_group_name

  allocation_method            = "Static"
  sku                          = "Standard" # Zone redundant
  domain_name_label            = random_string.vpn_domain_name_label.result

  tags                         = var.tags
}

resource azurerm_virtual_network_gateway vpn_gw {
  name                         = "${local.resource_group_name}-vpn"
  resource_group_name          = local.resource_group_name
  location                     = var.location

  type                         = "Vpn"
  vpn_type                     = "RouteBased"

  active_active                = false
  enable_bgp                   = false
  sku                          = "VpnGw1AZ"

  ip_configuration {
    name                       = "vnetGatewayConfig"
    public_ip_address_id       = azurerm_public_ip.vpn_pip.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                  = azurerm_subnet.vpn_subnet.id
  }

  vpn_client_configuration {
    address_space              = [var.vpn_range]
    # root_certificate {
    #   name                     = var.vpn_root_cert_name
    #   public_cert_data         = filebase64(var.vpn_root_cert_file) # load cert from file
    # }
    vpn_client_protocols       = ["OpenVPN"]
  }

  timeouts {
    create                     = var.default_create_timeout
    update                     = var.default_update_timeout
    read                       = var.default_read_timeout
    delete                     = var.default_delete_timeout
  }  

  count                        = var.deploy_vpn ? 1 : 0
  tags                         = var.tags
}

resource null_resource vpn_aad {
  # Enable AAD auth
  provisioner local-exec {
    # tenant and issuer are the same url
    command                    = "az network vnet-gateway aad assign --gateway-name ${azurerm_virtual_network_gateway.vpn_gw.0.name} -g ${azurerm_virtual_network_gateway.vpn_gw.0.resource_group_name} --audience 41b23e61-6c1e-4545-b367-cd054e0ed4b4 --issuer '${local.issuer_url}' --tenant '${local.tenant_url}' --query 'vpnClientConfiguration'"
  }

  count                        = var.deploy_vpn ? 1 : 0
}

resource "azurerm_monitor_diagnostic_setting" "vpn_logs" {
  name                         = "${azurerm_virtual_network_gateway.vpn_gw.0.name}-logs"
  target_resource_id           = azurerm_virtual_network_gateway.vpn_gw.0.id
  storage_account_id           = var.diagnostics_storage_id
  log_analytics_workspace_id   = var.diagnostics_workspace_resource_id

  log {
    category                   = "GatewayDiagnosticLog"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }

  log {
    category                   = "TunnelDiagnosticLog"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }

  log {
    category                   = "RouteDiagnosticLog"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }

  log {
    category                   = "IKEDiagnosticLog"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }

  log {
    category                   = "P2SDiagnosticLog"
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

  count                        = var.deploy_vpn ? 1 : 0
}
