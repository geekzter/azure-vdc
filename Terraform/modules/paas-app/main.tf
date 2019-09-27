resource "random_string" "password" {
  length                       = 12
  upper                        = true
  lower                        = true
  number                       = true
  special                      = true
# override_special             = "!@#$%&*()-_=+[]{}<>:?" # default
# Avoid characters that may cause shell scripts to break
  override_special             = "." 
}

locals {
  admin_ips                    = "${tolist(var.admin_ips)}"
  # Last element of resource id is resource name
  integrated_vnet_name         = "${element(split("/",var.integrated_vnet_id),length(split("/",var.integrated_vnet_id))-1)}"
  integrated_subnet_name       = "${element(split("/",var.integrated_subnet_id),length(split("/",var.integrated_subnet_id))-1)}"
  spoke_vnet_guid_file         = "${path.module}/paas-spoke-vnet-resourceguid.tmp"

  password                     = ".Az9${random_string.password.result}"
  vdc_resource_group_name      = "${element(split("/",var.vdc_resource_group_id),length(split("/",var.vdc_resource_group_id))-1)}"

}

data "http" "localpublicip" {
# Get public IP address of the machine running this terraform template
  url                          = "https://ipinfo.io/ip"
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "app_rg" {
  name                         = "${var.resource_group_name}"
  location                     = "${var.location}"

  tags                         = "${var.tags}"
}

resource "azurerm_storage_account" "app_storage" {
  name                         = "${substr(lower(replace(var.resource_group_name,"-","")),0,20)}stor"
  location                     = "${azurerm_resource_group.app_rg.location}"
  resource_group_name          = "${azurerm_resource_group.app_rg.name}"
  account_kind                 = "StorageV2"
  account_tier                 = "Standard"
  account_replication_type     = "${var.storage_replication_type}"
 
  network_rules {
    default_action             = "Deny"
    bypass                     = ["Logging","Metrics","AzureServices"] # Logging, Metrics, AzureServices, or None.
    # Without this hole we can't make (automated) changes. Disable it later in the interactive demo
    ip_rules                   = "${var.admin_ip_ranges}"
    # Allow the Firewall subnet
    virtual_network_subnet_ids = [
                                 "${var.iag_subnet_id}",
                                 "${var.integrated_subnet_id}"
    ]
  } 

  tags                         = "${var.tags}"
}

### App Service

resource "azurerm_storage_container" "app_storage_container" {
  name                         = "data"
  storage_account_name         = "${azurerm_storage_account.app_storage.name}"
  container_access_type        = "private"
}

resource "azurerm_storage_blob" "app_storage_blob_sample" {
  name                         = "sample.txt"
  storage_account_name         = "${azurerm_storage_account.app_storage.name}"
  storage_container_name       = "${azurerm_storage_container.app_storage_container.name}"

  type                         = "block"
  source                       = "../Data/sample.txt"
}

resource "azurerm_storage_account" "archive_storage" {
  name                         = "${substr(lower(replace(var.resource_group_name,"-","")),0,20)}arch"
  location                     = "${azurerm_resource_group.app_rg.location}"
  resource_group_name          = "${azurerm_resource_group.app_rg.name}"
  account_kind                 = "StorageV2"
  account_tier                 = "Standard"
  account_replication_type     = "${var.storage_replication_type}"

  tags                         = "${var.tags}"
}

resource "azurerm_storage_container" "archive_storage_container" {
  name                         = "eventarchive"
  storage_account_name         = "${azurerm_storage_account.archive_storage.name}"
  container_access_type        = "private"
}

resource "azurerm_app_service_plan" "paas_plan" {
  name                         = "${var.resource_group_name}-appsvc-plan"
  location                     = "${azurerm_resource_group.app_rg.location}"
  resource_group_name          = "${azurerm_resource_group.app_rg.name}"

  sku {
    tier                       = "PremiumV2"
    size                       = "P1v2"
  }

  tags                         = "${var.tags}"

  depends_on                   = ["azurerm_resource_group.app_rg"]
}

resource "azurerm_app_service" "paas_web_app" {
  name                         = "${var.resource_group_name}-appsvc-app"
  location                     = "${azurerm_resource_group.app_rg.location}"
  resource_group_name          = "${azurerm_resource_group.app_rg.name}"
  app_service_plan_id          = "${azurerm_app_service_plan.paas_plan.id}"

  app_settings = {
    "APPINSIGHTS_INSTRUMENTATIONKEY" = "${var.diagnostics_instrumentation_key}"
    "WEBSITE_HTTPLOGGING_RETENTION_DAYS" = "90"
  }

  connection_string {
    name                       = "MyDbConnection"
    type                       = "SQLAzure"
  # No secrets in connection string
    value                      = "Server=tcp:${azurerm_sql_server.app_sqlserver.fully_qualified_domain_name},1433;Database=${azurerm_sql_database.app_sqldb.name};"
  }

  identity {
    type                       = "SystemAssigned"
  }

  logs {
    # application_logs {
    #   azure_blob_storage {
    #     level                    = "Error"
    #     retention_in_days        = 90
    #     # there is currently no means of generating Service SAS tokens with the azurerm provider
    #     sas_url                  = ""
    #   }
    # }
    http_logs {
      # azure_blob_storage {
      #   retention_in_days        = 90
      #   # there is currently no means of generating Service SAS tokens with the azurerm provider
      #   sas_url                  = ""
      # }
      file_system {
        retention_in_days        = 90
        retention_in_mb          = 100
      }
    }
  }

  site_config {
    always_on                  = false
    default_documents          = [
                                 "default.aspx",
                                 "default.htm",
                                 "index.html"
                                 ]
    dotnet_framework_version   = "v4.0"
    ftps_state                 = "Disabled"
    # ip_restriction {
    #   virtual_network_subnet_id = "${var.waf_subnet_id}"
    # }
    scm_type                   = "LocalGit"
  # virtual_network_name       = "${local.integrated_vnet_name}"
  }

  tags                         = "${var.tags}"
}

# Workaround for https://github.com/terraform-providers/terraform-provider-azurerm/issues/2325
# resource "null_resource" "spoke_vnet_guid" {
#   # Changes to any instance of the cluster requires re-provisioning
#   triggers = {
#     allways                    = "${timestamp()}" # Trigger every run
#   # vnet_name                  = "${local.integrated_vnet_name}"
#   }

#   provisioner "local-exec" {
#     # Bootstrap script called with private_ip of each node in the clutser
#     command = "Get-AzVirtualNetwork -Name ${local.integrated_vnet_name} -ResourceGroupName ${local.vdc_resource_group_name} | Select-Object -ExpandProperty ResourceGuid >${local.spoke_vnet_guid_file}"
#     interpreter = ["pwsh", "-c"]
#   }

#   depends_on                   = ["var.integrated_vnet_id"]
# }

# resource "azurerm_template_deployment" "app_service_network_association" {
#   name                         = "${azurerm_app_service.paas_web_app.name}-network-association"
#   resource_group_name          = "${local.vdc_resource_group_name}"
#   deployment_mode              = "Incremental"

#   template_body                = "${file("${path.module}/appsvc-network-association.json")}"

#   parameters                   = {
#     location                   = "${var.location}"
#     addressPrefix              = "${var.integrated_subnet_range}" # Required parameter when updating subnet to add association
#     appServicePlanId           = "${azurerm_app_service_plan.paas_plan.id}"
#     integratedVNetName         = "${local.integrated_vnet_name}"
#     integratedSubnetId         = "${var.integrated_subnet_id}" # Dummy parameter to assure dependency on delegated subnet
#     integratedSubnetName       = "${local.integrated_subnet_name}"
#   }

#   depends_on                   = ["azurerm_app_service.paas_web_app"] # Explicit dependency for ARM templates
# } 

# resource "azurerm_template_deployment" "app_service_network_connection" {
#   name                         = "${azurerm_app_service.paas_web_app.name}-network-connection"
#   resource_group_name          = "${azurerm_resource_group.app_rg.name}"
#   deployment_mode              = "Incremental"

#   template_body                = "${file("${path.module}/appsvc-network-connection.json")}"

#   parameters                   = {
#     location                   = "${azurerm_resource_group.app_rg.location}"
#     functionsAppServiceAppName = "${azurerm_app_service.paas_web_app.name}"
#     integratedVNetId           = "${var.integrated_vnet_id}"
#     integratedSubnetId         = "${var.integrated_subnet_id}" # Dummy parameter to assure dependency on delegated subnet
#     integratedSubnetName       = "${local.integrated_subnet_name}"
#     # Workaround for https://github.com/terraform-providers/terraform-provider-azurerm/issues/2325
#     vnetResourceGuid           = "${trimspace(file(local.spoke_vnet_guid_file))}"
#   }

#   depends_on                   = ["azurerm_app_service.paas_web_app","azurerm_template_deployment.app_service_network_association","null_resource.spoke_vnet_guid"] # Explicit dependency for ARM templates
# }

### Event Hub

resource "azurerm_eventhub_namespace" "app_eventhub" {
  name                         = "${lower(replace(var.resource_group_name,"-",""))}eventhubNamespace"
  location                     = "${azurerm_resource_group.app_rg.location}"
  resource_group_name          = "${azurerm_resource_group.app_rg.name}"
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
  depends_on                   = ["azurerm_resource_group.app_rg"]
}

resource "azurerm_eventhub" "app_eventhub" {
  name                         = "${lower(replace(var.resource_group_name,"-",""))}eventhub"
  namespace_name               = "${azurerm_eventhub_namespace.app_eventhub.name}"
  resource_group_name          = "${azurerm_resource_group.app_rg.name}"
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

### SQL Database

resource "azurerm_sql_server" "app_sqlserver" {
  name                         = "${lower(replace(var.resource_group_name,"-",""))}sqlserver"
  resource_group_name          = "${azurerm_resource_group.app_rg.name}"
  location                     = "${azurerm_resource_group.app_rg.location}"
  version                      = "12.0"
# TODO: Remove credentials, and/or store in Key Vault
  administrator_login          = "${var.admin_username}"
  administrator_login_password = "${local.password}"
  
  tags                         = "${var.tags}"
}

resource "azurerm_sql_firewall_rule" "tfclient" {
  name                         = "TerraformClientRule"
  resource_group_name          = "${azurerm_resource_group.app_rg.name}"
  server_name                  = "${azurerm_sql_server.app_sqlserver.name}"
  start_ip_address             = "${chomp(data.http.localpublicip.body)}"
  end_ip_address               = "${chomp(data.http.localpublicip.body)}"
}

resource "azurerm_sql_firewall_rule" "adminclient" {
  name                         = "AdminClientRule${count.index}"
  resource_group_name          = "${azurerm_resource_group.app_rg.name}"
  server_name                  = "${azurerm_sql_server.app_sqlserver.name}"
  start_ip_address             = "${element(local.admin_ips, count.index)}"
  end_ip_address               = "${element(local.admin_ips, count.index)}"
  count                        = "${length(local.admin_ips)}"
}

# HACK: Not sure why backup restores are initated from this address
resource "azurerm_sql_firewall_rule" "azure1" {
  name                         = "AzureRule1"
  resource_group_name          = "${azurerm_resource_group.app_rg.name}"
  server_name                  = "${azurerm_sql_server.app_sqlserver.name}"
  start_ip_address             = "65.52.129.125"
  end_ip_address               = "65.52.129.125"
}

# Add rule for ${azurerm_app_service.paas_web_app.outbound_ip_addresses} array
# Note these are shared addresses, hence does not fully constrain access
# resource "azurerm_sql_firewall_rule" "webapp" {
#   name                         = "AllowWebApp${count.index}"
#   resource_group_name          = "${azurerm_resource_group.app_rg.name}"
#   server_name                  = "${azurerm_sql_server.app_sqlserver.name}"
#   start_ip_address             = "${element(split(",", azurerm_app_service.paas_web_app.outbound_ip_addresses), count.index)}"
#   end_ip_address               = "${element(split(",", azurerm_app_service.paas_web_app.outbound_ip_addresses), count.index)}"
# # BUG: terraform bug. Throws as an error on first creation: "value of 'count' cannot be computed". Subsequent executions do work.
#   count                        = "${length(split(",", azurerm_app_service.paas_web_app.outbound_ip_addresses))}"
#   depends_on                   = ["azurerm_app_service.paas_web_app"]
# } 

resource "azurerm_sql_firewall_rule" "azureall" {
  name                         = "AllowAllWindowsAzureIPs" # Same name as Azure generated one
  resource_group_name          = "${azurerm_resource_group.app_rg.name}"
  server_name                  = "${azurerm_sql_server.app_sqlserver.name}"
# 0.0.0.0 represents Azure addresses, see https://docs.microsoft.com/en-us/rest/api/sql/firewallrules/createorupdate
  start_ip_address             = "0.0.0.0"
  end_ip_address               = "0.0.0.0"
} 

# TODO: Use AAD group for DBA's, add DBA and TF to that group
resource "azurerm_sql_active_directory_administrator" "dba" {
  server_name                  = "${azurerm_sql_server.app_sqlserver.name}"
  resource_group_name          = "${azurerm_resource_group.app_rg.name}"
  login                        = "${var.dba_login}"
  tenant_id                    = "${data.azurerm_client_config.current.tenant_id}"
  object_id                    = "${var.dba_object_id}" 
}

# Required for SQLCMD
/* resource "azurerm_sql_active_directory_administrator" "tf" {
  server_name                  = "${azurerm_sql_server.app_sqlserver.name}"
  resource_group_name          = "${azurerm_resource_group.app_rg.name}"
  login                        = "tfadmin"
  tenant_id                    = "${data.azurerm_client_config.current.tenant_id}"
  object_id                    = "${data.azurerm_client_config.current.service_principal_object_id}"
} */

/* 
resource "azurerm_sql_active_directory_administrator" "client" {
  server_name                  = "${azurerm_sql_server.app_sqlserver.name}"
  resource_group_name          = "${azurerm_resource_group.app_rg.name}"
  login                        = "${azurerm_app_service.app_appservice.name}"
  tenant_id                    = "${data.azurerm_client_config.current.tenant_id}"
  object_id                    = "${azurerm_app_service.app_appservice.identity.0.principal_id}"
} */

resource "azurerm_sql_database" "app_sqldb" {
  name                         = "${lower(replace(var.resource_group_name,"-",""))}sqldb"
  resource_group_name          = "${azurerm_resource_group.app_rg.name}"
  location                     = "${azurerm_resource_group.app_rg.location}"
  server_name                  = "${azurerm_sql_server.app_sqlserver.name}"
  edition                      = "Premium"

  # Import only works once, this is better moved to an Azure Pipeline Job
  # Error: sql.DatabasesClient#CreateImportOperation: Failure sending request: StatusCode=400 -- Original Error: Code="Failed" Message="The async operation failed." InnerError={"unmarshalError":"json: cannot unmarshal array into Go struct field serviceError2.details of type map[string]interface {}"} AdditionalInfo=[{"code":"0","details":[{"code":"0","message":"There was an error that occurred during this operation : '\u003cstring xmlns=\"http://schemas.microsoft.com/2003/10/Serialization/\"\u003eError encountered during the service operation. ; Exception Microsoft.SqlServer.Management.Dac.Services.ServiceException:Target database is not empty. The import operation can only be performed on an empty database.; \u003c/string\u003e'","severity":"16","target":null}],"innererror":[],"message":"There was an error that occurred during this operation : '\u003cstring xmlns=\"http://schemas.microsoft.com/2003/10/Serialization/\"\u003eError encountered during the service operation. ; Exception Microsoft.SqlServer.Management.Dac.Services.ServiceException:Target database is not empty. The import operation can only be performed on an empty database.; \u003c/string\u003e'","target":null}]
  # database_import

  dynamic "import" {
    for_each = range(var.database_import ? 1 : 0)
    content {
      storage_uri              = "${var.database_template_storage_uri}"
      storage_key              = "${var.database_template_storage_key}"
      storage_key_type         = "StorageAccessKey"
      administrator_login      = "${azurerm_sql_server.app_sqlserver.administrator_login}"
      administrator_login_password = "${azurerm_sql_server.app_sqlserver.administrator_login_password}"
      authentication_type      = "SQL"
    }
  }

  # import {
  #   storage_uri                = "${var.database_template_storage_uri}"
  #   storage_key                = "${var.database_template_storage_key}"
  #   storage_key_type           = "StorageAccessKey"
  #   administrator_login        = "${azurerm_sql_server.app_sqlserver.administrator_login}"
  #   administrator_login_password = "${azurerm_sql_server.app_sqlserver.administrator_login_password}"
  #   authentication_type        = "SQL"
  # }

# Can be enabled through Azure policy instead
  threat_detection_policy {
    state                     = "Enabled"
    use_server_default        = "Enabled"
  }

/* 
# Configure least privilege access for MSI/SPN accessing database
  provisioner "local-exec" {
  # TODO: pass MSI name as argument (${azurerm_app_service.app_appservice.name})
  # Requires AAD auth in order to grant access to (other) AAD objects
    command = "sqlcmd -S ${azurerm_sql_server.app_sqlserver.fully_qualified_domain_name} -d app_paassqldb -U ${var.admin_username} -P ${local.password} -G -i grant-database-access.sql"
  }
*/

  tags                         = "${var.tags}"
} 