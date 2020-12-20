resource azurerm_storage_account vdc_diag_storage {
  name                         = "${lower(replace(local.vdc_resource_group,"-",""))}diagstor"
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  location                     = var.location
  account_kind                 = "StorageV2"
  account_tier                 = "Standard"
  account_replication_type     = var.app_storage_replication_type
  enable_https_traffic_only    = true

  provisioner "local-exec" {
    # TODO: Add --auth-mode login once supported
    command                    = "az storage logging update --account-name ${self.name} --log rwd --retention 90 --services b"
  }

  network_rules {
    default_action             = "Deny"
    # This is used for diagnostics only
    bypass                     = [
                                  "AzureServices",
                                  "Logging",
                                  "Metrics"
    ]
    ip_rules                   = [local.ipprefix]
  }

  tags                         = local.tags
}

resource azurerm_private_endpoint diag_blob_storage_endpoint {
  name                         = "${azurerm_storage_account.vdc_diag_storage.name}-blob-endpoint"
  resource_group_name          = azurerm_storage_account.vdc_diag_storage.resource_group_name
  location                     = azurerm_storage_account.vdc_diag_storage.location
  
  subnet_id                    = azurerm_subnet.shared_paas_subnet.id

  private_service_connection {
    is_manual_connection       = false
    name                       = "${azurerm_storage_account.vdc_diag_storage.name}-blob-endpoint-connection"
    private_connection_resource_id = azurerm_storage_account.vdc_diag_storage.id
    subresource_names          = ["blob"]
  }

  timeouts {
    create                     = var.default_create_timeout
    update                     = var.default_update_timeout
    read                       = var.default_read_timeout
    delete                     = var.default_delete_timeout
  }  

  tags                         = local.tags
  count                        = var.enable_private_link ? 1 : 0
  depends_on                   = [azurerm_subnet_route_table_association.shared_paas_subnet_routes]
}
resource azurerm_private_dns_a_record diag_storage_blob_dns_record {
  name                         = azurerm_storage_account.vdc_diag_storage.name 
  zone_name                    = azurerm_private_dns_zone.zone["blob"].name
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  ttl                          = 300
  records                      = [azurerm_private_endpoint.diag_blob_storage_endpoint.0.private_service_connection[0].private_ip_address]

  tags                         = var.tags
  count                        = var.enable_private_link ? 1 : 0
}
resource azurerm_private_endpoint diag_table_storage_endpoint {
  name                         = "${azurerm_storage_account.vdc_diag_storage.name}-table-endpoint"
  resource_group_name          = azurerm_storage_account.vdc_diag_storage.resource_group_name
  location                     = azurerm_storage_account.vdc_diag_storage.location
  
  subnet_id                    = azurerm_subnet.shared_paas_subnet.id

  private_service_connection {
    is_manual_connection       = false
    name                       = "${azurerm_storage_account.vdc_diag_storage.name}-table-endpoint-connection"
    private_connection_resource_id = azurerm_storage_account.vdc_diag_storage.id
    subresource_names          = ["table"]
  }

  timeouts {
    create                     = var.default_create_timeout
    update                     = var.default_update_timeout
    read                       = var.default_read_timeout
    delete                     = var.default_delete_timeout
  }  

  tags                         = local.tags
  count                        = var.enable_private_link ? 1 : 0
  depends_on                   = [azurerm_subnet_route_table_association.shared_paas_subnet_routes]
}
resource azurerm_private_dns_a_record diag_storage_table_dns_record {
  name                         = azurerm_storage_account.vdc_diag_storage.name 
  zone_name                    = azurerm_private_dns_zone.zone["table"].name
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  ttl                          = 300
  records                      = [azurerm_private_endpoint.diag_table_storage_endpoint.0.private_service_connection[0].private_ip_address]

  tags                         = var.tags
  count                        = var.enable_private_link ? 1 : 0
}

resource azurerm_advanced_threat_protection vdc_diag_storage {
  target_resource_id           = azurerm_storage_account.vdc_diag_storage.id
  enabled                      = true
}

resource azurerm_log_analytics_workspace vcd_workspace {
  name                         = "${local.vdc_resource_group}-loganalytics"
  # Doesn't deploy in all regions e.g. South India
  location                     = local.workspace_location
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  sku                          = "Standalone"
  retention_in_days            = 90 

  timeouts {
    create                     = var.default_create_timeout
    update                     = var.default_update_timeout
    read                       = var.default_read_timeout
    delete                     = var.default_delete_timeout
  }  

  tags                         = local.tags
  depends_on                   = [
                                  # HACK: Not an actual dependency, but ensures this is available for flow logs, that are also dependent on this workspace
                                  null_resource.network_watcher 
                                 ]
}

resource azurerm_log_analytics_linked_service automation {
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  workspace_id                 = azurerm_log_analytics_workspace.vcd_workspace.id
  read_access_id               = azurerm_automation_account.automation.id

  tags                         = local.tags
}

# List of solutions: https://docs.microsoft.com/en-us/rest/api/loganalytics/workspaces/listintelligencepacks
resource azurerm_log_analytics_solution oms_solutions {
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

resource azurerm_monitor_diagnostic_setting vnet_logs {
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

locals {
  #network_watcher_name         = "NetworkWatcher_${var.location}" # Previous(?) naming convention
  network_watcher_name         = "${var.location}-watcher" # Azure CLI naming convention
  network_watcher_resource_group = "NetworkWatcherRG"
}

resource null_resource network_watcher {
  provisioner "local-exec" {
    command                    = "../scripts/create_network_watcher.ps1 -Location ${var.location} -NetworkWatcherName ${local.network_watcher_name} -ResourceGroupName ${local.network_watcher_resource_group}"
    interpreter                = ["pwsh", "-nop", "-Command"]
  }

  count                        = var.deploy_network_watcher ? 1 : 0
}

resource azurerm_application_insights vdc_insights {
  name                         = "${azurerm_resource_group.vdc_rg.name}-insights"
  location                     = azurerm_log_analytics_workspace.vcd_workspace.location
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  application_type             = "web"

  tags                         = local.tags
}

resource azurerm_dashboard vdc_dashboard {
  name                         = "VDC-${local.deployment_name}-${terraform.workspace}"
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  location                     = azurerm_resource_group.vdc_rg.location
  dashboard_properties = templatefile("dashboard.tpl",
    {
      apim_gw_url              = "${local.apim_gw_url}echo/resource?param1=sample&subscription-key=${try(azurerm_api_management_subscription.echo_subscription.0.primary_key,"")}"
      apim_portal_url          = local.apim_portal_url
      appinsights_id           = azurerm_application_insights.vdc_insights.app_id
      build_web_url            = try(var.build_id != "" ? "https://dev.azure.com/${var.app_devops["account"]}/${var.app_devops["team_project"]}/_build/results?buildId=${var.build_id}" : "https://dev.azure.com/${var.app_devops["account"]}/${var.app_devops["team_project"]}/_build","https://dev.azure.com")
      deployment_name          = local.deployment_name
      iaas_app_url             = local.iaas_app_url
      paas_app_resource_group_short = local.paas_app_resource_group_short
      paas_app_url             = local.paas_app_url
      prefix                   = var.resource_prefix
      release_web_url          = try(var.release_web_url != "" ? var.release_web_url : "https://dev.azure.com/${var.app_devops["account"]}/${var.app_devops["team_project"]}/_release","https://dev.azure.com")
      shared_rg                = var.shared_resources_group
      subscription             = data.azurerm_subscription.primary.id
      subscription_guid        = data.azurerm_subscription.primary.subscription_id
      suffix                   = local.suffix
      vso_url                  = var.vso_url != "" ? var.vso_url : "https://online.visualstudio.com/"
  })

  tags                         = merge(
    local.tags,
    map(
      "hidden-title",           "VDC (${local.deployment_name}/${terraform.workspace})",
    )
  )
}

resource azurerm_monitor_action_group main {
  name                         = "${azurerm_resource_group.vdc_rg.name}-actions"
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  short_name                   = "PushAndEmail"

  azure_app_push_receiver {
    name                       = "pushtoadmin"
    email_address              = var.alert_email
  }
  email_receiver {
    name                       = "sendtoadmin"  
    email_address              = var.alert_email
  }

  tags                         = local.tags
  count                        = var.alert_email != null && var.alert_email != "" ? 1 : 0
}

# resource azurerm_monitor_metric_alert vm_alert {
#   name                         = "${azurerm_resource_group.vdc_rg.name}-vm-alert"
#   resource_group_name          = azurerm_resource_group.vdc_rg.name
# # scopes                       = local.virtual_machine_ids
#   scopes                       = [azurerm_windows_virtual_machine.mgmt.id]
#   description                  = "Action will be triggered when Disk Queue Length is greater than 5."

#   criteria {
#     metric_namespace           = "Azure.VM.Windows.GuestMetrics"
#     metric_name                = "LogicalDisk\\Avg. Disk Queue Length"
#     aggregation                = "Total"
#     operator                   = "GreaterThan"
#     threshold                  = 5

#     dimension {
#       name                     = "Instance"
#       operator                 = "Include"
#       values                   = ["*"]
#     }
#   }

#   action {
#     action_group_id            = azurerm_monitor_action_group.main.0.id
#   }

#   count                        = var.deploy_non_essential_vm_extensions ? 1 : 0
# }