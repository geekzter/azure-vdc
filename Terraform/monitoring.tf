resource "azurerm_storage_account" "vdc_diag_storage" {
  name                         = "${lower(replace(local.vdc_resource_group,"-",""))}diagstor"
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  location                     = var.location
  account_kind                 = "StorageV2"
  account_tier                 = "Standard"
  account_replication_type     = var.app_storage_replication_type
  enable_advanced_threat_protection = true
  enable_blob_encryption       = true
  enable_https_traffic_only    = true


  provisioner "local-exec" {
    command                    = "../Scripts/enable_storage_logging.ps1 -StorageAccountName ${self.name} -ResourceGroupName ${self.resource_group_name} "
    interpreter                = ["pwsh", "-nop", "-Command"]
  }

  tags                         = local.tags
}

resource "azurerm_storage_account" "vdc_automation_storage" {
  name                         = "${lower(replace(local.vdc_resource_group,"-",""))}autstorage"
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  location                     = local.automation_location
  account_kind                 = "StorageV2"
  account_tier                 = "Standard"
  account_replication_type     = var.app_storage_replication_type
  enable_advanced_threat_protection = true
  enable_blob_encryption       = true
  enable_https_traffic_only    = true

  provisioner "local-exec" {
    command                    = "../Scripts/enable_storage_logging.ps1 -StorageAccountName ${self.name} -ResourceGroupName ${self.resource_group_name} "
    interpreter                = ["pwsh", "-nop", "-Command"]
  }

  tags                         = local.tags
}

resource "azurerm_log_analytics_workspace" "vcd_workspace" {
  name                         = "${local.vdc_resource_group}-loganalytics"
  # Doesn't deploy in all regions e.g. South India
  location                     = local.workspace_location
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  sku                          = "Standalone"
  retention_in_days            = 90 

  tags                         = local.tags

  depends_on                   = [
                                  # HACK: Not an actual dependency, but ensures this is available for flow logs, that are also dependent on this workspace
                                  null_resource.network_watcher 
                                 ]
}

resource "azurerm_log_analytics_linked_service" "automation" {
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  workspace_name               = azurerm_log_analytics_workspace.vcd_workspace.name
  resource_id                  = azurerm_automation_account.automation.id

  tags                         = local.tags
}

# List of solutions: https://docs.microsoft.com/en-us/rest/api/loganalytics/workspaces/listintelligencepacks
resource "azurerm_log_analytics_solution" "oms_solutions" {
  solution_name                 = element(var.vdc_oms_solutions, count.index)
  location                      = azurerm_log_analytics_workspace.vcd_workspace.location
  resource_group_name           = azurerm_resource_group.vdc_rg.name
  workspace_resource_id         = azurerm_log_analytics_workspace.vcd_workspace.id
  workspace_name                = azurerm_log_analytics_workspace.vcd_workspace.name

  plan {
    publisher                   = "Microsoft"
    product                     = "OMSGallery/${element(var.vdc_oms_solutions, count.index)}"
  }

  count                         = length(var.vdc_oms_solutions)

  depends_on                    = [azurerm_log_analytics_linked_service.automation]

} 

resource "azurerm_monitor_diagnostic_setting" "mgmt_nsg_logs" {
  name                         = "${azurerm_network_security_group.mgmt_nsg.name}-logs"
  target_resource_id           = azurerm_network_security_group.mgmt_nsg.id
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
resource "azurerm_monitor_diagnostic_setting" "vnet_logs" {
  name                         = "${azurerm_virtual_network.hub_vnet.name}-logs"
  target_resource_id           = azurerm_virtual_network.hub_vnet.id
  storage_account_id           = azurerm_storage_account.vdc_diag_storage.id
  log_analytics_workspace_id   = azurerm_log_analytics_workspace.vcd_workspace.id

  log {
    category                   = "VMProtectionAlerts"
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

# Conflicts with Start/Stop Automation solution
resource "azurerm_monitor_diagnostic_setting" "automation_logs" {
  name                         = "Automation_Logs"
  target_resource_id           = azurerm_automation_account.automation.id
  storage_account_id           = azurerm_storage_account.vdc_automation_storage.id
  log_analytics_workspace_id   = azurerm_log_analytics_workspace.vcd_workspace.id


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

# Check if network watcher exists, there can only be one per region
# data external network_watcher {
#   program                      = ["pwsh", "-nop", "-Command",
#                                   "../Scripts/get_network_watcher.ps1",
#                                   "-Location",azurerm_resource_group.vdc_rg.location,
#                                   "-SubscriptionId",data.azurerm_subscription.primary.subscription_id,
#                                  ]
# }

locals {
  network_watcher_name         = "NetworkWatcher_${var.location}"
  network_watcher_resource_group = "NetworkWatcherRG"
}

resource null_resource network_watcher {
  provisioner "local-exec" {
    command                    = "../Scripts/create_network_watcher.ps1 -Location ${var.location} -NetworkWatcherName ${local.network_watcher_name} -ResourceGroupName ${local.network_watcher_resource_group}"
    interpreter                = ["pwsh", "-nop", "-Command"]
  }

  count                        = var.deploy_network_watcher ? 1 : 0
}

resource "azurerm_application_insights" "vdc_insights" {
  name                         = "${azurerm_resource_group.vdc_rg.name}-insights"
  location                     = azurerm_log_analytics_workspace.vcd_workspace.location
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  application_type             = "Web"

  tags                         = local.tags
}

resource "azurerm_dashboard" "vdc_dashboard" {
  name                         = "VDC-${local.environment}-${terraform.workspace}"
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  location                     = azurerm_resource_group.vdc_rg.location
  tags                         = merge(
    local.tags,
    map(
      "hidden-title",           "VDC (${local.environment}/${terraform.workspace})",
    )
  )

  dashboard_properties = templatefile("dashboard.tpl",
    {
      subscription             = data.azurerm_subscription.primary.id
      prefix                   = var.resource_prefix
      environment              = local.environment
      suffix                   = local.suffix
      subscription_guid        = data.azurerm_subscription.primary.subscription_id
      build_web_url            = var.build_id != "" ? "https://dev.azure.com/${var.app_devops["account"]}/${var.app_devops["team_project"]}/_build/results?buildId=${var.build_id}" : "https://dev.azure.com/${var.app_devops["account"]}/${var.app_devops["team_project"]}/_build"
      iaas_app_url             = local.iaas_app_url
      paas_app_url             = local.paas_app_url
      paas_app_resource_group_short = local.paas_app_resource_group_short
      release_web_url          = var.release_web_url != "" ? var.release_web_url : "https://dev.azure.com/${var.app_devops["account"]}/${var.app_devops["team_project"]}/_release"
      vso_url                  = var.vso_url != "" ? var.vso_url : "https://online.visualstudio.com/"
  })
}