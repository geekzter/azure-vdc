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
}

resource "azurerm_public_ip" "waf_pip" {
  name                         = "${azurerm_resource_group.vdc_rg.name}-waf-pip"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  allocation_method            = "Static"
  sku                          = "Standard"
  domain_name_label            = "${random_string.waf_domain_name_label.result}"

  tags                         = "${local.tags}"
}

resource "azurerm_dns_cname_record" "waf_pip_cname" {
  name                         = "${lower(var.resource_prefix)}${lower(var.resource_environment)}app"
  zone_name                    = "${data.azurerm_dns_zone.vanity_domain.name}"
  resource_group_name          = "${data.azurerm_dns_zone.vanity_domain.resource_group_name}"
  ttl                          = 300
  record                       = "${azurerm_public_ip.waf_pip.fqdn}"
  depends_on                   = ["azurerm_public_ip.waf_pip"]

  tags                         = "${local.tags}"
} 

locals {
  ssl_count                    = "${var.use_ssl ? 1 : 0}"
  ssl_range                    = "${range(local.ssl_count)}" # Contains one item only if var.use_ssl = true
  ssl_range_inverted           = "${range(1-local.ssl_count)}" # Contains one item only if var.use_ssl = false
  app_fqdn                     = "${azurerm_dns_cname_record.waf_pip_cname.name}.${azurerm_dns_cname_record.waf_pip_cname.zone_name}"
}

resource "azurerm_application_gateway" "waf" {
  name                         = "${azurerm_resource_group.vdc_rg.name}-waf"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  location                     = "${azurerm_resource_group.vdc_rg.location}"

  sku {
    name                       = "WAF_v2"
    tier                       = "WAF_v2"
    capacity                   = 2
  }

  gateway_ip_configuration {
    name                       = "waf-ip-configuration"
    subnet_id                  = "${azurerm_subnet.waf_subnet.id}"
  }

  frontend_port {
    name                       = "http"
    port                       = 80
  }
  frontend_port {
    name                       = "https"
    port                       = 443
  }
  frontend_ip_configuration {
    name                       = "${azurerm_resource_group.app_rg.name}-ip-configuration"
    public_ip_address_id       = "${azurerm_public_ip.waf_pip.id}"
  }

  backend_address_pool {
    name                       = "${azurerm_resource_group.app_rg.name}-webservers"
    ip_addresses               = "${var.app_web_vms}"
  }
  backend_http_settings {
    name                       = "${azurerm_resource_group.app_rg.name}-config"
    cookie_based_affinity      = "Disabled"
    path                       = "/"
    port                       = 80
    protocol                   = "Http"
    request_timeout            = 1
  }

  http_listener {
    name                       = "${azurerm_resource_group.app_rg.name}-http-listener"
    frontend_ip_configuration_name = "${azurerm_resource_group.app_rg.name}-ip-configuration"
    frontend_port_name         = "http"
    protocol                   = "Http"
  }
  # http_listener {
  #   name                       = "${azurerm_resource_group.app_rg.name}-https-listener"
  #   frontend_ip_configuration_name = "${azurerm_resource_group.app_rg.name}-ip-configuration"
  #   frontend_port_name         = "https"
  #   protocol                   = "Https"
  #   host_name                  = "${local.app_fqdn}"
  #   ssl_certificate_name       = "${var.vanity_certificate_name}"
  # } 
  # HACK: This is a way to make HTTPS and SSL optional 
  dynamic "http_listener" {
    for_each = local.ssl_range
    content {
      name                     = "${azurerm_resource_group.app_rg.name}-https-listener"
      frontend_ip_configuration_name = "${azurerm_resource_group.app_rg.name}-ip-configuration"
      frontend_port_name       = "https"
      protocol                 = "Https"
      host_name                = "${local.app_fqdn}"
      ssl_certificate_name     = "${var.vanity_certificate_name}"
    }
  }

  # request_routing_rule {
  #   name                       = "${azurerm_resource_group.app_rg.name}-http-rule"
  #   rule_type                  = "Basic"
  #   http_listener_name         = "${azurerm_resource_group.app_rg.name}-http-listener"
  #   backend_address_pool_name  = "${azurerm_resource_group.app_rg.name}-webservers"
  #   backend_http_settings_name = "${azurerm_resource_group.app_rg.name}-config"
  # }
  dynamic "request_routing_rule" {
    # Applied when var.use_ssl = false
    for_each = local.ssl_range_inverted
    content {
      name                     = "${azurerm_resource_group.app_rg.name}-http-rule"
      rule_type                = "Basic"
      http_listener_name       = "${azurerm_resource_group.app_rg.name}-http-listener"
      backend_address_pool_name  = "${azurerm_resource_group.app_rg.name}-webservers"
      backend_http_settings_name = "${azurerm_resource_group.app_rg.name}-config"
    }
  }
  dynamic "request_routing_rule" {
    # Applied when var.use_ssl = true
    # Redirect HTTP to HTTPS
    for_each = local.ssl_range
    content {
      name                     = "${azurerm_resource_group.app_rg.name}-http-to-https-rule"
      rule_type                = "Basic"
      http_listener_name       = "${azurerm_resource_group.app_rg.name}-http-listener"
      redirect_configuration_name = "${azurerm_resource_group.app_rg.name}-http-to-https"
    }
  }
  # request_routing_rule {
  #   name                       = "${azurerm_resource_group.app_rg.name}-https-rule"
  #   rule_type                  = "Basic"
  #   http_listener_name         = "${azurerm_resource_group.app_rg.name}-https-listener"
  #   backend_address_pool_name  = "${azurerm_resource_group.app_rg.name}-webservers"
  #   backend_http_settings_name = "${azurerm_resource_group.app_rg.name}-config"
  # }
  # HACK: This is a way to make HTTPS and SSL optional 
  dynamic "request_routing_rule" {
    for_each = local.ssl_range
    content {
      name                     = "${azurerm_resource_group.app_rg.name}-https-rule"
      rule_type                = "Basic"
      http_listener_name       = "${azurerm_resource_group.app_rg.name}-https-listener"
      backend_address_pool_name = "${azurerm_resource_group.app_rg.name}-webservers"
      backend_http_settings_name = "${azurerm_resource_group.app_rg.name}-config"
    }
  }
  # ssl_certificate {
  #   name                       = "${var.vanity_certificate_name}"
  #   data                       = "${filebase64(var.vanity_certificate_path)}" # load pfx from file
  #   password                   = "${var.vanity_certificate_password}"
  # }
  # HACK: This is a way to make HTTPS and SSL optional (for those too lazy to create a certificate)
  dynamic "ssl_certificate" {
    for_each = local.ssl_range
    content {
      name                     = "${var.vanity_certificate_name}"
      data                     = "${filebase64(var.vanity_certificate_path)}" # load pfx from file
      password                 = "${var.vanity_certificate_password}"
    }
  }

  dynamic "redirect_configuration" {
    for_each = local.ssl_range
    content {
      name                     = "${azurerm_resource_group.app_rg.name}-http-to-https"
      redirect_type            = "Temporary" # HTTP 302
      target_listener_name     = "${azurerm_resource_group.app_rg.name}-https-listener"
    }
  }

  waf_configuration {
    enabled                    = true
    firewall_mode              = "Detection"
    rule_set_type              = "OWASP"
    rule_set_version           = "3.0"
  }

  tags                         = "${local.tags}"
}