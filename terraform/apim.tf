# https://docs.microsoft.com/en-us/azure/api-management/api-management-howto-integrate-internal-vnet-appgateway

locals {
  deploy_api_gateway           = var.deploy_api_gateway && var.use_vanity_domain_and_ssl
}

resource azurerm_subnet apim_subnet {
  name                         = "ApiManagement"
  virtual_network_name         = azurerm_virtual_network.hub_vnet.name
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  address_prefixes             = [var.vdc_config["hub_apim_subnet"]]
  service_endpoints            = [
  # As per https://docs.microsoft.com/en-us/azure/api-management/api-management-using-with-vnet
                                  "Microsoft.EventHub",
                                  "Microsoft.ServiceBus",
                                  "Microsoft.Sql",
                                  "Microsoft.Storage",
  ]

  timeouts {
    create                     = var.default_create_timeout
    update                     = var.default_update_timeout
    read                       = var.default_read_timeout
    delete                     = var.default_delete_timeout
  }  
}
resource azurerm_route_table apim_route_table {
  name                        = "${azurerm_resource_group.vdc_rg.name}-apim-routes"
  location                    = azurerm_resource_group.vdc_rg.location
  resource_group_name         = azurerm_resource_group.vdc_rg.name

  route {
    name                      = "InternetViaIAG"
    address_prefix            = "0.0.0.0/0"
    next_hop_type             = "VirtualAppliance"
    next_hop_in_ip_address    = azurerm_firewall.iag.ip_configuration.0.private_ip_address
  }

  dynamic "route" {
    for_each                   = var.apim_control_plane_ip_addresses
    content  {
      name                     = "ControlPlane${route.value}toInternet"
      address_prefix           = "${route.value}/32"
      next_hop_type            = "Internet"
    }
  }
}

resource azurerm_subnet_route_table_association apim_subnet_routes {
  subnet_id                    = azurerm_subnet.apim_subnet.id
  route_table_id               = azurerm_route_table.apim_route_table.id

  timeouts {
    create                     = var.default_create_timeout
    update                     = var.default_update_timeout
    read                       = var.default_read_timeout
    delete                     = var.default_delete_timeout
  }  

  depends_on                   = [azurerm_firewall.iag]
}
# https://aka.ms/apim-vnet-common-issues
resource azurerm_network_security_group apim_nsg {
  name                        = "${azurerm_resource_group.vdc_rg.name}-apim-nsg"
  location                    = azurerm_resource_group.vdc_rg.location
  resource_group_name         = azurerm_resource_group.vdc_rg.name

  security_rule {
    name                      = "AllowHTTPInbound"
    priority                  = 101
    direction                 = "Inbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "443"
    source_address_prefix     = "Internet"
    destination_address_prefix= "VirtualNetwork"
  }
  # Client communication to API Management
  security_rule {
    name                      = "AllowHTTPSInbound"
    priority                  = 102
    direction                 = "Inbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "443"
    source_address_prefix     = "Internet"
    destination_address_prefix= "VirtualNetwork"
  }
  # Management endpoint
  security_rule {
    name                      = "AllowMgmtInbound"
    priority                  = 103
    direction                 = "Inbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "3443"
    source_address_prefix     = "ApiManagement"
    destination_address_prefix= "VirtualNetwork"
  }
  # Access Redis Service for Cache policies between machines
  security_rule {
    name                      = "AllowRedisCacheInbound"
    priority                  = 104
    direction                 = "Inbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "6381-6383"
    source_address_prefix     = "VirtualNetwork"
    destination_address_prefix= "VirtualNetwork"
  }
  # Sync Counters for Rate Limit policies between machines
  security_rule {
    name                      = "AllowSyncCountersInbound"
    priority                  = 105
    direction                 = "Inbound"
    access                    = "Allow"
    protocol                  = "Udp"
    source_port_range         = "*"
    destination_port_range    = "4290"
    source_address_prefix     = "VirtualNetwork"
    destination_address_prefix= "VirtualNetwork"
  }
  # Azure Infrastructure Load Balancer
  security_rule {
    name                      = "AllowLoadBalancerInbound"
    priority                  = 106
    direction                 = "Inbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "*"
    source_address_prefix     = "AzureLoadBalancer"
    destination_address_prefix= "VirtualNetwork"
  }
  # Debug
  security_rule {
    name                      = "AllowALLInbound"
    priority                  = 199
    direction                 = "Inbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "*"
    source_address_prefix     = "*"
    destination_address_prefix= "*"
  }

  # Dependency on Azure Storage
  security_rule {
    name                      = "AllowStorageHTTPOutbound"
    priority                  = 200
    direction                 = "Outbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "443"
    source_address_prefix     = "VirtualNetwork"
    destination_address_prefix= "Storage"
  }
  # Dependency on Azure File Share for GIT
  security_rule {
    name                      = "AllowStorageIFSOutbound"
    priority                  = 201
    direction                 = "Outbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "445"
    source_address_prefix     = "VirtualNetwork"
    destination_address_prefix= "Storage"
  }
  security_rule {
    name                      = "AllowAADOutbound"
    priority                  = 202
    direction                 = "Outbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "443"
    source_address_prefix     = "VirtualNetwork"
    destination_address_prefix= "AzureActiveDirectory"
  }
  # Access to Azure SQL endpoints
  security_rule {
    name                      = "AllowSQLOutbound"
    priority                  = 203
    direction                 = "Outbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "1443"
    source_address_prefix     = "VirtualNetwork"
    destination_address_prefix= "SQL"
  }
  # Dependency for Log to Event Hub policy and monitoring agent
  security_rule {
    name                      = "AllowEventHubAMQPOutbound"
    priority                  = 204
    direction                 = "Outbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "5671-5672"
    source_address_prefix     = "VirtualNetwork"
    destination_address_prefix= "EventHub"
  }
  security_rule {
    name                      = "AllowEventHubHTTPOutbound"
    priority                  = 205
    direction                 = "Outbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "443"
    source_address_prefix     = "VirtualNetwork"
    destination_address_prefix= "EventHub"
  }
  # Health and Monitoring Extension
  security_rule {
    name                      = "AllowHealthMonitoringOutbound"
    priority                  = 206
    direction                 = "Outbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "12000"
    source_address_prefix     = "VirtualNetwork"
    destination_address_prefix= "AzureCloud"
  }
  security_rule {
    name                      = "AllowHealthHTTPMonitoringOutbound"
    priority                  = 207
    direction                 = "Outbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "443"
    source_address_prefix     = "VirtualNetwork"
    destination_address_prefix= "AzureCloud"
  }
  # Publish Diagnostics Logs and Metrics, Resource Health and Application Insights
  security_rule {
    name                      = "AllowMonitoringOutbound"
    priority                  = 208
    direction                 = "Outbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "1886"
    source_address_prefix     = "VirtualNetwork"
    destination_address_prefix= "AzureMonitor"
  }
  security_rule {
    name                      = "AllowHTTPMonitoringOutbound"
    priority                  = 209
    direction                 = "Outbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "443"
    source_address_prefix     = "VirtualNetwork"
    destination_address_prefix= "AzureMonitor"
  }
  # Connect to SMTP Relay for sending e-mails
  security_rule {
    name                      = "AllowSMTP25RelayOutbound"
    priority                  = 210
    direction                 = "Outbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "25"
    source_address_prefix     = "VirtualNetwork"
    destination_address_prefix= "Internet"
  }
  security_rule {
    name                      = "AllowSMTP587RelayyOutbound"
    priority                  = 211
    direction                 = "Outbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "587"
    source_address_prefix     = "Internet"
    destination_address_prefix= azurerm_firewall.iag.ip_configuration.0.private_ip_address
  }
  security_rule {
    name                      = "AllowSMTP25028RelayyOutbound"
    priority                  = 212
    direction                 = "Outbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "25028"
    source_address_prefix     = "Internet"
    destination_address_prefix= azurerm_firewall.iag.ip_configuration.0.private_ip_address
  }
  # Access Redis Service for Cache policies between machines
  security_rule {
    name                      = "AllowRedisCacheOutbound"
    priority                  = 213
    direction                 = "Outbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "6381-6383"
    source_address_prefix     = "VirtualNetwork"
    destination_address_prefix= "VirtualNetwork"
  }
  # Sync Counters for Rate Limit policies between machines
  security_rule {
    name                      = "AllowSyncCountersOutbound"
    priority                  = 214
    direction                 = "Outbound"
    access                    = "Allow"
    protocol                  = "Udp"
    source_port_range         = "*"
    destination_port_range    = "4290"
    source_address_prefix     = "VirtualNetwork"
    destination_address_prefix= "VirtualNetwork"
  }
  # Debug
  security_rule {
    name                      = "AllowALLOutbound"
    priority                  = 299
    direction                 = "Outbound"
    access                    = "Allow"
    protocol                  = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "*"
    source_address_prefix     = "*"
    destination_address_prefix= "*"
  }
}
resource azurerm_network_watcher_flow_log apim_nsg {
  network_watcher_name         = local.network_watcher_name
  resource_group_name          = local.network_watcher_resource_group

  network_security_group_id    = azurerm_network_security_group.apim_nsg.id
  storage_account_id           = azurerm_storage_account.vdc_diag_storage.id
  enabled                      = true
  version                      = 2

  retention_policy {
    enabled                    = true
    days                       = 7
  }

  traffic_analytics {
    enabled                    = true
    workspace_id               = azurerm_log_analytics_workspace.vcd_workspace.workspace_id
    interval_in_minutes        = 10
    workspace_region           = local.workspace_location
    workspace_resource_id      = azurerm_log_analytics_workspace.vcd_workspace.id
  }

  count                        = var.deploy_network_watcher ? 1 : 0
}
resource azurerm_monitor_diagnostic_setting apim_nsg_logs {
  name                         = "${azurerm_network_security_group.apim_nsg.name}-logs"
  target_resource_id           = azurerm_network_security_group.apim_nsg.id
  storage_account_id           = azurerm_storage_account.vdc_diag_storage.id
  log_analytics_workspace_id   = azurerm_log_analytics_workspace.vcd_workspace.id

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

resource azurerm_subnet_network_security_group_association apim_subnet_nsg {
  subnet_id                    = azurerm_subnet.apim_subnet.id
  network_security_group_id    = azurerm_network_security_group.apim_nsg.id

  timeouts {
    create                     = var.default_create_timeout
    update                     = var.default_update_timeout
    read                       = var.default_read_timeout
    delete                     = var.default_delete_timeout
  }  

  depends_on                   = [azurerm_subnet_route_table_association.mgmt_subnet_routes,
                                  azurerm_firewall_application_rule_collection.iag_app_rules,
                                  azurerm_firewall_network_rule_collection.iag_net_outbound_rules
  ]
}

resource azurerm_api_management api_gateway {
  name                         = "${azurerm_resource_group.vdc_rg.name}-apigw"
  location                     = azurerm_resource_group.vdc_rg.location
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  publisher_name               = "Automated VDC"
  publisher_email              = var.admin_login
  sku_name                     = "Developer_1"

  hostname_configuration {
    portal {
      certificate              = filebase64(var.vanity_certificate_path) # load pfx from file
      certificate_password     = var.vanity_certificate_password
      host_name                = local.apim_portal_fqdn
      #negotiate_client_certificate = true # Trust AppGW only
    }
    proxy {
      certificate              = filebase64(var.vanity_certificate_path) # load pfx from file
      certificate_password     = var.vanity_certificate_password
      host_name                = local.apim_gw_fqdn
      negotiate_client_certificate = true # Trust AppGW only
    }
  }

  identity {
    type                       = "SystemAssigned"
  }
  notification_sender_email    = var.apim_notification_sender_email
  virtual_network_type         = "Internal"
  virtual_network_configuration {
    subnet_id                  = azurerm_subnet.apim_subnet.id
  }

  sign_up {
    enabled                    = true
    terms_of_service {
      consent_required         = false
      enabled                  = false
      text                     = "ToS text"
    }
  }

  timeouts {
    create                     = "${max(90,replace(var.default_create_timeout,"/h|m/",""))}m"
    update                     = var.default_update_timeout
    read                       = var.default_read_timeout
    delete                     = var.default_delete_timeout
  }  

  count                        = local.deploy_api_gateway ? 1 : 0

  depends_on                   = [azurerm_subnet_route_table_association.apim_subnet_routes,
                                  azurerm_subnet_network_security_group_association.apim_subnet_nsg,
                                  azurerm_firewall_application_rule_collection.iag_apim_app_rules,
                                  azurerm_firewall_network_rule_collection.iag_net_outbound_apim_rules
  ]
}
resource azurerm_monitor_diagnostic_setting apim_logs {
  name                         = "${azurerm_api_management.api_gateway.0.name}-logs"
  target_resource_id           = azurerm_api_management.api_gateway.0.id
  storage_account_id           = azurerm_storage_account.vdc_diag_storage.id
  log_analytics_workspace_id   = azurerm_log_analytics_workspace.vcd_workspace.id

  log {
    category                   = "GatewayLogs"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }

  count                        = local.deploy_api_gateway ? 1 : 0
}
resource azurerm_api_management_identity_provider_aad subscription {
  api_management_name          = azurerm_api_management.api_gateway.0.name
  resource_group_name          = azurerm_api_management.api_gateway.0.resource_group_name
  client_id                    = var.apim_aad_client_id
  client_secret                = var.apim_aad_client_secret
  allowed_tenants              = [data.azurerm_subscription.primary.tenant_id]

  count                        = (local.deploy_api_gateway && var.apim_aad_client_id != null && var.apim_aad_client_secret != null) ? 1 : 0
}

# Sample
data azurerm_api_management_product starter {
  product_id                   = "Starter"
  api_management_name          = azurerm_api_management.api_gateway.0.name
  resource_group_name          = azurerm_api_management.api_gateway.0.resource_group_name

  count                        = local.deploy_api_gateway ? 1 : 0

  depends_on                   = [azurerm_api_management.api_gateway]
}
resource azurerm_api_management_user demo_user {
  user_id                      = uuid()
  api_management_name          = azurerm_api_management.api_gateway.0.name
  resource_group_name          = azurerm_api_management.api_gateway.0.resource_group_name
  first_name                   = "Example"
  last_name                    = "User"
  email                        = "developer@nowhere.com"
  state                        = "active"

  count                        = local.deploy_api_gateway ? 1 : 0
}
resource azurerm_api_management_subscription echo_subscription {
  api_management_name          = azurerm_api_management.api_gateway.0.name
  resource_group_name          = azurerm_api_management.api_gateway.0.resource_group_name
  user_id                      = azurerm_api_management_user.demo_user.0.id
  product_id                   = data.azurerm_api_management_product.starter.0.id
  display_name                 = "Echo API"
  state                        = "active"

  count                        = local.deploy_api_gateway ? 1 : 0
}