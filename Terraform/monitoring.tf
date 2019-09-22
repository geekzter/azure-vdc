resource "azurerm_storage_account" "vdc_diag_storage" {
  name                         = "${lower(replace(local.vdc_resource_group,"-",""))}storage"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  location                     = "${var.location}"
  account_tier                 = "Standard"
  account_replication_type     = "${var.app_storage_replication_type}"

  tags                         = "${local.tags}"

  depends_on                   = ["azurerm_resource_group.vdc_rg"]
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
  name                         = "${azurerm_virtual_network.hub_vnet.name}-logs"
  target_resource_id           = "${azurerm_virtual_network.hub_vnet.id}"
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




# TODO: Issue with monitoring connections can cause deployment to fail when apply is repeatedly run
resource "azurerm_network_watcher" "vdc_watcher" {
  name                         = "${var.resource_prefix}-watcher"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"

  count                        = "${var.deploy_connection_monitors ? 1 : 0}"  
  tags                         = "${local.tags}"
}

/*
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

*/

resource "azurerm_application_insights" "vdc_insights" {
  name                          = "${azurerm_resource_group.vdc_rg.name}-insights"
  location                      = "${azurerm_log_analytics_workspace.vcd_workspace.location}"
  resource_group_name           = "${azurerm_resource_group.vdc_rg.name}"
  application_type              = "Web"

  tags                         = "${local.tags}"
}