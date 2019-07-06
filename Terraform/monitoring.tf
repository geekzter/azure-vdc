resource "azurerm_storage_account" "vdc_diag_storage" {
  name                         = "${lower(replace(local.vdc_resource_group,"-",""))}storage"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  location                     = "${var.location}"
  account_tier                 = "Standard"
  account_replication_type     = "LRS"

  tags                         = "${local.tags}"
}

resource "azurerm_log_analytics_workspace" "vcd_workspace" {
  name                         = "${local.vdc_resource_group}-loganalytics"
  # Doesn't deploy in all regions e.g. South India
  location                     = "${var.workspace_location}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  sku                          = "Standalone"
  retention_in_days            = 90 

  tags                         = "${local.tags}"
}

resource "azurerm_log_analytics_linked_service" "automation" {
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  workspace_name               = "${azurerm_log_analytics_workspace.vcd_workspace.name}"
  resource_id                  = "${azurerm_automation_account.automation.id}"

  tags                         = "${local.tags}"
}

# List of solutions: https://docs.microsoft.com/en-us/rest/api/loganalytics/workspaces/listintelligencepacks
resource "azurerm_log_analytics_solution" "oms_solutions" {
  solution_name                 = "${element(var.vdc_oms_solutions, count.index)}" 
  location                      = "${azurerm_log_analytics_workspace.vcd_workspace.location}"
  resource_group_name           = "${azurerm_resource_group.vdc_rg.name}"
  workspace_resource_id         = "${azurerm_log_analytics_workspace.vcd_workspace.id}"
  workspace_name                = "${azurerm_log_analytics_workspace.vcd_workspace.name}"

  plan {
    publisher                   = "Microsoft"
    product                     = "OMSGallery/${element(var.vdc_oms_solutions, count.index)}"
  }

  count                         = "${length(var.vdc_oms_solutions)}" 

  depends_on                    = ["azurerm_log_analytics_linked_service.automation"]

} 

resource "azurerm_monitor_diagnostic_setting" "iag_logs" {
  name                         = "${azurerm_firewall.iag.name}-logs"
  target_resource_id           = "${azurerm_firewall.iag.id}"
  storage_account_id           = "${azurerm_storage_account.vdc_diag_storage.id}"
  log_analytics_workspace_id   = "${azurerm_log_analytics_workspace.vcd_workspace.id}"

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

resource "azurerm_monitor_diagnostic_setting" "app_nsg_logs" {
  name                         = "${azurerm_network_security_group.app_nsg.name}-logs"
  target_resource_id           = "${azurerm_network_security_group.app_nsg.id}"
  storage_account_id           = "${azurerm_storage_account.vdc_diag_storage.id}"
  log_analytics_workspace_id   = "${azurerm_log_analytics_workspace.vcd_workspace.id}"

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
resource "azurerm_monitor_diagnostic_setting" "data_nsg_logs" {
  name                         = "${azurerm_network_security_group.data_nsg.name}-logs"
  target_resource_id           = "${azurerm_network_security_group.data_nsg.id}"
  storage_account_id           = "${azurerm_storage_account.vdc_diag_storage.id}"
  log_analytics_workspace_id   = "${azurerm_log_analytics_workspace.vcd_workspace.id}"

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
resource "azurerm_monitor_diagnostic_setting" "mgmt_nsg_logs" {
  name                         = "${azurerm_network_security_group.mgmt_nsg.name}-logs"
  target_resource_id           = "${azurerm_network_security_group.mgmt_nsg.id}"
  storage_account_id           = "${azurerm_storage_account.vdc_diag_storage.id}"
  log_analytics_workspace_id   = "${azurerm_log_analytics_workspace.vcd_workspace.id}"

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
resource "azurerm_monitor_diagnostic_setting" "vnet_logs" {
  name                         = "${azurerm_virtual_network.vnet.name}-logs"
  target_resource_id           = "${azurerm_virtual_network.vnet.id}"
  storage_account_id           = "${azurerm_storage_account.vdc_diag_storage.id}"
  log_analytics_workspace_id   = "${azurerm_log_analytics_workspace.vcd_workspace.id}"

  log {
    category                   = "VMProtectionAlerts"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }
}
resource "azurerm_monitor_diagnostic_setting" "vpn_logs" {
  name                         = "${azurerm_virtual_network_gateway.vpn_gw.0.name}-logs"
  target_resource_id           = "${azurerm_virtual_network_gateway.vpn_gw.0.id}"
  storage_account_id           = "${azurerm_storage_account.vdc_diag_storage.id}"
  log_analytics_workspace_id   = "${azurerm_log_analytics_workspace.vcd_workspace.id}"

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

  count                        = "${var.deploy_vpn ? 1 : 0}"
}
resource "azurerm_monitor_diagnostic_setting" "db_lb_logs" {
  name                         = "${azurerm_lb.app_db_lb.name}-logs"
  target_resource_id           = "${azurerm_lb.app_db_lb.id}"
  storage_account_id           = "${azurerm_storage_account.vdc_diag_storage.id}"
  log_analytics_workspace_id   = "${azurerm_log_analytics_workspace.vcd_workspace.id}"

  log {
    category                   = "LoadBalancerAlertEvent"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }

  log {
    category                   = "LoadBalancerProbeHealthStatus"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "iag_pip_logs" {
  name                         = "${azurerm_public_ip.iag_pip.name}-logs"
  target_resource_id           = "${azurerm_public_ip.iag_pip.id}"
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
resource "azurerm_monitor_diagnostic_setting" "waf_pip_logs" {
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

# Conflicts with Start/Stop Automation solution
resource "azurerm_monitor_diagnostic_setting" "automation_logs" {
  name                         = "Automation_Logs"
  target_resource_id           = "${azurerm_automation_account.automation.id}"
  storage_account_id           = "${azurerm_storage_account.vdc_diag_storage.id}"
  log_analytics_workspace_id   = "${azurerm_log_analytics_workspace.vcd_workspace.id}"


  log {
    category                   = "JobLogs"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }


  log {
    category                   = "JobStreams"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  } 
    
  log {
    category                   = "DscNodeStatus"
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

resource "azurerm_monitor_diagnostic_setting" "eh_logs" {
  name                         = "EventHub_Logs"
  target_resource_id           = "${azurerm_eventhub_namespace.app_eventhub.id}"
  storage_account_id           = "${azurerm_storage_account.vdc_diag_storage.id}"
  log_analytics_workspace_id   = "${azurerm_log_analytics_workspace.vcd_workspace.id}"

  log {
    category                   = "ArchiveLogs"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }

  log {
    category                   = "OperationalLogs"
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

/* 
# TODO: Not yet available for Azure Functions
resource "azurerm_monitor_diagnostic_setting" "vdc_function_logs" {
  name                         = "Function_Logs"
  target_resource_id           = "${azurerm_function_app.vdc_functions.id}"
  storage_account_id           = "${azurerm_storage_account.vdc_diag_storage.id}"
  log_analytics_workspace_id   = "${azurerm_log_analytics_workspace.vcd_workspace.id}"

  log {
    category                   = "FunctionExecutionLogs"
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
} */

# TODO: Issue with monitoring connections can cause deployment to fail when apply is repeatedly run
/* 
resource "azurerm_network_watcher" "vdc_watcher" {
  name                         = "${var.resource_prefix}-watcher"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"

  tags                         = "${local.tags}"
}

resource "azurerm_virtual_machine_extension" "bastion_watcher" {
  name                         = "bastion_watcher"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  virtual_machine_name         = "${azurerm_virtual_machine.bastion.name}"
  publisher                    = "Microsoft.Azure.NetworkWatcher"
  type                         = "NetworkWatcherAgentWindows"
  type_handler_version         = "1.4"
  auto_upgrade_minor_version   = true

  tags                         = "${local.tags}"
}


resource "azurerm_network_connection_monitor" "storage_watcher" {
  name                         = "${azurerm_storage_account.app_storage.name}-watcher"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  network_watcher_name         = "${azurerm_network_watcher.vdc_watcher.name}"

  source {
    virtual_machine_id         = "${azurerm_virtual_machine.bastion.id}"
  }

  destination {
    address                    = "${azurerm_storage_account.app_storage.primary_blob_host}"
    port                       = 443
  }

  depends_on                   = ["azurerm_virtual_machine_extension.bastion_watcher"]

  tags                         = "${local.tags}"
}

resource "azurerm_network_connection_monitor" "eventhub_watcher" {
  name                         = "${azurerm_eventhub_namespace.app_eventhub.name}-watcher"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  network_watcher_name         = "${azurerm_network_watcher.vdc_watcher.name}"

  source {
    virtual_machine_id         = "${azurerm_virtual_machine.bastion.id}"
  }

  destination {
    address                    = "${lower(azurerm_eventhub_namespace.app_eventhub.name)}.servicebus.windows.net"
    port                       = 443
  }

  depends_on                   = ["azurerm_virtual_machine_extension.bastion_watcher"]

  tags                         = "${local.tags}"
} 

resource "azurerm_network_connection_monitor" "devops_watcher" {
  name                         = "${azurerm_resource_group.app_rg.name}-db-vm${count.index}-devops-watcher"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  network_watcher_name         = "${azurerm_network_watcher.vdc_watcher.name}"

  source {
    virtual_machine_id         = "${element(azurerm_virtual_machine.app_db_vm.*.id, count.index)}"
  }

  destination {
    address                    = "vstsagentpackage.azureedge.net"
    port                       = 443
  }
  count                        = 2

  depends_on                   = ["azurerm_virtual_machine_extension.app_db_vm_watcher"]

  tags                         = "${local.tags}"
}
*/

resource "azurerm_application_insights" "vdc_insights" {
  name                          = "${azurerm_resource_group.vdc_rg.name}-insights"
  location                      = "${azurerm_log_analytics_workspace.vcd_workspace.location}"
  resource_group_name           = "${azurerm_resource_group.vdc_rg.name}"
  application_type              = "Web"

  tags                         = "${local.tags}"
}