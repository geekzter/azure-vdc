data azurerm_dns_zone vanity_domain {
  name                         = var.vanity_domainname
  resource_group_name          = var.shared_resources_group
  count                        = var.use_vanity_domain_and_ssl ? 1 : 0
}

resource random_string waf_domain_name_label {
  length                      = 16
  upper                       = false
  lower                       = true
  number                      = false
  special                     = false
}
resource azurerm_public_ip waf_pip {
  name                         = "${azurerm_resource_group.vdc_rg.name}-waf-pip"
  location                     = azurerm_resource_group.vdc_rg.location
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  allocation_method            = "Static"
  sku                          = "Standard" # Zone redundant
  domain_name_label            = random_string.waf_domain_name_label.result

  tags                         = local.tags
}

resource azurerm_dns_cname_record waf_iaas_app_cname {
  name                         = "${lower(var.resource_prefix)}${lower(terraform.workspace)}iisapp"
  zone_name                    = data.azurerm_dns_zone.vanity_domain.0.name
  resource_group_name          = data.azurerm_dns_zone.vanity_domain.0.resource_group_name
  ttl                          = 300
  record                       = azurerm_public_ip.waf_pip.fqdn
  depends_on                   = [azurerm_public_ip.waf_pip]

  tags                         = local.tags
  count                        = var.use_vanity_domain_and_ssl ? 1 : 0
} 
resource azurerm_dns_cname_record waf_paas_app_cname {
  name                         = "${lower(var.resource_prefix)}${lower(terraform.workspace)}webapp"
  zone_name                    = data.azurerm_dns_zone.vanity_domain.0.name
  resource_group_name          = data.azurerm_dns_zone.vanity_domain.0.resource_group_name
  ttl                          = 300
  record                       = azurerm_public_ip.waf_pip.fqdn

  tags                         = local.tags
  count                        = var.use_vanity_domain_and_ssl ? 1 : 0
} 
resource azurerm_dns_cname_record waf_apim_gw_cname {
  name                         = "${lower(var.resource_prefix)}${lower(terraform.workspace)}apiproxy"
  zone_name                    = data.azurerm_dns_zone.vanity_domain.0.name
  resource_group_name          = data.azurerm_dns_zone.vanity_domain.0.resource_group_name
  ttl                          = 300
  record                       = azurerm_public_ip.waf_pip.fqdn

  tags                         = local.tags
  count                        = var.use_vanity_domain_and_ssl ? 1 : 0
} 

resource azurerm_dns_cname_record waf_apim_portal_cname {
  name                         = "${lower(var.resource_prefix)}${lower(terraform.workspace)}apiportal"
  zone_name                    = data.azurerm_dns_zone.vanity_domain.0.name
  resource_group_name          = data.azurerm_dns_zone.vanity_domain.0.resource_group_name
  ttl                          = 300
  record                       = azurerm_public_ip.waf_pip.fqdn

  tags                         = local.tags
  count                        = var.use_vanity_domain_and_ssl ? 1 : 0
} 

locals {
  ssl_range                    = range(var.use_vanity_domain_and_ssl ? 1 : 0) # Contains one item only if var.use_vanity_domain_and_ssl = true
  ssl_range_inverted           = range(var.use_vanity_domain_and_ssl ? 0 : 1) # Contains one item only if var.use_vanity_domain_and_ssl = false
  http80_listener              = "${module.paas_app.app_resource_group}-http-listener"
  http81_listener              = "${module.iis_app.app_resource_group}-http-listener"

  iaas_app_fqdn                = var.use_vanity_domain_and_ssl ? "${azurerm_dns_cname_record.waf_iaas_app_cname[0].name}.${azurerm_dns_cname_record.waf_iaas_app_cname[0].zone_name}" : azurerm_public_ip.waf_pip.fqdn
  iaas_app_url                 = "${var.use_vanity_domain_and_ssl ? "https" : "http"}://${local.iaas_app_fqdn}${var.use_vanity_domain_and_ssl ? "" : ":81"}/"
  iaas_app_backend_pool        = "${module.iis_app.app_resource_group}-webservers"
  iaas_app_backend_setting     = "${module.iis_app.app_resource_group}-config"
  iaas_app_https_listener      = "${module.iis_app.app_resource_group}-https-listener"
  iaas_app_redirect_config     = "${module.iis_app.app_resource_group}-http-to-https"
  
  paas_app_fqdn                = var.use_vanity_domain_and_ssl ? "${azurerm_dns_cname_record.waf_paas_app_cname[0].name}.${azurerm_dns_cname_record.waf_paas_app_cname[0].zone_name}" : azurerm_public_ip.waf_pip.fqdn
  paas_app_url                 = "${var.use_vanity_domain_and_ssl ? "https" : "http"}://${local.paas_app_fqdn}/"
  paas_app_backend_pool        = "${module.paas_app.app_resource_group}-appsvc"
  paas_app_backend_setting     = "${module.paas_app.app_resource_group}-config"
  paas_app_https_listener      = "${module.paas_app.app_resource_group}-https-listener"
  paas_app_redirect_config     = "${module.paas_app.app_resource_group}-http-to-https"

  apim_gw_fqdn                 = var.use_vanity_domain_and_ssl ? "${azurerm_dns_cname_record.waf_apim_gw_cname[0].name}.${azurerm_dns_cname_record.waf_apim_gw_cname[0].zone_name}" : azurerm_public_ip.waf_pip.fqdn
  apim_gw_url                  = "${var.use_vanity_domain_and_ssl ? "https" : "http"}://${local.apim_gw_fqdn}/"
  apim_gw_backend_pool         = "${azurerm_resource_group.vdc_rg.name}-apigw-backend-pool"
  apim_gw_backend_setting      = "${azurerm_resource_group.vdc_rg.name}-apigw-backend-setting"
  apim_gw_https_listener       = "${azurerm_resource_group.vdc_rg.name}-apigw-listener"

  apim_portal_fqdn             = var.use_vanity_domain_and_ssl ? "${azurerm_dns_cname_record.waf_apim_portal_cname[0].name}.${azurerm_dns_cname_record.waf_apim_portal_cname[0].zone_name}" : azurerm_public_ip.waf_pip.fqdn
  apim_portal_url              = "${var.use_vanity_domain_and_ssl ? "https" : "http"}://${local.apim_portal_fqdn}/"
  apim_portal_backend_pool     = "${azurerm_resource_group.vdc_rg.name}-apiportal-backend-pool"
  apim_portal_backend_setting  = "${azurerm_resource_group.vdc_rg.name}-apiportal-backend-setting"
  apim_portal_https_listener   = "${azurerm_resource_group.vdc_rg.name}-apiportal-listener"

  waf_frontend_ip_config       = "${azurerm_resource_group.vdc_rg.name}-waf-ip-configuration"
}

resource azurerm_application_gateway waf {
  name                         = "${azurerm_resource_group.vdc_rg.name}-waf"
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  location                     = azurerm_resource_group.vdc_rg.location

  sku {
    # v2 SKU's are zone redundant
    name                       = "WAF_v2"
    tier                       = "WAF_v2"
    capacity                   = 2
  }
  # Zone redundant
  zones                        = ["1", "2", "3"]

  gateway_ip_configuration {
    name                       = "waf-ip-configuration"
    subnet_id                  = azurerm_subnet.waf_subnet.id
  }

  # Applications
  frontend_ip_configuration {
    name                       = local.waf_frontend_ip_config
    public_ip_address_id       = azurerm_public_ip.waf_pip.id
  }
  frontend_port {
    name                       = "http"
    port                       = 80
  }
  frontend_port {
    name                       = "http81"
    port                       = 81
  }
  frontend_port {
    name                       = "https"
    port                       = 443
  }

  # This is a way to make HTTPS and SSL optional (for those too lazy to create a certificate)
  dynamic "ssl_certificate" {
    for_each = local.ssl_range
    content {
      name                     = var.vanity_certificate_name
      data                     = filebase64(var.vanity_certificate_path) # load pfx from file
      password                 = var.vanity_certificate_password
    }
  }

  #### IaaS IIS App
  backend_address_pool {
    name                       = local.iaas_app_backend_pool 
    ip_addresses               = var.app_web_vms
  }
  backend_http_settings {
    name                       = local.iaas_app_backend_setting
    cookie_based_affinity      = "Disabled"
    path                       = "/"
    port                       = 80
    protocol                   = "Http"
    request_timeout            = 10
  }
  http_listener {
    name                       = local.http81_listener 
    frontend_ip_configuration_name = local.waf_frontend_ip_config
    frontend_port_name         = "http81"
    host_name                  = local.iaas_app_fqdn
    protocol                   = "Http"
  }
  # This is a way to make HTTPS and SSL optional 
  dynamic "http_listener" {
    for_each = local.ssl_range
    content {
      name                     = local.iaas_app_https_listener
      frontend_ip_configuration_name = local.waf_frontend_ip_config
      frontend_port_name       = "https"
      protocol                 = "Https"
      host_name                = local.iaas_app_fqdn
      ssl_certificate_name     = var.vanity_certificate_name
    }
  }
  dynamic "request_routing_rule" {
    # Applied when var.use_vanity_domain_and_ssl = false
    for_each = local.ssl_range_inverted
    content {
      name                     = "${module.iis_app.app_resource_group}-http-rule"
      rule_type                = "Basic"
      http_listener_name       = local.http81_listener 
      backend_address_pool_name  = local.iaas_app_backend_pool 
      backend_http_settings_name = local.iaas_app_backend_setting
    }
  }
  dynamic "request_routing_rule" {
    # Applied when var.use_vanity_domain_and_ssl = true
    # Redirect HTTP (port 81) to HTTPS
    for_each = local.ssl_range
    content {
      name                     = "${module.iis_app.app_resource_group}-http81-to-https-rule"
      rule_type                = "Basic"
      http_listener_name       = local.http81_listener 
      redirect_configuration_name = local.iaas_app_redirect_config
    }
  }
  # This is a way to make HTTPS and SSL optional 
  dynamic "request_routing_rule" {
    for_each = local.ssl_range
    content {
      name                     = "${module.iis_app.app_resource_group}-https-rule"
      rule_type                = "Basic"
      http_listener_name       = local.iaas_app_https_listener
      backend_address_pool_name = local.iaas_app_backend_pool 
      backend_http_settings_name = local.iaas_app_backend_setting
    }
  }
  dynamic "redirect_configuration" {
    for_each = local.ssl_range
    content {
      name                     = local.iaas_app_redirect_config
      redirect_type            = "Temporary" # HTTP 302
      target_listener_name     = local.iaas_app_https_listener
    }
  }

  #### PaaS App Service App
  backend_address_pool {
    name                       = local.paas_app_backend_pool
    fqdns                      = [module.paas_app.app_service_fqdn]
  }
  backend_http_settings {
    name                       = local.paas_app_backend_setting
    cookie_based_affinity      = "Disabled"
    # Used when terminating SSL at App Service
    host_name                  = local.paas_app_fqdn
    port                       = 443
    probe_name                 = "paas-app-probe"
    protocol                   = "Https"
    request_timeout            = 10
  }

  http_listener {
    name                       = local.http80_listener
    frontend_ip_configuration_name = local.waf_frontend_ip_config
    frontend_port_name         = "http"
    host_name                  = local.paas_app_fqdn
    protocol                   = "Http"
  }
  # This is a way to make HTTPS and SSL optional 
  dynamic "http_listener" {
    for_each = local.ssl_range
    content {
      name                     = local.paas_app_https_listener
      frontend_ip_configuration_name = local.waf_frontend_ip_config
      frontend_port_name       = "https"
      protocol                 = "Https"
      host_name                = local.paas_app_fqdn
      ssl_certificate_name     = var.vanity_certificate_name
    }
  }
  dynamic "request_routing_rule" {
    # Applied when var.use_vanity_domain_and_ssl = false
    for_each = local.ssl_range_inverted
    content {
      name                     = "${module.paas_app.app_resource_group}-http-rule"
      rule_type                = "Basic"
      http_listener_name       = local.http80_listener
      backend_address_pool_name  = local.paas_app_backend_pool
      backend_http_settings_name = local.paas_app_backend_setting
    }
  }
  dynamic "request_routing_rule" {
    # Applied when var.use_vanity_domain_and_ssl = true
    # Redirect HTTP to HTTPS
    for_each = local.ssl_range
    content {
      name                     = "${module.paas_app.app_resource_group}-http-to-https-rule"
      rule_type                = "Basic"
      http_listener_name       = local.http80_listener
      redirect_configuration_name = local.paas_app_redirect_config
    }
  }
  # This is a way to make HTTPS and SSL optional 
  dynamic "request_routing_rule" {
    for_each = local.ssl_range
    content {
      name                     = "${module.paas_app.app_resource_group}-https-rule"
      rule_type                = "Basic"
      http_listener_name       = local.paas_app_https_listener
      backend_address_pool_name = local.paas_app_backend_pool
      backend_http_settings_name = local.paas_app_backend_setting
      rewrite_rule_set_name    = "paas-rewrite-rules"
    }
  }
  dynamic "redirect_configuration" {
    for_each = local.ssl_range
    content {
      name                     = local.paas_app_redirect_config
      redirect_type            = "Temporary" # HTTP 302
      target_listener_name     = local.paas_app_https_listener
    }
  }
  # These rules rewrite the App Service URL with the vanity domain one
  # This is required when terminating SSL at App Gateway
  # This is also recommended in general, just to make sure redirects that use the wrong hostname still work
  rewrite_rule_set {
    name                       = "paas-rewrite-rules"
    rewrite_rule {
      name                     = "paas-rewrite-response-redirect"
      rule_sequence            = 1
      condition {
        variable               = "http_resp_Location"
        pattern                = "(.*)redirect_uri=https%3A%2F%2F${module.paas_app.app_service_fqdn}(.*)$"
        ignore_case            = true
      }
      response_header_configuration {
        header_name            = "Location"
        header_value           = "{http_resp_Location_1}redirect_uri=https%3A%2F%2F${local.paas_app_fqdn}{http_resp_Location_2}" 
      }
    }
    rewrite_rule {
      name                     = "paas-rewrite-response-location"
      rule_sequence            = 2
      condition {
        variable               = "http_resp_Location"
        pattern                = "(https?):\\/\\/${module.paas_app.app_service_fqdn}(.*)$"
        ignore_case            = true
      }
      response_header_configuration {
        header_name            = "Location"
        header_value           = "{http_resp_Location_1}://${local.paas_app_fqdn}{http_resp_Location_2}" 
      }
    }
  }
  probe {
    name                       = "paas-app-probe"
    # Used alias when terminating SSL at App Service, as this will actually resolve to App Service (no loop to App Gateway)
    host                       = module.paas_app.app_service_alias_fqdn
    path                       = "/"
    # Used when terminating SSL at App Gateway
    #pick_host_name_from_backend_http_settings = true
    protocol                   = "Https"
    interval                   = 3
    timeout                    = 3
    unhealthy_threshold        = 3
    match {
      body                     = ""
      status_code              = ["200-399","401"]
    }
  }

  # API Management Proxy
  dynamic "backend_address_pool" {
    for_each = range(var.deploy_api_gateway ? 1 : 0)
    content {
      name                     = local.apim_gw_backend_pool
      ip_addresses             = try(azurerm_api_management.api_gateway.0.private_ip_addresses,null)
    }
  }
  dynamic "backend_http_settings" {
    for_each = range(var.use_vanity_domain_and_ssl && var.deploy_api_gateway ? 1 : 0)
    content {
      name                     = local.apim_gw_backend_setting
      cookie_based_affinity    = "Disabled"
      # Used when terminatingSL at App Service
      host_name                = local.apim_gw_fqdn
      port                     = 443
      probe_name               = "apim-gw-probe"
      protocol                 = "Https"
      request_timeout          = 180
      trusted_root_certificate_names = [var.vanity_certificate_name]
    }
  }
  dynamic "http_listener" {
    for_each = range(var.use_vanity_domain_and_ssl && var.deploy_api_gateway ? 1 : 0)
    content {
      name                     = local.apim_gw_https_listener
      frontend_ip_configuration_name = local.waf_frontend_ip_config
      frontend_port_name       = "https"
      protocol                 = "Https"
      host_name                = local.apim_gw_fqdn
      ssl_certificate_name     = var.vanity_certificate_name
    }
  }
  dynamic "request_routing_rule" {
    for_each = range(var.use_vanity_domain_and_ssl && var.deploy_api_gateway ? 1 : 0)
    content {
      name                     = "${azurerm_resource_group.vdc_rg.name}-apigw-https-rule"
      rule_type                = "Basic"
      http_listener_name       = local.apim_gw_https_listener
      backend_address_pool_name = local.apim_gw_backend_pool
      backend_http_settings_name = local.apim_gw_backend_setting
    }
  }
  probe {
    name                       = "apim-gw-probe"
    # Used alias when terminating SSL at App Service, as this will actually resolve to App Service (no loop to App Gateway)
    host                       = local.apim_gw_fqdn
    path                       = "/status-0123456789abcdef"
    # Used when terminating SSL at App Gateway
    #pick_host_name_from_backend_http_settings = true
    protocol                   = "Https"
    interval                   = 30
    timeout                    = 120
    unhealthy_threshold        = 8
    # match {
    #   body                     = ""
    #   status_code              = ["200-399","401"]
    # }
  }
  dynamic "trusted_root_certificate" {
    for_each = range(var.use_vanity_domain_and_ssl && var.deploy_api_gateway ? 1 : 0)
    content {
      name                     = var.vanity_certificate_name
      data                     = filebase64(var.vanity_root_certificate_cer_path)
    }
  }

  # API Management Portal
  dynamic "backend_http_settings" {
    for_each = range(var.use_vanity_domain_and_ssl && var.deploy_api_gateway ? 1 : 0)
    content {
      name                     = local.apim_portal_backend_setting
      cookie_based_affinity    = "Disabled"
      # Used when terminating SSL at App Service
      host_name                = local.apim_portal_fqdn
      port                     = 443
      probe_name               = "apim-portal-probe"
      protocol                 = "Https"
      request_timeout          = 180
      trusted_root_certificate_names = [var.vanity_certificate_name]
    }
  }
  dynamic "http_listener" {
    for_each = range(var.use_vanity_domain_and_ssl && var.deploy_api_gateway ? 1 : 0)
    content {
      name                     = local.apim_portal_https_listener
      frontend_ip_configuration_name = local.waf_frontend_ip_config
      frontend_port_name       = "https"
      protocol                 = "Https"
      host_name                = local.apim_portal_fqdn
      ssl_certificate_name     = var.vanity_certificate_name
    }
  }
  dynamic "request_routing_rule" {
    for_each = range(var.use_vanity_domain_and_ssl && var.deploy_api_gateway ? 1 : 0)
    content {
      name                     = "${azurerm_resource_group.vdc_rg.name}-apiportal-https-rule"
      rule_type                = "Basic"
      http_listener_name       = local.apim_portal_https_listener
      backend_address_pool_name = local.apim_gw_backend_pool
      backend_http_settings_name = local.apim_portal_backend_setting
    }
  }
  probe {
    name                       = "apim-portal-probe"
    # Used alias when terminating SSL at App Service, as this will actually resolve to App Service (no loop to App Gateway)
    host                       = local.apim_portal_fqdn
    path                       = "/signin"
    # Used when terminating SSL at App Gateway
    #pick_host_name_from_backend_http_settings = true
    protocol                   = "Https"
    interval                   = 30
    timeout                    = 120
    unhealthy_threshold        = 8
    # match {
    #   body                     = ""
    #   status_code              = ["200-399","401"]
    # }
  }

  waf_configuration {
    enabled                    = true
    firewall_mode              = "Detection"
    rule_set_type              = "OWASP"
    rule_set_version           = "3.1"
  }

  tags                         = local.tags
}

resource azurerm_monitor_diagnostic_setting waf_iaas_app_pip_logs {
  name                         = "${azurerm_public_ip.waf_pip.name}-logs"
  target_resource_id           = azurerm_public_ip.waf_pip.id
  storage_account_id           = azurerm_storage_account.vdc_diag_storage.id
  log_analytics_workspace_id   = azurerm_log_analytics_workspace.vcd_workspace.id

  log {
    category                   = "DDoSProtectionNotifications"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }

  log {
    category                   = "DDoSMitigationFlowLogs"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }

  log {
    category                   = "DDoSMitigationReports"
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

resource azurerm_monitor_diagnostic_setting waf_logs {
  name                         = "${azurerm_application_gateway.waf.name}-logs"
  target_resource_id           = azurerm_application_gateway.waf.id
  storage_account_id           = azurerm_storage_account.vdc_diag_storage.id
  log_analytics_workspace_id   = azurerm_log_analytics_workspace.vcd_workspace.id

  log {
    category                   = "ApplicationGatewayAccessLog"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }

  log {
    category                   = "ApplicationGatewayPerformanceLog"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }

  log {
    category                   = "ApplicationGatewayFirewallLog"
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