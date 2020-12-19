resource azurerm_key_vault vault {
  name                         = "${lower(var.resource_prefix)}-${lower(local.deployment_name)}-vault-${lower(local.suffix)}"
  location                     = azurerm_resource_group.vdc_rg.location
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  tenant_id                    = data.azurerm_client_config.current.tenant_id

  enabled_for_disk_encryption  = true
  purge_protection_enabled     = true
  sku_name                     = "premium"
  soft_delete_enabled          = true
  soft_delete_retention_days   = 7

  # Grant access to self
  access_policy {
    tenant_id                  = data.azurerm_client_config.current.tenant_id
    object_id                  = local.automation_object_id

    key_permissions            = [
                                "create",
                                "get",
                                "delete",
                                "list",
                                "purge",
                                "wrapkey",
                                "unwrapkey"
    ]
    secret_permissions         = [
                                "get",
                                "delete",
                                "purge",
                                "set",
    ]

  }

  # Grant access to admin, if defined
  dynamic "access_policy" {
    for_each = range(var.admin_object_id != null && var.admin_object_id != "" ? 1 : 0) 
    content {
      tenant_id                = data.azurerm_client_config.current.tenant_id
      object_id                = var.admin_object_id

      key_permissions          = [
                                "create",
                                "get",
                                "list",
                                "purge",
      ]

      secret_permissions       = [
                                "purge",
                                "set",
      ]
    }
  }

  dynamic "network_acls" {
    for_each = range(var.restrict_public_access ? 1 : 0) 
    content {
      default_action           = "Deny"
      # When enabled_for_disk_encryption is true, network_acls.bypass must include "AzureServices"
      bypass                   = "AzureServices"
      ip_rules                 = local.admin_cidr_ranges
      virtual_network_subnet_ids = [
                                 azurerm_subnet.iag_subnet.id
      ]
    }
  }

  dynamic "network_acls" {
    for_each = range(var.restrict_public_access ? 0 : 1) 
    content {
      default_action           = "Allow"
      bypass                   = "AzureServices"
    }
  }

  tags                         = local.tags
}
locals {
  key_vault_fqdn               = replace(replace(azurerm_key_vault.vault.vault_uri,"https://",""),"/","")
}

resource azurerm_private_endpoint vault_endpoint {
  name                         = "${azurerm_key_vault.vault.name}-endpoint"
  resource_group_name          = azurerm_virtual_network.hub_vnet.resource_group_name
  location                     = azurerm_virtual_network.hub_vnet.location
  
  subnet_id                    = azurerm_subnet.shared_paas_subnet.id

  private_service_connection {
    is_manual_connection       = false
    name                       = "${azurerm_key_vault.vault.name}-endpoint-connection"
    private_connection_resource_id = azurerm_key_vault.vault.id
    subresource_names          = ["vault"]
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
resource azurerm_private_dns_a_record vault_dns_record {
  name                         = azurerm_key_vault.vault.name
  zone_name                    = azurerm_private_dns_zone.zone["vault"].name
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  ttl                          = 300
  records                      = [azurerm_private_endpoint.vault_endpoint.0.private_service_connection[0].private_ip_address]

  tags                         = local.tags
  count                        = var.enable_private_link ? 1 : 0
}
resource azurerm_monitor_diagnostic_setting key_vault_logs {
  name                         = "${azurerm_key_vault.vault.name}-logs"
  target_resource_id           = azurerm_key_vault.vault.id
  storage_account_id           = azurerm_storage_account.vdc_diag_storage.id
  log_analytics_workspace_id   = azurerm_log_analytics_workspace.vcd_workspace.id

  log {
    category                   = "AuditEvent"
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

resource azurerm_storage_account vdc_automation_storage {
  name                         = "${lower(replace(local.vdc_resource_group,"-",""))}autstorage"
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  location                     = local.automation_location
  account_kind                 = "StorageV2"
  account_tier                 = "Standard"
  account_replication_type     = var.app_storage_replication_type
  allow_blob_public_access     = true # No secrets to hide, just scripts that are also on GitHub
  enable_https_traffic_only    = true

  provisioner "local-exec" {
    # TODO: Add --auth-mode login once supported
    command                    = "az storage logging update --account-name ${self.name} --log rwd --retention 90 --services b"
  }

  tags                         = local.tags
}
resource azurerm_storage_account_network_rules automation_storage_rules {
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  storage_account_name         = azurerm_storage_account.vdc_automation_storage.name
  default_action               = "Deny"
  bypass                       = ["AzureServices"]

  ip_rules                     = [local.ipprefixdata.data.prefix]

  count                        = var.restrict_public_access ? 1 : 0
}
resource azurerm_private_endpoint aut_blob_storage_endpoint {
  name                         = "${azurerm_storage_account.vdc_automation_storage.name}-blob-endpoint"
  resource_group_name          = azurerm_virtual_network.hub_vnet.resource_group_name
  location                     = azurerm_virtual_network.hub_vnet.location
  
  subnet_id                    = azurerm_subnet.shared_paas_subnet.id

  private_service_connection {
    is_manual_connection       = false
    name                       = "${azurerm_storage_account.vdc_automation_storage.name}-blob-endpoint-connection"
    private_connection_resource_id = azurerm_storage_account.vdc_automation_storage.id
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
resource azurerm_private_dns_a_record aut_storage_blob_dns_record {
  name                         = azurerm_storage_account.vdc_automation_storage.name 
  zone_name                    = azurerm_private_dns_zone.zone["blob"].name
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  ttl                          = 300
  records                      = [azurerm_private_endpoint.aut_blob_storage_endpoint.0.private_service_connection[0].private_ip_address]
  tags                         = local.tags

  count                        = var.enable_private_link ? 1 : 0
}
resource azurerm_advanced_threat_protection vdc_automation_storage {
  target_resource_id           = azurerm_storage_account.vdc_automation_storage.id
  enabled                      = true
}
# Requires access to private preview of diagnostic log settings for Azure resource type 'microsoft.storage/storageaccounts', feature flag: 'microsoft.insights/diagnosticsettingpreview':
# https://docs.microsoft.com/en-us/azure/storage/common/monitor-storage
# BUG: https://github.com/terraform-providers/terraform-provider-azurerm/issues/8275
# resource azurerm_monitor_diagnostic_setting automation_storage {
#   name                         = "${azurerm_storage_account.vdc_automation_storage.name}-logs"
#   target_resource_id           = azurerm_storage_account.vdc_automation_storage.id
#   storage_account_id           = azurerm_storage_account.vdc_diag_storage.id
#   log_analytics_workspace_id   = azurerm_log_analytics_workspace.vcd_workspace.id

#   log {
#     category                   = "StorageRead"
#     enabled                    = true

#     retention_policy {
#       enabled                  = false
#     }
#   }

#   count                        = var.enable_storage_diagnostic_setting ? 1 : 0
# }
# HACK: workaround for issue https://github.com/terraform-providers/terraform-provider-azurerm/issues/8275
resource null_resource automation_storage_diagnostic_setting {
  provisioner "local-exec" {
    command                    = "az monitor diagnostic-settings create --resource ${azurerm_storage_account.vdc_automation_storage.id}/blobServices/default --name logsbytfaz --storage-account ${azurerm_storage_account.vdc_diag_storage.id} --workspace ${azurerm_log_analytics_workspace.vcd_workspace.id} --logs '[{\"category\": \"StorageRead\",\"enabled\": true}]' "
  }
  count                        = var.enable_storage_diagnostic_setting ? 1 : 0
}

# Create Private Endpoint for Container Registry (if in the same region)
data azurerm_container_registry vdc_images {
  name                         = var.shared_container_registry
  resource_group_name          = var.shared_resources_group

  count                        = var.shared_container_registry != null ? 1 : 0
}
resource azurerm_private_endpoint container_registry_endpoint {
  name                         = "${lower(var.resource_prefix)}-${lower(local.deployment_name)}-${data.azurerm_container_registry.vdc_images.0.name}-${lower(local.suffix)}-endpoint"
  resource_group_name          = azurerm_virtual_network.hub_vnet.resource_group_name
  location                     = azurerm_virtual_network.hub_vnet.location
  
  subnet_id                    = azurerm_subnet.shared_paas_subnet.id

  private_dns_zone_group {
    name                       = azurerm_private_dns_zone.zone["registry"].name
    private_dns_zone_ids       = [azurerm_private_dns_zone.zone["registry"].id]
  }

  private_service_connection {
    is_manual_connection       = false
    name                       = "${lower(var.resource_prefix)}-${lower(local.deployment_name)}-${data.azurerm_container_registry.vdc_images.0.name}-${lower(local.suffix)}-endpoint-connection"
    private_connection_resource_id = data.azurerm_container_registry.vdc_images.0.id
    subresource_names          = ["registry"]
  }

  timeouts {
    create                     = var.default_create_timeout
    update                     = var.default_update_timeout
    read                       = var.default_read_timeout
    delete                     = var.default_delete_timeout
  }  

  tags                         = local.tags
  count                        = var.shared_container_registry != null ? 1 : 0
  depends_on                   = [azurerm_subnet_route_table_association.shared_paas_subnet_routes]
}