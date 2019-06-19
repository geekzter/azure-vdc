resource "random_string" "iag_domain_name_label" {
  length                      = 16
  upper                       = false
  lower                       = true
  number                      = false
  special                     = false
}

resource "azurerm_public_ip" "iag_pip" {
  name                         = "${azurerm_resource_group.vdc_rg.name}-iag-pip"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  allocation_method            = "Static"
  sku                          = "Standard"
  domain_name_label            = "${random_string.iag_domain_name_label.result}"
}

# Workarlound as azurerm_public_ip.iag_pip.fqdn is not exported
data "azurerm_public_ip" "iag_pip_created" {
  name                         = "${azurerm_public_ip.iag_pip.name}"
  resource_group_name          = "${azurerm_public_ip.iag_pip.resource_group_name}"
}

resource "azurerm_dns_cname_record" "iag_pip_cname" {
  name                         = "${lower(var.resource_prefix)}vdciag"
  zone_name                    = "${data.azurerm_dns_zone.vanity_domain.name}"
  resource_group_name          = "${data.azurerm_dns_zone.vanity_domain.resource_group_name}"
  ttl                          = 300
  record                       = "${data.azurerm_public_ip.iag_pip_created.fqdn}"
  depends_on                   = ["azurerm_public_ip.iag_pip"]
} 

resource "azurerm_firewall" "iag" {
  name                         = "${azurerm_resource_group.vdc_rg.name}-iag"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"

  ip_configuration {
    name                       = "iag_ipconfig"
    subnet_id                  = "${azurerm_subnet.iag_subnet.id}"
    public_ip_address_id       = "${azurerm_public_ip.iag_pip.id}"
  }
}

# Outbound domain whitelisting
resource "azurerm_firewall_application_rule_collection" "iag_app_rules" {
  name                         = "${azurerm_firewall.iag.name}-app-rules"
  azure_firewall_name          = "${azurerm_firewall.iag.name}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  priority                     = 200
  action                       = "Allow"

  rule {
    name                       = "Allow ${azurerm_storage_account.app_storage.name} Storage"

    source_addresses           = [
      "${var.vdc_vnet["app_subnet"]}",
      "${var.vdc_vnet["data_subnet"]}",
      "${var.vdc_vnet["mgmt_subnet"]}",
      "${var.vdc_vnet["vpn_range"]}"
    ]

    target_fqdns               = [
      "${azurerm_storage_account.app_storage.primary_blob_host}",
    # "${azurerm_storage_account.app_storage.secondary_blob_host}",
      "${azurerm_storage_account.app_storage.primary_queue_host}",
    # "${azurerm_storage_account.app_storage.secondary_queue_host}",
      "${azurerm_storage_account.app_storage.primary_table_host}",
    # "${azurerm_storage_account.app_storage.secondary_table_host}",
      "${azurerm_storage_account.app_storage.primary_file_host}",
    # "${azurerm_storage_account.app_storage.secondary_file_host}",
      "${azurerm_storage_account.app_storage.primary_dfs_host}",
    # "${azurerm_storage_account.app_storage.secondary_dfs_host}",
      "${azurerm_storage_account.app_storage.primary_web_host}",
    # "${azurerm_storage_account.app_storage.secondary_web_host}",
    ]

    protocol {
        port                   = "443"
        type                   = "Https"
    }
  }

  rule {
    name                       = "Allow ${azurerm_eventhub_namespace.app_eventhub.name} Event Hub HTTPS"

    source_addresses           = [
      "${var.vdc_vnet["app_subnet"]}",
      "${var.vdc_vnet["data_subnet"]}",
      "${var.vdc_vnet["mgmt_subnet"]}",
      "${var.vdc_vnet["vpn_range"]}"
    ]

    target_fqdns               = [
    # "${lower(azurerm_eventhub_namespace.app_eventhub.name)}.servicebus.windows.net", # BUG: Not allowed even though it should match exactly
      "*${lower(azurerm_eventhub_namespace.app_eventhub.name)}.servicebus.windows.net" # HACK: Wildcard does the trick
    ]

    protocol {
        port                   = "443"
        type                   = "Https"
    }
  }

  rule {
    name                       = "Allow Azure DevOps"
    description                = "The VSTS/Azure DevOps agent installed on application VM's requires outbound access. This agent is used by Azure Pipelines for application deployment"

    source_addresses           = [
      "${var.vdc_vnet["app_subnet"]}",
      "${var.vdc_vnet["data_subnet"]}",
      "${var.vdc_vnet["mgmt_subnet"]}",
      "${var.vdc_vnet["vpn_range"]}"
    ]

    target_fqdns               = [
      "vstsagentpackage.azureedge.net",
      "dev.azure.com",
      "*.visualstudio.com",
    ]

    protocol {
        port                   = "443"
        type                   = "Https"
    }
  }
}  

# Outbound IP rules
/* resource "azurerm_firewall_network_rule_collection" "iagnetinrules" {
  name                         = "${azurerm_firewall.iag.name}-NET-IN-RULES-${}"`
  azure_firewall_name          = "${azurerm_firewall.iag.name}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  priority                     = 100
  action                       = "Allow"

}  */

# Inbound port forwarding rules
resource "azurerm_firewall_nat_rule_collection" "iag_nat_rules" {
  name                         = "${azurerm_firewall.iag.name}-fwd-rules"
  azure_firewall_name          = "${azurerm_firewall.iag.name}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
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
      "${data.azurerm_public_ip.iag_pip_created.ip_address}",
    ]

    translated_port            = "80"
    translated_address         = "${var.vdc_vnet["app_web_lb_address"]}"
    protocols                  = [
      "TCP",
    ]
  }

  rule {
    name                       = "AllowInbountRDPtoBastion"

    source_addresses           = "${var.admin_ip_ranges}"

    destination_ports          = [
    # "3389", # Default port
      "${var.rdp_port}"
    ]
    destination_addresses      = [
      "${data.azurerm_public_ip.iag_pip_created.ip_address}",
    ]

    translated_port            = "3389"
    translated_address         = "${var.vdc_vnet["bastion_address"]}"
    protocols                  = [
      "TCP"
    ]
  }
}
  
resource "azurerm_firewall_network_rule_collection" "iag_net_outbound_rules" {
  name                         = "${azurerm_firewall.iag.name}-net-out-rules"
  azure_firewall_name          = "${azurerm_firewall.iag.name}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  priority                     = 101
  action                       = "Allow"

  rule {
    name                       = "AllowDNStoGoogleFromAppSubnet"

    source_addresses           = [
      "${var.vdc_vnet["app_subnet"]}",
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
    name = "AllowAllOutboundFromAppSubnet"

    source_addresses           = [
      "${var.vdc_vnet["app_subnet"]}",
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
      "${var.vdc_vnet["app_subnet"]}",
      "${var.vdc_vnet["data_subnet"]}",
      "${var.vdc_vnet["iag_subnet"]}",
      "${var.vdc_vnet["mgmt_subnet"]}",
      "${var.vdc_vnet["vpn_range"]}"
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
