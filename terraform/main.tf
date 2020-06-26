data "azurerm_client_config" "current" {}
data "azurerm_subscription" "primary" {}

# FIX: Required for Azure Cloud Shell (azurerm_client_config.current.object_id not populated)
# HACK: Retrieve user objectId in case it is not exposed in azurerm_client_config.current.object_id
data external account_info {
  program                      = [
                                 "az",
                                 "ad",
                                 "signed-in-user",
                                 "show",
                                 "--query",
                                 "{object_id:objectId}",
                                 "-o",
                                 "json",
                                 ]
  count                        = data.azurerm_client_config.current.object_id != null && data.azurerm_client_config.current.object_id != "" ? 0 : 1
}

data http localpublicip {
# Get public IP address of the machine running this terraform template
  url                          = "http://ipinfo.io/ip"
# url                          = "https://ipapi.co/ip" 
}

data http localpublicprefix {
# Get public IP prefix of the machine running this terraform template
  url                          = "https://stat.ripe.net/data/network-info/data.json?resource=${chomp(data.http.localpublicip.body)}"
}

# Random password generator
resource "random_string" "password" {
  length                       = 12
  upper                        = true
  lower                        = true
  number                       = true
  special                      = true
# override_special             = "!@#$%&*()-_=+[]{}<>:?" # default
# Avoid characters that may cause shell scripts to break
  override_special             = "!@#%*)(-_=+][]}{:?" 
}

# Random resource suffix, this will prevent name collisions when creating resources in parallel
resource "random_string" "suffix" {
  length                       = 4
  upper                        = false
  lower                        = true
  number                       = false
  special                      = false
}

# These variables will be used throughout the Terraform templates
locals {
  # Making sure all character classes are represented, as random does not guarantee that  
  workspace_location           = var.workspace_location != null && var.workspace_location != "" ? var.workspace_location : var.location
  # https://docs.microsoft.com/en-us/azure/automation/how-to/region-mappings
  automation_location          = var.automation_location != null && var.automation_location != "" ? var.automation_location : replace(local.workspace_location,"/eastus$/","eastus2")
  password                     = ".Az9${random_string.password.result}"
# password                     = ".Az9${random_string.password.override_special}" # Test
  suffix                       = var.resource_suffix != "" ? lower(var.resource_suffix) : random_string.suffix.result
  deployment_name              = var.deployment_name != "" ? lower(var.deployment_name) : (length(terraform.workspace) <= 4 ? terraform.workspace : substr(lower(replace(terraform.workspace,"/a|e|i|o|u|y/","")),0,4))
  vdc_resource_group           = "${lower(var.resource_prefix)}-${lower(local.deployment_name)}-${lower(local.suffix)}"
  iaas_app_resource_group      = "${lower(var.resource_prefix)}-${lower(local.deployment_name)}-iaasapp-${lower(local.suffix)}"
  paas_app_resource_group      = "${lower(var.resource_prefix)}-${lower(local.deployment_name)}-paasapp-${lower(local.suffix)}"
  paas_app_resource_group_short= substr(lower(replace(local.paas_app_resource_group,"-","")),0,20)
  ipprefixdata                 = jsondecode(chomp(data.http.localpublicprefix.body))
  admin_ip                     = [
                                  chomp(data.http.localpublicip.body) 
  ]
  admin_ip_cidr                = [
                                  "${chomp(data.http.localpublicip.body)}/30", # /32 not allowed in network_rules
                                  # HACK: Complete prefix required when run from an environment where public ip changes e.g. Azure Pipeline Hosted Agents
                                  local.ipprefixdata.data.prefix 
  ] 
  admin_ips                    = setunion(local.admin_ip,var.admin_ips)
  admin_ip_ranges              = setunion([for ip in local.admin_ips : format("%s/30", ip)],var.admin_ip_ranges) # /32 not allowed in network_rules
  admin_cidr_ranges            = [for range in local.admin_ip_ranges : cidrsubnet(range,0,0)] # Make sure ranges have correct base address
  # FIX: Required for Azure Cloud Shell (azurerm_client_config.current.object_id not populated)
  automation_object_id         = data.azurerm_client_config.current.object_id != null && data.azurerm_client_config.current.object_id != "" ? data.azurerm_client_config.current.object_id : data.external.account_info.0.result.object_id

  tags                         = merge(
    var.tags,
    map(
      "deployment-name",         local.deployment_name,
      "environment",             terraform.workspace,
      "prefix",                  var.resource_prefix,
      "shutdown",                "true",
      "suffix",                  local.suffix,
      "workspace",               terraform.workspace,
      "release-id",              var.release_id,
      "release-url",             var.release_web_url,
      "release-user",            var.release_user_email
    )
  )

  lifecycle                    = {
    ignore_changes             = ["tags"]
  }
}

# Create Azure resource group to be used for VDC resources
resource "azurerm_resource_group" "vdc_rg" {
  name                         = local.vdc_resource_group
  location                     = var.location

  tags                         = local.tags
}

resource "azurerm_role_assignment" "demo_admin" {
  scope                        = azurerm_resource_group.vdc_rg.id
  role_definition_name         = "Contributor"
  principal_id                 = var.admin_object_id

  count                        = var.admin_object_id != null ? 1 : 0
}

resource azurerm_key_vault vault {
  name                         = "${lower(var.resource_prefix)}-${lower(local.deployment_name)}-vault-${lower(local.suffix)}"
  location                     = azurerm_resource_group.vdc_rg.location
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  tenant_id                    = data.azurerm_client_config.current.tenant_id

  enabled_for_disk_encryption  = true
  purge_protection_enabled     = true
  sku_name                     = "premium"
  soft_delete_enabled          = true

  # Grant access to self
  access_policy {
    tenant_id                  = data.azurerm_client_config.current.tenant_id
    object_id                  = local.automation_object_id

    key_permissions            = [
                                "create",
                                "get",
                                "delete",
                                "list",
                                "wrapkey",
                                "unwrapkey"
    ]
    secret_permissions         = [
                                "get",
                                "delete",
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
      ]

      secret_permissions       = [
                                "set",
      ]
    }
  }

  network_acls {
    default_action             = "Deny"
    # When enabled_for_disk_encryption is true, network_acls.bypass must include "AzureServices"
    bypass                     = "AzureServices"
    ip_rules                   = local.admin_cidr_ranges
    virtual_network_subnet_ids = [
                                  azurerm_subnet.iag_subnet.id
    ]
  }

  tags                         = local.tags
}
resource azurerm_private_endpoint vault_endpoint {
  name                         = "${azurerm_key_vault.vault.name}-endpoint"
  resource_group_name          = azurerm_key_vault.vault.resource_group_name
  location                     = azurerm_key_vault.vault.location
  
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

  count                        = var.enable_private_link ? 1 : 0
}
resource azurerm_private_endpoint aut_blob_storage_endpoint {
  name                         = "${azurerm_storage_account.vdc_automation_storage.name}-blob-endpoint"
  resource_group_name          = azurerm_storage_account.vdc_automation_storage.resource_group_name
  location                     = azurerm_storage_account.vdc_automation_storage.location
  
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

# Create Private Endpoint for Container Registry (if in the same region)
data azurerm_container_registry vdc_images {
  name                         = var.shared_container_registry
  resource_group_name          = var.shared_resources_group

  count                        = var.shared_container_registry != null ? 1 : 0
}
resource azurerm_private_endpoint container_registry_endpoint {
  name                         = "${data.azurerm_container_registry.vdc_images.0.name}-endpoint"
  resource_group_name          = data.azurerm_container_registry.vdc_images.0.resource_group_name
  location                     = data.azurerm_container_registry.vdc_images.0.location
  
  subnet_id                    = azurerm_subnet.shared_paas_subnet.id

  private_dns_zone_group {
    name                       = azurerm_private_dns_zone.zone["registry"].name
    private_dns_zone_ids       = [
                                 azurerm_private_dns_zone.zone["registry"].id
    ]
  }

  private_service_connection {
    is_manual_connection       = false
    name                       = "${azurerm_storage_account.vdc_automation_storage.name}-endpoint-connection"
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

  count                        = (var.shared_container_registry != null && data.azurerm_container_registry.vdc_images.0.location == var.location) ? 1 : 0
  depends_on                   = [azurerm_subnet_route_table_association.shared_paas_subnet_routes]
}
