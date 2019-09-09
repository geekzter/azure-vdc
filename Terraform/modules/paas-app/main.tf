resource "azurerm_storage_account" "app_storage" {
  name                         = "${lower(replace(var.resource_group,"-",""))}storage"
  resource_group_name          = "${var.resource_group}"
  location                     = "${var.location}"
  account_kind                 = "StorageV2"
  account_tier                 = "Standard"
  account_replication_type     = "${var.storage_replication_type}"
 
  network_rules {
    default_action             = "Deny"
    bypass                     = ["Logging","Metrics","AzureServices"] # Logging, Metrics, AzureServices, or None.
    # Without this hole we can't make (automated) changes. Disable it later in the interactive demo
  # ip_rules                   = "${var.admin_ip_ranges}" # BUG: CIDR notation doesn't work as advertised
    ip_rules                   = "${var.admin_ips}" # BUG: CIDR notation doesn't work as advertised
    # Allow the Firewall subnet
    virtual_network_subnet_ids = [
                                 "${var.appsvc_subnet_id}",
                                 "${var.endpoint_subnet_id}"
    ]
  } 

  # HACK: To prevent 'not provisioned. They are in Updating state..'
  #depends_on                   = ["var.endpoint_subnet_id","azurerm_storage_account.archive_storage","azurerm_storage_account.vdc_diag_storage"]

  tags                         = "${var.tags}"
}

resource "azurerm_storage_container" "app_storage_container" {
  name                         = "data"
  storage_account_name         = "${azurerm_storage_account.app_storage.name}"
  container_access_type        = "private"
}

resource "azurerm_storage_blob" "app_storage_blob_sample" {
  name                         = "sample.txt"

  resource_group_name          = "${var.resource_group}"
  storage_account_name         = "${azurerm_storage_account.app_storage.name}"
  storage_container_name       = "${azurerm_storage_container.app_storage_container.name}"

  type                         = "block"
  source                       = "../Data/sample.txt"
}

resource "azurerm_storage_account" "archive_storage" {
  name                         = "${lower(replace(var.resource_group,"-",""))}archive"
  resource_group_name          = "${var.resource_group}"
  location                     = "${var.location}"
  account_kind                 = "StorageV2"
  account_tier                 = "Standard"
  account_replication_type     = "${var.storage_replication_type}"

  depends_on                   = ["var.endpoint_subnet_id"]

  tags                         = "${var.tags}"
}

resource "azurerm_storage_container" "archive_storage_container" {
  name                         = "eventarchive"
  storage_account_name         = "${azurerm_storage_account.archive_storage.name}"
  container_access_type        = "private"
}

resource "azurerm_app_service_plan" "paas_plan" {
  name                         = "${var.resource_group}-appsvc-plan"
  location                     = "${var.location}"
  resource_group_name          = "${var.resource_group}"

  sku {
    tier                       = "PremiumV2"
    size                       = "P1v2"
  }

  tags                         = "${var.tags}"
}

resource "azurerm_app_service" "paas_web_app" {
  name                         = "${var.resource_group}-appsvc-app"
  location                     = "${var.location}"
  resource_group_name          = "${var.resource_group}"
  app_service_plan_id          = "${azurerm_app_service_plan.paas_plan.id}"

  app_settings = {
    "APPINSIGHTS_INSTRUMENTATIONKEY" = "${var.diagnostics_instrumentation_key}"
  }

  identity {
    type                       = "SystemAssigned"
  }

  site_config {
    dotnet_framework_version   = "v4.0"
    ftps_state                 = "Disabled"
    scm_type                   = "LocalGit"
  }

# connection_string {
#   name                       = "MyDbConnection"
#   type                       = "SQLAzure"
# # No secrets in connection string
#   value                      = "Server=tcp:${azurerm_sql_server.app_sqlserver.fully_qualified_domain_name},1433;Database=${azurerm_sql_database.app_sqldb.name};"
# }

  tags                         = "${var.tags}"
}

resource "azurerm_template_deployment" "app_service_network" {
  name                         = "${azurerm_app_service.paas_web_app.name}-network"
  resource_group_name          = "${var.resource_group}"
  deployment_mode              = "Incremental"

  template_body                = "${file("${path.module}/appsvc-network.json")}"

  parameters                   = {
    location                   = "${var.location}"
    functionsAppServicePlanName = "${azurerm_app_service_plan.paas_plan.name}"
    functionsAppServiceAppName = "${azurerm_app_service.paas_web_app.name}"
    integratedVNetId           = "${var.integrated_vnet_id}"
    integratedSubnetName       = "${var.integrated_subnet_name}"
    wafSubnetId                = "${var.waf_subnet_id}"
  }

  depends_on                   = ["azurerm_app_service.paas_web_app"] # Explicit dependency for ARM templates
}

resource "azurerm_eventhub_namespace" "app_eventhub" {
  name                         = "${lower(replace(var.resource_group,"-",""))}eventhubNamespace"
  resource_group_name          = "${var.resource_group}"
  location                     = "${var.location}"
  sku                          = "Standard"
  capacity                     = 1
  kafka_enabled                = false

  # TODO: Service Endpoint support
/*   
  network_rules {
    default_action             = "Deny"
    # Without this hole we can't make (automated) changes. Disable it later in the interactive demo
    ip_rules                   = ["${chomp(data.http.localpublicip.body)}"] # We need this to make changes
    # Allow the Firewall subnet
    virtual_network_subnet_ids = ["${var.endpoint_subnet_id}"]
  }  */

  tags                         = "${var.tags}"
}

resource "azurerm_eventhub" "app_eventhub" {
  name                         = "${lower(replace(var.resource_group,"-",""))}eventhub"
  namespace_name               = "${azurerm_eventhub_namespace.app_eventhub.name}"
  resource_group_name          = "${var.resource_group}"
  partition_count              = 2
  message_retention            = 1

  capture_description {
    enabled                    = true
    encoding                   = "Avro"
    interval_in_seconds        = 60
    destination {
      name                     = "EventHubArchive.AzureBlockBlob"
      archive_name_format      = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      storage_account_id       = "${azurerm_storage_account.archive_storage.id}"
      blob_container_name      = "${azurerm_storage_container.archive_storage_container.name}"
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "eh_logs" {
  name                         = "EventHub_Logs"
  target_resource_id           = "${azurerm_eventhub_namespace.app_eventhub.id}"
  storage_account_id           = "${var.diagnostics_storage_id}"
  log_analytics_workspace_id   = "${var.diagnostics_workspace_id}"

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
Error: Error Creating/Updating Subnet "appservice" (Virtual Network "vdc-dev-xnnm-paas-spoke-network" / Resource Group "vdc-dev-xnnm"): network.SubnetsClient#CreateOrUpdate: Failure sending request: StatusCode=400 -- Original Error: Code="SubnetMissingRequiredDelegation" Message="Subnet /subscriptions/84c1a2c7-585a-4753-ad28-97f69618cf12/resourceGroups/vdc-dev-xnnm/providers/Microsoft.Network/virtualNetworks/vdc-dev-xnnm-paas-spoke-network/subnets/appservice requires any of the following delegation(s) [Microsoft.Web/serverFarms] to reference service association link /subscriptions/84c1a2c7-585a-4753-ad28-97f69618cf12/resourceGroups/vdc-dev-xnnm/providers/Microsoft.Network/virtualNetworks/vdc-dev-xnnm-paas-spoke-network/subnets/appservice/serviceAssociationLinks/AppServiceLink." Details=[] 
*/