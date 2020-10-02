resource random_string iag_domain_name_label {
  length                      = 16
  upper                       = false
  lower                       = true
  number                      = false
  special                     = false
}

resource random_integer rdp_port {
  min     = 1024
  max     = 64000
}

locals {
  rdp_port                     = var.rdp_port != null ? var.rdp_port : random_integer.rdp_port.result
}

resource azurerm_ip_group admin {
  name                         = "${azurerm_resource_group.vdc_rg.name}-ipgroup-admin"
  location                     = azurerm_resource_group.vdc_rg.location
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  cidrs                        = local.admin_cidr_ranges

  tags                         = local.tags
}

resource azurerm_public_ip iag_pip {
  name                         = "${azurerm_resource_group.vdc_rg.name}-iag-pip"
  location                     = azurerm_resource_group.vdc_rg.location
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  allocation_method            = "Static"
  sku                          = "Standard" # Zone redundant
  domain_name_label            = random_string.iag_domain_name_label.result

  tags                         = local.tags
}

resource azurerm_dns_cname_record iag_pip_cname {
  name                         = "${lower(var.resource_prefix)}${lower(terraform.workspace)}iag"
  zone_name                    = data.azurerm_dns_zone.vanity_domain.0.name
  resource_group_name          = data.azurerm_dns_zone.vanity_domain.0.resource_group_name
  ttl                          = 300
  record                       = azurerm_public_ip.iag_pip.fqdn
  depends_on                   = [azurerm_public_ip.iag_pip]

  count                        = var.use_vanity_domain_and_ssl ? 1 : 0
  tags                         = local.tags
} 

resource azurerm_firewall iag {
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
resource azurerm_firewall_application_rule_collection iag_app_rules {
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
    ]

    target_fqdns               = [
      # https://docs.microsoft.com/en-us/azure/devops/pipelines/agents/v2-windows?view=azure-devops
      "*.dev.azure.com",
      "*.pkgs.visualstudio.com",
      "*.visualstudio.com",
      "*.vsassets.io",
      "*.vsblob.visualstudio.com", # Pipeline artifacts
      "*.vsrm.visualstudio.com",
      "*.vssps.visualstudio.com",
      "*.vstmrblob.vsassets.io",
    # "*vsblob*.blob.core.windows.net", # Pipeline artifacts, wildcard not allowed. So instead use:
      "*.blob.core.windows.net", # Pipeline artifacts
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
      var.vdc_config["vdc_range"],
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
      "sqlopsbuilds.azureedge.net", # Data Studio
      "sqlopsextensions.blob.core.windows.net", # Data Studio
      "version.pm2.io",
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
      "*.applicationinsights.io",
      "*.azure-automation.net",
      "*.delivery.mp.microsoft.com",
      "*.do.dsp.mp.microsoft.com",
      "*.events.data.microsoft.com",
      "*.identity.azure.net", # MSI Sidecar
      "*.ingestion.msftcloudes.com",
      "*.loganalytics.io",
      "*.microsoftonline-p.com", # AAD Browser login
      "*.monitoring.azure.com",
      "*.msauth.net", # AAD Browser login
      "*.msftauth.net", # AAD Browser login
      "*.msauthimages.net", # AAD Browser login
      "*.msftauthimages.net", # AAD Browser login
      "*.ods.opinsights.azure.com",
      "*.oms.opinsights.azure.com",
      "*.portal.azure.com",
      "*.portal.azure.net", # Portal images, resources
      "*.systemcenteradvisor.com",
      "*.telemetry.microsoft.com",
      "*.update.microsoft.com",
      "*.windowsupdate.com",
      "checkappexec.microsoft.com",
      "device.login.microsoftonline.com",
      "edge.microsoft.com",
      "enterpriseregistration.windows.net",
      "graph.microsoft.com",
      "ieonline.microsoft.com",
      "login.microsoftonline.com",
      "management.azure.com",
      "management.core.windows.net",
      "msft.sts.microsoft.com",
      "nav.smartscreen.microsoft.com",
      "opinsightsweuomssa.blob.core.windows.net",
      "pas.windows.net",
      "portal.azure.com",
      "scadvisor.accesscontrol.windows.net",
      "scadvisorcontent.blob.core.windows.net",
      "scadvisorservice.accesscontrol.windows.net",
      "settings-win.data.microsoft.com",
      "smartscreen-prod.microsoft.com",
      "sts.windows.net",
      "urs.microsoft.com",
      "validation-v2.sls.microsoft.com",
      "${azurerm_key_vault.vault.name}.vault.azure.net",
      azurerm_log_analytics_workspace.vcd_workspace.portal_url,
      azurerm_storage_account.vdc_diag_storage.primary_blob_host,
      azurerm_storage_account.vdc_diag_storage.primary_table_host
    ]

    protocol {
        port                   = "443"
        type                   = "Https"
    }
  }

  rule {
    name                       = "Allow Application"
    description                = "Diagnostics, Management, Windows Update"

    source_addresses           = [
      var.vdc_config["vdc_range"],
      var.vdc_config["vpn_range"]
    ]

    target_fqdns               = [
        "*.bootstrapcdn.com",
        "cdnjs.cloudflare.com",
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

  # https://docs.microsoft.com/en-us/azure/key-vault/general/whats-new#will-this-affect-me
    target_fqdns               = [
      "*.d-trust.net",
      "*.digicert.com",
    # "adl.windows.com",
      "chocolatey.org",
      "crl.microsoft.com",
      "crl.usertrust.com",
      "go.microsoft.com",
      "mscrl.microsoft.com",
      "ocsp.msocsp.com",
      "ocsp.sectigo.com",
      "ocsp.usertrust.com",
      "oneocsp.microsoft.com",
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
resource azurerm_firewall_nat_rule_collection iag_nat_rules {
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

    source_ip_groups           = [azurerm_ip_group.admin.id]

    destination_ports          = [
    # "3389", # Default port
      "${local.rdp_port}"
    ]
    destination_addresses      = [
      "${azurerm_public_ip.iag_pip.ip_address}",
    ]

    translated_port            = "3389"
    translated_address         = var.vdc_config["hub_mgmt_address"]
    protocols                  = [
      "TCP"
    ]
  }
}
  
resource azurerm_firewall_network_rule_collection iag_net_outbound_rules {
  name                         = "${azurerm_firewall.iag.name}-net-out-rules"
  azure_firewall_name          = azurerm_firewall.iag.name
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  priority                     = 101
  action                       = "Allow"

  rule {
    name                       = "AllowOutboundDNS"

    source_addresses           = [
      var.vdc_config["vdc_range"],
    ]

    destination_ports          = [
      "53",
    ]
    destination_addresses      = [
      "*",
    ]

    protocols                  = [
      "TCP",
      "UDP",
    ]
  }
  
  rule {
    name                       = "AllowAzureActiveDirectory"

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
    name                       = "AllowICMP"

    source_addresses           = [
      var.vdc_config["vdc_range"],
    ]

    destination_ports          = [
      "*",
    ]
    destination_addresses      = [
      "*",
    ]

    protocols                  = [
      "ICMP",
    ]
  }

  rule {
    name                       = "AllowKMS"

    source_addresses           = [
      var.vdc_config["vdc_range"],
    ]

    destination_ports          = [
      "1688",
    ]
    destination_addresses      = [
      "*",
    ]

    protocols                  = [
      "TCP",
    ]
  }

  rule {
    name                       = "AllowNTP"

    source_addresses           = [
      var.vdc_config["vdc_range"],
    ]

    destination_ports          = [
      "123",
    ]
    destination_addresses      = [
      "*",
    ]

    protocols                  = [
      "UDP",
    ]
  }

  rule {
    name                       = "AllowOwneedIPs"

    source_addresses           = [
      var.vdc_config["vdc_range"],
    ]

    destination_ports          = [
      "*",
    ]
    destination_addresses      = [
      azurerm_public_ip.iag_pip.ip_address,
      azurerm_public_ip.waf_pip.ip_address,
      module.p2s_vpn.gateway_ip,
    ]

    protocols                  = [
      "TCP",
      "UDP",
    ]
  }
}

# Rules for API Management
# https://aka.ms/apim-vnet-common-issues
resource azurerm_firewall_application_rule_collection iag_apim_app_rules {
  name                         = "${azurerm_firewall.iag.name}-apim-app-rules"
  azure_firewall_name          = azurerm_firewall.iag.name
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  priority                     = 201
  action                       = "Allow"

  # Allow APIM access to Azure SQL endpoints
  rule {
    name                       = "APIM -> SQL Access"
    description                = "Allow API Management access to Azure SQL endpoints"

    source_addresses           = [
      var.vdc_config["hub_apim_subnet"],
    ]

    target_fqdns               = [
      "*"
    ]

    protocol {
        port                   = "1433"
        type                   = "Mssql"
    }
  }

  rule {
    name                       = "Catch-all APIM HTTP rule"
    description                = "Allow API Management HTTP traffic not covered by one of the documented rules"

    source_addresses           = [
      var.vdc_config["hub_apim_subnet"],
    ]

    target_fqdns               = [
        "*.azureedge.net",
        "*.metrics.nsatc.net",
        "*.monitoring.azure.com",
        "client.hip.live.com",
        "dc.services.visualstudio.com",
        "partner.hip.live.com",
    ]

    protocol {
        port                   = "443"
        type                   = "Https"
    }
  }

  rule {
    name                       = "APIM Metrics rule"
    description                = "Allow metrics traffic to port 1186 (HTTP)"

    source_addresses           = [
      var.vdc_config["hub_apim_subnet"],
    ]

    target_fqdns               = [
        "*.metrics.nsatc.net"
    ]

    protocol {
        port                   = "1886"
        type                   = "Https"
    }
  }

  rule {
    name                       = "Rule for API Demo's"
    description                = "Allow API Management HTTP traffic to demo API's"

    source_addresses           = [
      var.vdc_config["hub_apim_subnet"],
    ]

    target_fqdns               = [
        "echoapi.cloudapp.net",
    ]

    protocol {
        port                   = "80"
        type                   = "Http"
    }
  }

}
# Rules for API Management
# https://aka.ms/apim-vnet-common-issues
data dns_a_record_set apim_smtp_relay1 {
  host                         = "smtpi-co1.msn.com"
}
data dns_a_record_set apim_smtp_relay2 {
  host                         = "smtpi-ch1.msn.com"
}
data dns_a_record_set apim_smtp_relay3 {
  host                         = "smtpi-db3.msn.com"
}
data dns_a_record_set apim_smtp_relay4 {
  host                         = "smtpi-sin.msn.com"
}
resource azurerm_firewall_network_rule_collection iag_net_outbound_apim_rules {
  name                         = "${azurerm_firewall.iag.name}-apim-out-rules"
  azure_firewall_name          = azurerm_firewall.iag.name
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  priority                     = 103
  action                       = "Allow"

  rule {
    name                       = "AllowOutboundStorage"
    source_addresses           = [
      var.vdc_config["hub_apim_subnet"],
    ]
    destination_ports          = [
      "443",
    ]
    destination_addresses      = [
      "*"
    ]
    protocols                  = [
      "TCP"
    ]
  }
  
  rule {
    name                       = "AllowAzureActiveDirectory"
    source_addresses           = [
      var.vdc_config["hub_apim_subnet"],
    ]
    destination_ports          = [
      "443",
    ]
    destination_addresses      = [
      "AzureActiveDirectory",
    ]
    protocols                  = [
      "TCP"
    ]
  }    

  rule {
    name                       = "AllowStorage"
    source_addresses           = [
      var.vdc_config["hub_apim_subnet"],
    ]
    destination_ports          = [
      "443",
      "445",
    ]
    destination_addresses      = [
      "Storage",
    ]
    protocols                  = [
      "TCP"
    ]
  }    

  rule {
    name                       = "AllowHealthMonitoring"
    source_addresses           = [
      var.vdc_config["hub_apim_subnet"],
    ]
    destination_ports          = [
      "443",
      "12000",
    ]
    destination_addresses      = [
      "AzureCloud",
    ]
    protocols                  = [
      "TCP"
    ]
  }    

  rule {
    name                       = "AllowMonitoring"
    source_addresses           = [
      var.vdc_config["hub_apim_subnet"],
    ]
    destination_ports          = [
      "443",
      "1886",
    ]
    destination_addresses      = [
      "AzureMonitor",
    ]
    protocols                  = [
      "TCP"
    ]
  }    

  rule {
    name                       = "AllowSQL"
    source_addresses           = [
      var.vdc_config["hub_apim_subnet"],
    ]
    destination_ports          = [
      "1443",
    ]
    destination_addresses      = [
      "Sql",
    ]
    protocols                  = [
      "TCP"
    ]
  }    

  rule {
    name                       = "AllowEventHub"
    source_addresses           = [
      var.vdc_config["hub_apim_subnet"],
    ]
    destination_ports          = [
      "443",
      "5671",
      "5672",
    ]
    destination_addresses      = [
      "EventHub",
    ]
    protocols                  = [
      "TCP"
    ]
  }    

  rule {
    name                       = "AllowSMTPRelay"
    source_addresses           = [
      var.vdc_config["hub_apim_subnet"],
    ]
    destination_ports          = [
      "25",
      "587",
      "25028",
    ]
    destination_addresses      = concat(
                                        data.dns_a_record_set.apim_smtp_relay1.addrs,
                                        data.dns_a_record_set.apim_smtp_relay2.addrs,
                                        data.dns_a_record_set.apim_smtp_relay3.addrs,
                                        data.dns_a_record_set.apim_smtp_relay4.addrs
    )
    protocols                  = [
      "TCP"
    ]
  }    
}

/*
resource azurerm_firewall_network_rule_collection iag_net_outbound_debug_rules {
  name                         = "${azurerm_firewall.iag.name}-net-out-debug-rules"
  azure_firewall_name          = azurerm_firewall.iag.name
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  priority                     = 999
  action                       = "Allow"


  rule {
    name                       = "DEBUGAllowAllOutbound"

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
  }
}
*/

resource azurerm_monitor_diagnostic_setting iag_pip_logs {
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

resource azurerm_monitor_diagnostic_setting iag_logs {
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