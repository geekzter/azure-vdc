resource "random_string" "waf_domain_name_label" {
  length                      = 16
  upper                       = false
  lower                       = true
  number                      = false
  special                     = false
}

data "azurerm_dns_zone" "vanity_domain" {
  name                         = "${var.vanity_domainname}"
  resource_group_name          = "Shared"
  count                        = "${var.use_vanity_domain_and_ssl ? 1 : 0}"
}

resource "azurerm_public_ip" "waf_pip" {
  name                         = "${azurerm_resource_group.vdc_rg.name}-waf-pip"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  allocation_method            = "Static"
  sku                          = "Standard" # Zone redundant
  domain_name_label            = "${random_string.waf_domain_name_label.result}"

  tags                         = "${local.tags}"

  depends_on                   = ["azurerm_resource_group.vdc_rg"]
}

resource "azurerm_dns_cname_record" "waf_iaas_app_cname" {
  name                         = "${lower(var.resource_prefix)}${lower(var.resource_environment)}iisapp"
  zone_name                    = "${data.azurerm_dns_zone.vanity_domain.0.name}"
  resource_group_name          = "${data.azurerm_dns_zone.vanity_domain.0.resource_group_name}"
  ttl                          = 300
  record                       = "${azurerm_public_ip.waf_pip.fqdn}"
  depends_on                   = ["azurerm_public_ip.waf_pip"]

  count                        = "${var.use_vanity_domain_and_ssl ? 1 : 0}"
  tags                         = "${local.tags}"
} 

resource "azurerm_dns_cname_record" "waf_paas_app_cname" {
  name                         = "${lower(var.resource_prefix)}${lower(var.resource_environment)}webapp"
  zone_name                    = "${data.azurerm_dns_zone.vanity_domain.0.name}"
  resource_group_name          = "${data.azurerm_dns_zone.vanity_domain.0.resource_group_name}"
  ttl                          = 300
  record                       = "${azurerm_public_ip.waf_pip.fqdn}"
  depends_on                   = ["azurerm_public_ip.waf_pip"]

  count                        = "${var.use_vanity_domain_and_ssl ? 1 : 0}"
  tags                         = "${local.tags}"
} 

locals {
  ssl_range                    = "${range(var.use_vanity_domain_and_ssl ? 1 : 0)}" # Contains one item only if var.use_vanity_domain_and_ssl = true
  ssl_range_inverted           = "${range(var.use_vanity_domain_and_ssl ? 0 : 1)}" # Contains one item only if var.use_vanity_domain_and_ssl = false
  iaas_app_fqdn                = "${azurerm_dns_cname_record.waf_iaas_app_cname.0.name}.${azurerm_dns_cname_record.waf_iaas_app_cname.0.zone_name}"
  iaas_app_url                 = "${var.use_vanity_domain_and_ssl ? "https" : "http"}://${local.iaas_app_fqdn}/"
  paas_app_fqdn                = "${azurerm_dns_cname_record.waf_paas_app_cname.0.name}.${azurerm_dns_cname_record.waf_paas_app_cname.0.zone_name}"
  paas_app_url                 = "${var.use_vanity_domain_and_ssl ? "https" : "http"}://${local.paas_app_fqdn}/"
}

resource "azurerm_application_gateway" "waf" {
  name                         = "${azurerm_resource_group.vdc_rg.name}-waf"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  location                     = "${azurerm_resource_group.vdc_rg.location}"

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
    subnet_id                  = "${azurerm_subnet.waf_subnet.id}"
  }
  frontend_ip_configuration {
    name                       = "${azurerm_resource_group.vdc_rg.name}-waf-ip-configuration"
    public_ip_address_id       = "${azurerm_public_ip.waf_pip.id}"
  }
  frontend_port {
    name                       = "http"
    port                       = 80
  }
  frontend_port {
    name                       = "https"
    port                       = 443
  }

  # This is a way to make HTTPS and SSL optional (for those too lazy to create a certificate)
  dynamic "ssl_certificate" {
    for_each = local.ssl_range
    content {
      name                     = "${var.vanity_certificate_name}"
      data                     = "${filebase64(var.vanity_certificate_path)}" # load pfx from file
      password                 = "${var.vanity_certificate_password}"
    }
  }

/*
  BUG: when use_vanity_domain_and_ssl = false
Error: Error Creating/Updating Application Gateway "vdc-dev-uegl-waf" (Resource Group "vdc-dev-uegl"): network.ApplicationGatewaysClient#CreateOrUpdate: Failure sending request: StatusCode=400 -- Original Error: Code="ApplicationGatewayHttpListenersUsingSameFrontendPort" Message="Two Http Listeners of Application Gateway /resourceGroups/vdc-dev-uegl/providers/Microsoft.Network/applicationGateways/vdc-dev-uegl-waf are using the same Frontend Port /providers/Microsoft.Network/applicationGateways/vdc-dev-uegl-waf/frontendPorts/http." Details=[]
*/

  #### IaaS IIS App
  backend_address_pool {
    name                       = "${module.iis_app.app_resource_group}-webservers"
    ip_addresses               = "${var.app_web_vms}"
  }
  backend_http_settings {
    name                       = "${module.iis_app.app_resource_group}-config"
    cookie_based_affinity      = "Disabled"
    path                       = "/"
    port                       = 80
    protocol                   = "Http"
    request_timeout            = 1
  }
  http_listener {
    name                       = "${module.iis_app.app_resource_group}-http-listener"
    frontend_ip_configuration_name = "${azurerm_resource_group.vdc_rg.name}-waf-ip-configuration"
    frontend_port_name         = "http"
    host_name                  = "${local.iaas_app_fqdn}"
    protocol                   = "Http"
  }
  # This is a way to make HTTPS and SSL optional 
  dynamic "http_listener" {
    for_each = local.ssl_range
    content {
      name                     = "${module.iis_app.app_resource_group}-https-listener"
      frontend_ip_configuration_name = "${azurerm_resource_group.vdc_rg.name}-waf-ip-configuration"
      frontend_port_name       = "https"
      protocol                 = "Https"
      host_name                = "${local.iaas_app_fqdn}"
      ssl_certificate_name     = "${var.vanity_certificate_name}"
    }
  }
  dynamic "request_routing_rule" {
    # Applied when var.use_vanity_domain_and_ssl = false
    for_each = local.ssl_range_inverted
    content {
      name                     = "${module.iis_app.app_resource_group}-http-rule"
      rule_type                = "Basic"
      http_listener_name       = "${module.iis_app.app_resource_group}-http-listener"
      backend_address_pool_name  = "${module.iis_app.app_resource_group}-webservers"
      backend_http_settings_name = "${module.iis_app.app_resource_group}-config"
    }
  }
  dynamic "request_routing_rule" {
    # Applied when var.use_vanity_domain_and_ssl = true
    # Redirect HTTP to HTTPS
    for_each = local.ssl_range
    content {
      name                     = "${module.iis_app.app_resource_group}-http-to-https-rule"
      rule_type                = "Basic"
      http_listener_name       = "${module.iis_app.app_resource_group}-http-listener"
      redirect_configuration_name = "${module.iis_app.app_resource_group}-http-to-https"
    }
  }
  # This is a way to make HTTPS and SSL optional 
  dynamic "request_routing_rule" {
    for_each = local.ssl_range
    content {
      name                     = "${module.iis_app.app_resource_group}-https-rule"
      rule_type                = "Basic"
      http_listener_name       = "${module.iis_app.app_resource_group}-https-listener"
      backend_address_pool_name = "${module.iis_app.app_resource_group}-webservers"
      backend_http_settings_name = "${module.iis_app.app_resource_group}-config"
    }
  }
  dynamic "redirect_configuration" {
    for_each = local.ssl_range
    content {
      name                     = "${module.iis_app.app_resource_group}-http-to-https"
      redirect_type            = "Temporary" # HTTP 302
      target_listener_name     = "${module.iis_app.app_resource_group}-https-listener"
    }
  }

  #### PaaS App Service App
  backend_address_pool {
    name                       = "${module.paas_app.app_resource_group}-webservers"
    fqdns                      = ["${module.paas_app.app_service_fqdn}"]
  }
  backend_http_settings {
    name                       = "${module.paas_app.app_resource_group}-config"
    cookie_based_affinity      = "Disabled"
    path                       = "/"
    port                       = 80
    protocol                   = "Http"
    request_timeout            = 1
    pick_host_name_from_backend_address = true
  }
  http_listener {
    name                       = "${module.paas_app.app_resource_group}-http-listener"
    frontend_ip_configuration_name = "${azurerm_resource_group.vdc_rg.name}-waf-ip-configuration"
    frontend_port_name         = "http"
    host_name                  = "${local.paas_app_fqdn}"
    protocol                   = "Http"
  }
  # This is a way to make HTTPS and SSL optional 
  dynamic "http_listener" {
    for_each = local.ssl_range
    content {
      name                     = "${module.paas_app.app_resource_group}-https-listener"
      frontend_ip_configuration_name = "${azurerm_resource_group.vdc_rg.name}-waf-ip-configuration"
      frontend_port_name       = "https"
      protocol                 = "Https"
      host_name                = "${local.paas_app_fqdn}"
      ssl_certificate_name     = "${var.vanity_certificate_name}"
    }
  }
  dynamic "request_routing_rule" {
    # Applied when var.use_vanity_domain_and_ssl = false
    for_each = local.ssl_range_inverted
    content {
      name                     = "${module.paas_app.app_resource_group}-http-rule"
      rule_type                = "Basic"
      http_listener_name       = "${module.paas_app.app_resource_group}-http-listener"
      backend_address_pool_name  = "${module.paas_app.app_resource_group}-webservers"
      backend_http_settings_name = "${module.paas_app.app_resource_group}-config"
    }
  }
  dynamic "request_routing_rule" {
    # Applied when var.use_vanity_domain_and_ssl = true
    # Redirect HTTP to HTTPS
    for_each = local.ssl_range
    content {
      name                     = "${module.paas_app.app_resource_group}-http-to-https-rule"
      rule_type                = "Basic"
      http_listener_name       = "${module.paas_app.app_resource_group}-http-listener"
      redirect_configuration_name = "${module.paas_app.app_resource_group}-http-to-https"
    }
  }
  # This is a way to make HTTPS and SSL optional 
  dynamic "request_routing_rule" {
    for_each = local.ssl_range
    content {
      name                     = "${module.paas_app.app_resource_group}-https-rule"
      rule_type                = "Basic"
      http_listener_name       = "${module.paas_app.app_resource_group}-https-listener"
      backend_address_pool_name = "${module.paas_app.app_resource_group}-webservers"
      backend_http_settings_name = "${module.paas_app.app_resource_group}-config"
    }
  }
  dynamic "redirect_configuration" {
    for_each = local.ssl_range
    content {
      name                     = "${module.paas_app.app_resource_group}-http-to-https"
      redirect_type            = "Temporary" # HTTP 302
      target_listener_name     = "${module.paas_app.app_resource_group}-https-listener"
    }
  }
  # rewrite_rule_set {
  #   name                       = "paas-rewrite-rules"
  #   rewrite_rule {
  #     name                     = "paas-rewrite-host"
  #     rule_sequence            = 1
  #     condition {
  #       variable               = "Location"
  #       pattern                = "(https:?):\\/\\/.*azurewebsites\\.net(.*)$"
  #     }
  #     response_header_configuration {
  #       header_name            = "Location"
  #       header_value           = "{http_resp_Location_1}://${local.paas_app_fqdn}{http_resp_Location_2}" 
  #     }
  #   }
  # }

  waf_configuration {
    enabled                    = true
    firewall_mode              = "Detection"
    rule_set_type              = "OWASP"
    rule_set_version           = "3.1"
  }

  tags                         = "${local.tags}"
}

resource "azurerm_monitor_diagnostic_setting" "waf_iaas_app_pip_logs" {
  name                         = "${azurerm_public_ip.waf_pip.name}-logs"
  target_resource_id           = "${azurerm_public_ip.waf_pip.id}"
  storage_account_id           = "${azurerm_storage_account.vdc_diag_storage.id}"
  log_analytics_workspace_id   = "${azurerm_log_analytics_workspace.vcd_workspace.id}"

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
}

resource "azurerm_monitor_diagnostic_setting" "waf_logs" {
  name                         = "${azurerm_application_gateway.waf.name}-logs"
  target_resource_id           = "${azurerm_application_gateway.waf.id}"
  storage_account_id           = "${azurerm_storage_account.vdc_diag_storage.id}"
  log_analytics_workspace_id   = "${azurerm_log_analytics_workspace.vcd_workspace.id}"

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