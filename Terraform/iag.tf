resource "random_string" "iag_domain_name_label" {
  length                      = 16
  upper                       = false
  lower                       = true
  number                      = false
  special                     = false
}

resource "random_integer" "rdp_port" {
  min     = 1024
  max     = 64000
}

locals {
  rdp_port                     = var.rdp_port != null ? var.rdp_port : random_integer.rdp_port.result
}

resource "azurerm_public_ip" "iag_pip" {
  name                         = "${azurerm_resource_group.vdc_rg.name}-iag-pip"
  location                     = azurerm_resource_group.vdc_rg.location
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  allocation_method            = "Static"
  sku                          = "Standard" # Zone redundant
  domain_name_label            = random_string.iag_domain_name_label.result

  tags                         = local.tags
}

resource "azurerm_dns_cname_record" "iag_pip_cname" {
  name                         = "${lower(var.resource_prefix)}${lower(var.resource_environment)}iag"
  zone_name                    = data.azurerm_dns_zone.vanity_domain.0.name
  resource_group_name          = data.azurerm_dns_zone.vanity_domain.0.resource_group_name
  ttl                          = 300
  record                       = azurerm_public_ip.iag_pip.fqdn
  depends_on                   = [azurerm_public_ip.iag_pip]

  count                        = var.use_vanity_domain_and_ssl ? 1 : 0
  tags                         = local.tags
} 

resource "azurerm_firewall" "iag" {
  name                         = "${azurerm_resource_group.vdc_rg.name}-iag"
  location                     = azurerm_resource_group.vdc_rg.location
  resource_group_name          = azurerm_resource_group.vdc_rg.name

  # Make zone redundant
  zones                        = [1,2,3]

  ip_configuration {
    name                       = "iag_ipconfig"
    subnet_id                  = azurerm_subnet.iag_subnet.id
    public_ip_address_id       = azurerm_public_ip.iag_pip.id
  }
}

# Outbound domain whitelisting
resource "azurerm_firewall_application_rule_collection" "iag_app_rules" {
  name                         = "${azurerm_firewall.iag.name}-app-rules"
  azure_firewall_name          = azurerm_firewall.iag.name
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  priority                     = 200
  action                       = "Allow"

  rule {
    name                       = "Allow ${module.paas_app.storage_account_name} Storage"

    source_addresses           = [
      "${var.vdc_config["iaas_spoke_app_subnet"]}",
      "${var.vdc_config["iaas_spoke_data_subnet"]}",
      "${var.vdc_config["hub_mgmt_subnet"]}",
      "${var.vdc_config["vpn_range"]}"
    ]

    target_fqdns               = module.paas_app.storage_fqdns

    protocol {
        port                   = "443"
        type                   = "Https"
    }
  }

  rule {
    name                       = "Allow ${module.paas_app.eventhub_name} Event Hub HTTPS"

    source_addresses           = [
      "${var.vdc_config["iaas_spoke_app_subnet"]}",
      "${var.vdc_config["iaas_spoke_data_subnet"]}",
      "${var.vdc_config["hub_mgmt_subnet"]}",
      "${var.vdc_config["vpn_range"]}"
    ]

    target_fqdns               = [
    # module.paas_app.eventhub_namespace_fqdn, # BUG:  Not allowed even though it should match exactly
      "*${module.paas_app.eventhub_namespace_fqdn}" # HACK: Wildcard does the trick
    ]

    protocol {
        port                   = "443"
        type                   = "Https"
    }
  }

  rule {
    name                       = "Allow ${module.paas_app.sql_server} SQL Server TDS"

    source_addresses           = [
      "${var.vdc_config["iaas_spoke_app_subnet"]}",
      "${var.vdc_config["iaas_spoke_data_subnet"]}",
      "${var.vdc_config["hub_mgmt_subnet"]}",
      "${var.vdc_config["vpn_range"]}"
    ]

    target_fqdns               = [
      module.paas_app.sql_server_fqdn
    ]

    protocol {
        port                   = "1433"
        type                   = "Mssql"
    }
  }

  rule {
    name                       = "Allow Azure DevOps"
    description                = "The VSTS/Azure DevOps agent installed on application VM's requires outbound access. This agent is used by Azure Pipelines for application deployment"

    source_addresses           = [
      var.vdc_config["iaas_spoke_app_subnet"],
      var.vdc_config["iaas_spoke_data_subnet"],
      var.vdc_config["hub_mgmt_subnet"],
      var.vdc_config["vpn_range"]
    ]

    target_fqdns               = [
      # https://docs.microsoft.com/en-us/azure/devops/pipelines/agents/v2-windows?view=azure-devops
      "*.dev.azure.com",
      "*.pkgs.visualstudio.com",
      "*.visualstudio.com",
      "*.vsassets.io",
      "*.vsrm.visualstudio.com",
      "*.vssps.visualstudio.com",
      "dev.azure.com",
      "login.microsoftonline.com",
      "visualstudio-devdiv-c2s.msedge.net",
      "vstsagentpackage.azureedge.net"
    ]

    protocol {
        port                   = "443"
        type                   = "Https"
    }
  } 

  rule {
    name                       = "Allow Packaging tools"
    description                = "Packaging (e.g. Chocolatey, NuGet) tools"

    source_addresses           = [
      var.vdc_config["iaas_spoke_app_subnet"],
      var.vdc_config["iaas_spoke_data_subnet"],
      var.vdc_config["hub_mgmt_subnet"],
      var.vdc_config["vpn_range"]
    ]

    target_fqdns               = [
      "*.chocolatey.org",
      "*.nuget.org",
      "*.powershellgallery.com",
      "*.ubuntu.com",
      "aka.ms",
      "api.npms.io",
      "chocolatey.org",
      "devopsgallerystorage.blob.core.windows.net",
      "download.microsoft.com",
      "nuget.org",
      "onegetcdn.azureedge.net",
      "packages.microsoft.com",
      "psg-prod-eastus.azureedge.net", # PowerShell
      "registry.npmjs.org",
      "skimdb.npmjs.com",
      azurerm_storage_account.vdc_automation_storage.primary_blob_host # Bastion prepare script
    ]

    protocol {
        port                   = "443"
        type                   = "Https"
    }
  }

  rule {
    name                       = "Allow Bootstrap scripts and tools"
    description                = "Bootstrap scripts are hosted on GitHub, tools on their own locations"

    source_addresses           = [
      var.vdc_config["iaas_spoke_app_subnet"],
      var.vdc_config["iaas_spoke_data_subnet"],
      var.vdc_config["hub_mgmt_subnet"],
      var.vdc_config["vpn_range"]
    ]

    target_fqdns               = [
      "*.dlservice.microsoft.com",
      "*.github.com",
      "*.githubusercontent.com",
      "*.hashicorp.com",
      "*.pivotal.io",
      "*.smartscreen-prod.microsoft.com",
      "*.typescriptlang.org",
      "*.vo.msecnd.net", # Visual Studio Code
      "azcopy.azureedge.net",
      "azurecliprod.blob.core.windows.net",
      "azuredatastudiobuilds.blob.core.windows.net",
      "dl.pstmn.io", # Postman
      "dl.xamarin.com",
      "download.docker.com",
      "download.elifulkerson.com",
      "download.sysinternals.com",
      "download.visualstudio.com",
      "download.visualstudio.microsoft.com",
      "functionscdn.azureedge.net",
      "get.helm.sh",
      "github-production-release-asset-2e65be.s3.amazonaws.com", 
      "github.com",
      "go.microsoft.com",
      "licensing.mp.microsoft.com",
      "marketplace.visualstudio.com",
      "sqlopsextensions.blob.core.windows.net",
      "visualstudio.microsoft.com",
      "xamarin-downloads.azureedge.net",
      "visualstudio-devdiv-c2s.msedge.net"
    ]

    protocol {
        port                   = "443"
        type                   = "Https"
    }
  }

  rule {
    name                       = "Allow Management traffic by tag"
    description                = "Azure Backup, Diagnostics, Management, Windows Update"

    source_addresses           = [
      var.vdc_config["vdc_range"],
      var.vdc_config["vpn_range"]
    ]

    fqdn_tags                  = [
      "AzureActiveDirectory",
      "AzureBackup",
      "AzureMonitor",
      "MicrosoftActiveProtectionService",
      "WindowsDiagnostics",
      "WindowsUpdate"
    ]
  }

  rule {
    name                       = "Allow Management traffic by url"
    description                = "Diagnostics, Management, Windows Update"

    source_addresses           = [
      var.vdc_config["vdc_range"],
      var.vdc_config["vpn_range"]
    ]

    target_fqdns               = [
      "*.api.cdp.microsoft.com",
      "*.azure-automation.net",
      "*.delivery.mp.microsoft.com",
      "*.do.dsp.mp.microsoft.com",
      "*.events.data.microsoft.com",
      "*.loganalytics.io",
      "*.ods.opinsights.azure.com",
      "*.oms.opinsights.azure.com",
      "*.systemcenteradvisor.com",
      "*.telemetry.microsoft.com",
      "*.update.microsoft.com",
      "*.windowsupdate.com",
      "checkappexec.microsoft.com",
      "management.azure.com",
      "management.core.windows.net",
      "msft.sts.microsoft.com",
      "opinsightsweuomssa.blob.core.windows.net",
      "scadvisor.accesscontrol.windows.net",
      "scadvisorcontent.blob.core.windows.net",
      "scadvisorservice.accesscontrol.windows.net",
      "settings-win.data.microsoft.com",
      "smartscreen-prod.microsoft.com",
      azurerm_storage_account.vdc_diag_storage.primary_blob_host,
      azurerm_log_analytics_workspace.vcd_workspace.portal_url
    ]

    protocol {
        port                   = "443"
        type                   = "Https"
    }
  }

  rule {
    name                       = "Allow selected HTTP traffic"
    description                = "Plain HTTP traffic for some applications that need it"

    source_addresses           = [
      var.vdc_config["vdc_range"],
      var.vdc_config["vpn_range"]
    ]

    target_fqdns               = [
      "*.digicert.com",
    # "adl.windows.com",
      "chocolatey.org",
      "crl.microsoft.com",
      "go.microsoft.com",
      "mscrl.microsoft.com",
      "ocsp.msocsp.com",
      "dl.delivery.mp.microsoft.com", # "Microsoft Edge"
    # "www.microsoft.com",
      "www.msftconnecttest.com"
    ]

    protocol {
        port                   = "80"
        type                   = "Http"
    }
  }
} 

# Inbound port forwarding rules
resource "azurerm_firewall_nat_rule_collection" "iag_nat_rules" {
  name                         = "${azurerm_firewall.iag.name}-fwd-rules"
  azure_firewall_name          = azurerm_firewall.iag.name
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  priority                     = 100
  action                       = "Dnat"

  # Web Application
  rule {
    name                       = "AllowInboudHttp"

    source_addresses           = [
      "*",
    ]

    destination_ports          = [
    # "80",
      "81"
    ]
    destination_addresses      = [
      "${azurerm_public_ip.iag_pip.ip_address}",
    ]

    translated_port            = "80"
    translated_address         = var.vdc_config["iaas_spoke_app_web_lb_address"]
    protocols                  = [
      "TCP",
    ]
  }

  rule {
    name                       = "AllowInboundRDPtoBastion"

    source_addresses           = local.admin_cidr_ranges

    destination_ports          = [
    # "3389", # Default port
      "${local.rdp_port}"
    ]
    destination_addresses      = [
      "${azurerm_public_ip.iag_pip.ip_address}",
    ]

    translated_port            = "3389"
    translated_address         = var.vdc_config["hub_bastion_address"]
    protocols                  = [
      "TCP"
    ]
  }
}
  
resource "azurerm_firewall_network_rule_collection" "iag_net_outbound_rules" {
  name                         = "${azurerm_firewall.iag.name}-net-out-rules"
  azure_firewall_name          = azurerm_firewall.iag.name
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  priority                     = 101
  action                       = "Allow"

  rule {
    name                       = "AllowDNStoGoogleFromAppSubnet"

    source_addresses           = [
      var.vdc_config["iaas_spoke_app_subnet"],
      var.vdc_config["iaas_spoke_data_subnet"],
    ]

    destination_ports          = [
      "53",
    ]
    destination_addresses      = [
      "8.8.8.8",
      "8.8.4.4",
    ]

    protocols                  = [
      "TCP",
      "UDP",
    ]
  }
  
  rule {
    name = "AllowAzureActiveDirectory"

    source_addresses           = [
      var.vdc_config["vdc_range"],
      var.vdc_config["vpn_range"]
    ]

    destination_ports          = [
      "*",
    ]
    destination_addresses      = [
      "AzureActiveDirectory",
    ]

    protocols                  = [
      "TCP",
      "UDP",
    ]
  }    

  rule {
    name = "AllowSqlServer"

    source_addresses           = [
      var.vdc_config["iaas_spoke_app_subnet"],
      var.vdc_config["paas_spoke_appsvc_subnet"],
      var.vdc_config["hub_mgmt_subnet"],
    ]

    destination_ports          = [
      "*",
    ]
    destination_addresses      = [
      "Sql",
    ]

    protocols                  = [
      "TCP",
    ]
  }  


  rule {
    name = "AllowAllOutboundFromAppSubnet"

    source_addresses           = [
      var.vdc_config["iaas_spoke_app_subnet"],
    ]

    destination_ports          = [
      "*",
    ]
    destination_addresses      = [
      "*",
    ]

    protocols                  = [
      "TCP",
      "UDP",
    ]
  }

/*   
  rule {
    name                       = "Allow all Outbound (DEBUG)"

    source_addresses           = [
      "${var.vdc_config["vdc_range"]}"
    ]

    destination_ports          = [
      "*"
    ]
    destination_addresses      = [
      "*", 
    ]

    protocols                  = [
      "Any"
    ]
  } */
}

resource "azurerm_monitor_diagnostic_setting" "iag_pip_logs" {
  name                         = "${azurerm_public_ip.iag_pip.name}-logs"
  target_resource_id           = azurerm_public_ip.iag_pip.id
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

resource "azurerm_monitor_diagnostic_setting" "iag_logs" {
  name                         = "${azurerm_firewall.iag.name}-logs"
  target_resource_id           = azurerm_firewall.iag.id
  storage_account_id           = azurerm_storage_account.vdc_diag_storage.id
  log_analytics_workspace_id   = azurerm_log_analytics_workspace.vcd_workspace.id

  log {
    category                   = "AzureFirewallApplicationRule"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }

  log {
    category                   = "AzureFirewallNetworkRule"
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