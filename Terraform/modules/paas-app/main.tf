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

data "http" "localpublicip" {
# Get public IP address of the machine running this terraform template
  url                          = "http://ipinfo.io/ip"
# url                          = "https://ipapi.co/ip" 
}

data "azurerm_client_config" "current" {}
data "azurerm_subscription" "primary" {}

locals {
  aad_auth_client_id           = var.aad_auth_client_id_map != null ? lookup(var.aad_auth_client_id_map, "${terraform.workspace}_client_id", null) : null
  admin_ips                    = "${tolist(var.admin_ips)}"
  admin_login_ps               = var.admin_login != null ? var.admin_login : "$null"
  admin_object_id_ps           = var.admin_object_id != null ? var.admin_object_id : "$null"
  # Last element of resource id is resource name
  integrated_vnet_name         = "${element(split("/",var.integrated_vnet_id),length(split("/",var.integrated_vnet_id))-1)}"
  integrated_subnet_name       = "${element(split("/",var.integrated_subnet_id),length(split("/",var.integrated_subnet_id))-1)}"
# linux_fx_version             = "DOCKER|${data.azurerm_container_registry.vdc_images.login_server}/vdc-aspnet-core-sqldb:latest" 
# linux_fx_version             = "DOCKER|${data.azurerm_container_registry.vdc_images.login_server}/vdc/aspnet-core-sqldb:latest" 
# linux_fx_version             = "DOCKER|appsvcsample/python-helloworld:latest"
  resource_group_name_short    = substr(lower(replace(var.resource_group_name,"-","")),0,20)
  password                     = ".Az9${random_string.password.result}"
  vanity_hostname              = var.vanity_fqdn != null ? element(split(".",var.vanity_fqdn),0) : null
  vdc_resource_group_name      = "${element(split("/",var.vdc_resource_group_id),length(split("/",var.vdc_resource_group_id))-1)}"
}

resource "azurerm_resource_group" "app_rg" {
  name                         = var.resource_group_name
  location                     = var.location

  tags                         = var.tags
}

resource "azurerm_role_assignment" "demo_admin" {
  scope                        = azurerm_resource_group.app_rg.id
  role_definition_name         = "Contributor"
  principal_id                 = var.admin_object_id

  count                        = var.admin_object_id != null ? 1 : 0
}

resource "azurerm_storage_account" "app_storage" {
  name                         = "${local.resource_group_name_short}stor"
  location                     = azurerm_resource_group.app_rg.location
  resource_group_name          = azurerm_resource_group.app_rg.name
  account_kind                 = "StorageV2"
  account_tier                 = "Standard"
  account_replication_type     = var.storage_replication_type
  enable_https_traffic_only    = true
 
  # not using azurerm_storage_account_network_rules
  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices","Logging","Metrics","AzureServices"] # Logging, Metrics, AzureServices, or None.
    # Without this hole we can't make (automated) changes. Disable it later in the interactive demo
    ip_rules                   = var.admin_ip_ranges
    # Allow the Firewall subnet
    virtual_network_subnet_ids = [
                                 var.iag_subnet_id,
                                 var.data_subnet_id
    ]
  } 

  provisioner "local-exec" {
    command                    = "../Scripts/enable_storage_logging.ps1 -StorageAccountName ${self.name} -ResourceGroupName ${self.resource_group_name} "
    interpreter                = ["pwsh", "-nop", "-Command"]
  }

  timeouts {
    create                     = var.default_create_timeout
    update                     = var.default_update_timeout
    read                       = var.default_read_timeout
    delete                     = var.default_delete_timeout
  }  

  tags                         = var.tags
  
  # FIX for race condition: Error waiting for Azure Storage Account "vdccipaasappb1375stor" to be created: Future#WaitForCompletion: the number of retries has been exceeded: StatusCode=400 -- Original Error: Code="NetworkAclsValidationFailure" Message="Validation of network acls failure: SubnetsNotProvisioned:Cannot proceed with operation because subnets appservice of the virtual network /subscriptions//resourceGroups/vdc-ci-b1375/providers/Microsoft.Network/virtualNetworks/vdc-ci-b1375-paas-spoke-network are not provisioned. They are in Updating state.."
  depends_on                   = [azurerm_storage_container.archive_storage_container]
}

resource azurerm_advanced_threat_protection app_storage {
  target_resource_id           = azurerm_storage_account.app_storage.id
  enabled                      = true
}

# BUG: Error updating Azure Storage Account Network Rules "vdcdemopaasappr460stor" (Resource Group "vdc-demo-paasapp-r460"): storage.AccountsClient#Update: Failure responding to request: StatusCode=400 -- Original Error: autorest/azure: Service returned an error. Status=400 Code="NetworkAclsValidationFailure" Message="Validation of network acls failure: SubnetsNotProvisioned:Cannot proceed with operation because subnets azurefirewallsubnet of the virtual network /subscriptions/84c1a2c7-585a-4753-ad28-97f69618cf12/resourceGroups/vdc-demo-r460/providers/Microsoft.Network/virtualNetworks/vdc-demo-r460-hub-network are not provisioned. They are in Updating state.."
# resource "azurerm_storage_account_network_rules" "app_storage" {
#   resource_group_name          = azurerm_resource_group.app_rg.name
#   storage_account_name         = azurerm_storage_account.app_storage.name

#   default_action               = "Deny"
#   bypass                       = ["AzureServices","Logging","Metrics","AzureServices"] # Logging, Metrics, AzureServices, or None.
#   # Without this hole we can't make (automated) changes. Disable it later in the interactive demo
#   ip_rules                     = var.admin_ip_ranges
#   # Allow the Firewall subnet
#   virtual_network_subnet_ids   = [
#                                   var.iag_subnet_id,
#                                   var.integrated_subnet_id
#   ]
# }

# BUG: 1.0;2019-11-29T15:10:06.7720881Z;GetContainerProperties;IpAuthorizationError;403;6;6;authenticated;XXXXXXX;XXXXXXX;blob;"https://XXXXXXX.blob.core.windows.net:443/data?restype=container";"/";ad97678d-101e-0016-5ec7-a608d2000000;0;10.139.212.72:44506;2018-11-09;481;0;130;246;0;;;;;;"Go/go1.12.6 (amd64-linux) go-autorest/v13.0.2 tombuildsstuff/giovanni/v0.5.0 storage/2018-11-09";;
resource "azurerm_storage_container" "app_storage_container" {
  name                         = "data"
  storage_account_name         = azurerm_storage_account.app_storage.name
  container_access_type        = "private"

  count                        = var.storage_import ? 1 : 0

# depends_on                   = [azurerm_storage_account_network_rules.app_storage]
}

resource "azurerm_storage_blob" "app_storage_blob_sample" {
  name                         = "sample.txt"
  storage_account_name         = azurerm_storage_account.app_storage.name
  storage_container_name       = azurerm_storage_container.app_storage_container.0.name

  type                         = "Block"
  source                       = "../Data/sample.txt"

  count                        = var.storage_import ? 1 : 0
}

resource "azurerm_storage_account" "archive_storage" {
  name                         = "${local.resource_group_name_short}arch"
  location                     = azurerm_resource_group.app_rg.location
  resource_group_name          = azurerm_resource_group.app_rg.name
  account_kind                 = "StorageV2"
  account_tier                 = "Standard"
  account_replication_type     = var.storage_replication_type
  enable_https_traffic_only    = true

  provisioner "local-exec" {
    command                    = "../Scripts/enable_storage_logging.ps1 -StorageAccountName ${self.name} -ResourceGroupName ${self.resource_group_name} "
    interpreter                = ["pwsh", "-nop", "-Command"]
  }

  tags                         = var.tags
}

resource azurerm_advanced_threat_protection archive_storage {
  target_resource_id           = azurerm_storage_account.archive_storage.id
  enabled                      = true
}

resource "azurerm_storage_container" "archive_storage_container" {
  name                         = "eventarchive"
  storage_account_name         = azurerm_storage_account.archive_storage.name
  container_access_type        = "private"
}

resource "azurerm_app_service_plan" "paas_plan" {
  name                         = "${var.resource_group_name}-appsvc-plan"
  location                     = azurerm_resource_group.app_rg.location
  resource_group_name          = azurerm_resource_group.app_rg.name

  # Required for containers
# kind                         = "Linux"
# reserved                     = true

  sku {
    tier                       = "PremiumV2"
    size                       = "P1v2"
  }

  tags                         = var.tags
}

# Use user assigned identity, so we can get hold of the Application/Client ID
# This also prevents a bidirectional dependency between App Service & SQL Database
resource "azurerm_user_assigned_identity" "paas_web_app_identity" {
  name                         = "${var.resource_group_name}-appsvc-identity"
  location                     = azurerm_resource_group.app_rg.location
  resource_group_name          = azurerm_resource_group.app_rg.name
}

resource "azurerm_app_service" "paas_web_app" {
  name                         = "${var.resource_group_name}-appsvc-app"
  location                     = azurerm_resource_group.app_rg.location
  resource_group_name          = azurerm_resource_group.app_rg.name
  app_service_plan_id          = azurerm_app_service_plan.paas_plan.id

  app_settings = {
    # User assigned ID needs to be provided explicitely, this will be pciked up by the .NET application
    # https://github.com/geekzter/dotnetcore-sqldb-tutorial/blob/master/Data/MyDatabaseContext.cs
    APP_CLIENT_ID              = azurerm_user_assigned_identity.paas_web_app_identity.client_id 
    APPINSIGHTS_INSTRUMENTATIONKEY = var.diagnostics_instrumentation_key
    APPLICATIONINSIGHTS_CONNECTION_STRING = "InstrumentationKey=${var.diagnostics_instrumentation_key}"
    ASPNETCORE_ENVIRONMENT     = "Production"

    # Required for containers
  # # DOCKER_REGISTRY_SERVER_URL = "https://index.docker.io"
  # DOCKER_REGISTRY_SERVER_URL = "https://${data.azurerm_container_registry.vdc_images.login_server}"
  # # TODO: Use MSI
  # #       https://docs.microsoft.com/en-us/azure/container-registry/container-registry-authentication-managed-identity
  # DOCKER_REGISTRY_SERVER_USERNAME = "${data.azurerm_container_registry.vdc_images.admin_username}"
  # DOCKER_REGISTRY_SERVER_PASSWORD = "${data.azurerm_container_registry.vdc_images.admin_password}"
  # WEBSITES_ENABLE_APP_SERVICE_STORAGE = false

    WEBSITE_HTTPLOGGING_RETENTION_DAYS = "90"
    # https://docs.microsoft.com/en-us/azure/app-service/web-sites-integrate-with-vnet#regional-vnet-integration
    WEBSITE_VNET_ROUTE_ALL     = "1"
  }

  dynamic "auth_settings" {
    for_each = range(local.aad_auth_client_id != null ? 1 : 0) 
    content {
      active_directory {
        client_id              = local.aad_auth_client_id
        client_secret          = var.aad_auth_client_id_map["${terraform.workspace}_client_secret"]
      }
      default_provider         = "AzureActiveDirectory"
      enabled                  = var.enable_aad_auth
      issuer                   = "https://sts.windows.net/${data.azurerm_client_config.current.tenant_id}/"
      unauthenticated_client_action = "RedirectToLoginPage"
    }
  }

  connection_string {
    name                       = "MyDbConnection"
    type                       = "SQLAzure"
  # No secrets in connection string
    value                      = "Server=tcp:${azurerm_sql_server.app_sqlserver.fully_qualified_domain_name},1433;Database=${azurerm_sql_database.app_sqldb.name};"
  }

  identity {
    type                       = "UserAssigned"
    identity_ids               = [azurerm_user_assigned_identity.paas_web_app_identity.id]
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
    always_on                  = true # Better demo experience, no warmup needed
    app_command_line           = ""
    default_documents          = [
                                 "default.aspx",
                                 "default.htm",
                                 "index.html"
                                 ]
  # dotnet_framework_version   = "v4.0"
    ftps_state                 = "Disabled"

    ip_restriction {
      virtual_network_subnet_id = var.waf_subnet_id
    }
    dynamic "ip_restriction" {
      for_each = var.management_subnet_ids
      content {
        virtual_network_subnet_id = ip_restriction.value
      }
    }

    # Required for containers
  # linux_fx_version           = local.linux_fx_version
    # LocalGit removed since using containers for deployment
    scm_type                   = "None"
  }

  # Uncomment for container deployment
  # lifecycle {
  #   ignore_changes = [
  #     "site_config.0.linux_fx_version", # deployments are made outside of Terraform
  #   ]
  # }

  tags                         = var.tags

# We can't wait for App Service specific rules due to circular dependency.
# The all rule will be removed after App Service rules and SQL DB have been provisioned
# depends_on                   = [azurerm_sql_firewall_rule.azureall] 
}

resource "azurerm_dns_cname_record" "verify_record" {
  name                         = "awverify.${local.vanity_hostname}"
  zone_name                    = var.vanity_domainname
  resource_group_name          = element(split("/",var.vanity_dns_zone_id),length(split("/",var.vanity_dns_zone_id))-5)
  ttl                          = 300
  record                       = "awverify.${replace(azurerm_app_service.paas_web_app.default_site_hostname,"www.","")}"

  count                        = var.vanity_fqdn != null ? 1 : 0
  tags                         = var.tags
} 
resource "azurerm_dns_cname_record" "app_service_alias" {
  name                         = "${local.vanity_hostname}-appsvc"
  zone_name                    = var.vanity_domainname
  resource_group_name          = element(split("/",var.vanity_dns_zone_id),length(split("/",var.vanity_dns_zone_id))-5)
  ttl                          = 300
  record                       = azurerm_app_service.paas_web_app.default_site_hostname

  count                        = var.vanity_fqdn != null ? 1 : 0
  tags                         = var.tags
} 
resource azurerm_app_service_certificate vanity_ssl {
  name                         = var.vanity_certificate_name
  resource_group_name          = azurerm_app_service.paas_web_app.resource_group_name
  location                     = azurerm_app_service.paas_web_app.location
  pfx_blob                     = filebase64(var.vanity_certificate_path)
  password                     = var.vanity_certificate_password

  count                        = var.vanity_fqdn != null ? 1 : 0
  tags                         = var.tags
}
resource azurerm_app_service_custom_hostname_binding vanity_domain {
  hostname                     = var.vanity_fqdn
  app_service_name             = azurerm_app_service.paas_web_app.name
  resource_group_name          = azurerm_app_service.paas_web_app.resource_group_name

  ssl_state                    = "SniEnabled"
  thumbprint                   = azurerm_app_service_certificate.vanity_ssl.0.thumbprint

  count                        = var.vanity_fqdn != null ? 1 : 0
  depends_on                   = [azurerm_dns_cname_record.verify_record]
}
# This is used for the App GW Probe
resource azurerm_app_service_custom_hostname_binding alias_domain {
  hostname                     = "${azurerm_dns_cname_record.app_service_alias.0.name}.${var.vanity_domainname}"
  app_service_name             = azurerm_app_service.paas_web_app.name
  resource_group_name          = azurerm_app_service.paas_web_app.resource_group_name

  ssl_state                    = "SniEnabled"
  thumbprint                   = azurerm_app_service_certificate.vanity_ssl.0.thumbprint

  count                        = var.vanity_fqdn != null ? 1 : 0
  depends_on                   = [azurerm_dns_cname_record.verify_record]
}

resource "azurerm_monitor_diagnostic_setting" "app_service_logs" {
  name                         = "AppService_Logs"
  target_resource_id           = azurerm_app_service.paas_web_app.id
  storage_account_id           = var.diagnostics_storage_id
  log_analytics_workspace_id   = var.diagnostics_workspace_resource_id

  log {
    category                   = "AppServiceConsoleLogs"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }

  log {
    category                   = "AppServiceHTTPLogs"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }
  
  log {
    category                   = "AppServiceAuditLogs"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }
  
  log {
    category                   = "AppServiceFileAuditLogs"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }
  
  log {
    category                   = "AppServiceAppLogs"
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

# Doesn't work with containers yet
resource azurerm_app_service_virtual_network_swift_connection network {
  app_service_id               = azurerm_app_service.paas_web_app.id
  subnet_id                    = var.integrated_subnet_id

  count                        = var.deploy_app_service_network_integration ? 1 : 0
}

### Event Hub
resource "azurerm_eventhub_namespace" "app_eventhub" {
  name                         = "${lower(replace(var.resource_group_name,"-",""))}eventhubNamespace"
  location                     = azurerm_resource_group.app_rg.location
  resource_group_name          = azurerm_resource_group.app_rg.name
  sku                          = "Standard"
  capacity                     = 1
  # TODO: Zone Redundant
  #zone_redundant               = true

  # Service Endpoint support
  network_rulesets {
    default_action             = "Deny"
    # Without this hole we can't make (automated) changes. Disable it later in the interactive demo                 
    ip_rule {
      action                   = "Allow"
      ip_mask                  = chomp(data.http.localpublicip.body) # We need this to make changes
    }
    # # BUG: There is no variable named "var".
    # dynamic ip_rule {
    #   for_each                 = var.admin_ip_ranges
    #   content {
    #     action                 = "Allow"
    #     ip_mask                = ip_rule.value
    #   }
    # }
    virtual_network_rule {
      # Allow the Firewall subnet
      subnet_id                = var.iag_subnet_id
    }
    virtual_network_rule {
      subnet_id                = var.integrated_subnet_id
    }
  } 

  tags                         = var.tags
}

resource "azurerm_eventhub" "app_eventhub" {
  name                         = "${lower(replace(var.resource_group_name,"-",""))}eventhub"
  namespace_name               = azurerm_eventhub_namespace.app_eventhub.name
  resource_group_name          = azurerm_resource_group.app_rg.name
  partition_count              = 2
  message_retention            = 1

  capture_description {
    enabled                    = true
    encoding                   = "Avro"
    interval_in_seconds        = 60
    destination {
      name                     = "EventHubArchive.AzureBlockBlob"
      archive_name_format      = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      storage_account_id       = azurerm_storage_account.archive_storage.id
      blob_container_name      = azurerm_storage_container.archive_storage_container.name
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "eventhub_logs" {
  name                         = "EventHub_Logs"
  target_resource_id           = azurerm_eventhub_namespace.app_eventhub.id
  storage_account_id           = var.diagnostics_storage_id
  log_analytics_workspace_id   = var.diagnostics_workspace_resource_id

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
  resource_group_name          = azurerm_resource_group.app_rg.name
  location                     = azurerm_resource_group.app_rg.location
  version                      = "12.0"
# Credentials are mandatory, but password is randmon and declared as output variable
  administrator_login          = var.admin_username
  administrator_login_password = local.password
  
  # Doesn't support workspace (yet)
  # extended_auditing_policy {
  #   storage_account_access_key =
  #   storage_endpoint           = 
  # }

  tags                         = var.tags
}

resource "azurerm_sql_firewall_rule" "tfclient" {
  name                         = "TerraformClientRule"
  resource_group_name          = azurerm_resource_group.app_rg.name
  server_name                  = azurerm_sql_server.app_sqlserver.name
  start_ip_address             = chomp(data.http.localpublicip.body)
  end_ip_address               = chomp(data.http.localpublicip.body)
}

resource "azurerm_sql_firewall_rule" "adminclient" {
  name                         = "AdminClientRule${count.index}"
  resource_group_name          = azurerm_resource_group.app_rg.name
  server_name                  = azurerm_sql_server.app_sqlserver.name
  start_ip_address             = element(local.admin_ips, count.index)
  end_ip_address               = element(local.admin_ips, count.index)
  count                        = length(local.admin_ips)
}

resource "azurerm_sql_virtual_network_rule" "iag_subnet" {
  name                         = "AllowAzureFirewallSubnet"
  resource_group_name          = azurerm_resource_group.app_rg.name
  server_name                  = azurerm_sql_server.app_sqlserver.name
  subnet_id                    = var.iag_subnet_id

  timeouts {
    create                     = var.default_create_timeout
    update                     = var.default_update_timeout
    read                       = var.default_read_timeout
    delete                     = var.default_delete_timeout
  }  
}

resource "azurerm_sql_virtual_network_rule" "data_subnet" {
  name                         = "AllowDataSubnet"
  resource_group_name          = azurerm_resource_group.app_rg.name
  server_name                  = azurerm_sql_server.app_sqlserver.name
  subnet_id                    = var.data_subnet_id

  timeouts {
    create                     = var.default_create_timeout
    update                     = var.default_update_timeout
    read                       = var.default_read_timeout
    delete                     = var.default_delete_timeout
  }  
}

resource "azurerm_private_endpoint" "sqlserver_endpoint" {
  name                         = "${azurerm_sql_server.app_sqlserver.name}-endpoint"
  resource_group_name          = azurerm_resource_group.app_rg.name
  location                     = azurerm_resource_group.app_rg.location
  subnet_id                    = var.data_subnet_id

  private_service_connection {
    is_manual_connection       = false
    name                       = "${azurerm_sql_server.app_sqlserver.name}-endpoint-connection"
    private_connection_resource_id = azurerm_sql_server.app_sqlserver.id
    subresource_names          = ["sqlServer"]
  }
}

# Inspired by https://github.com/terraform-providers/terraform-provider-azurerm/issues/3234#issuecomment-491405625
data external account_info {
  program = ["pwsh","-nop","-command","../Scripts/get_user_info.ps1"]
}

locals {
  dba_object_id                = data.azurerm_client_config.current.object_id != null && data.azurerm_client_config.current.object_id != "" ? data.azurerm_client_config.current.object_id : data.external.account_info.result.objectId
}

# This is for Terraform acting as the AAD DBA (e.g. to execute change scripts)
resource "azurerm_sql_active_directory_administrator" "dba" {
  # Configure as Terraform identity as DBA
  server_name                  = azurerm_sql_server.app_sqlserver.name
  resource_group_name          = azurerm_resource_group.app_rg.name
  login                        = "Terraform"
  # BUG: Not populated in Azure Cloud Shell  https://github.com/terraform-providers/terraform-provider-azurerm/issues/6310
# object_id                    = data.azurerm_client_config.current.object_id 
  object_id                    = local.dba_object_id
  tenant_id                    = data.azurerm_client_config.current.tenant_id
} 

resource null_resource sql_database_access {
  # Add App Service MSI and DBA to Database
  provisioner "local-exec" {
    command                    = "../Scripts/grant_database_access.ps1 -DBAName ${local.admin_login_ps} -DBAObjectId ${local.admin_object_id_ps} -MSIName ${azurerm_user_assigned_identity.paas_web_app_identity.name} -MSIClientId ${azurerm_user_assigned_identity.paas_web_app_identity.client_id} -SqlDatabaseName ${azurerm_sql_database.app_sqldb.name} -SqlServerFQDN ${azurerm_sql_server.app_sqlserver.fully_qualified_domain_name}"
    interpreter                = ["pwsh", "-nop", "-Command"]
  }

  # Terraform change scripts require Terraform to be the AAD DBA
  depends_on                   = [azurerm_sql_active_directory_administrator.dba]
}

resource "azurerm_sql_database" "app_sqldb" {
  name                         = "${lower(replace(var.resource_group_name,"-",""))}sqldb"
  resource_group_name          = azurerm_resource_group.app_rg.name
  location                     = azurerm_resource_group.app_rg.location
  server_name                  = azurerm_sql_server.app_sqlserver.name
  edition                      = "Premium"

  # Can be enabled through Azure policy instead
  threat_detection_policy {
    state                      = "Enabled"
    use_server_default         = "Enabled"
  }

  zone_redundant               = true

  tags                         = var.tags
} 

resource "azurerm_monitor_diagnostic_setting" "sql_database_logs" {
  name                         = "SqlDatabase_Logs"
  target_resource_id           = azurerm_sql_database.app_sqldb.id
  storage_account_id           = var.diagnostics_storage_id
  log_analytics_workspace_id   = var.diagnostics_workspace_resource_id

  log {
    category                   = "SQLInsights"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }

  log {
    category                   = "AutomaticTuning"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }
  
  log {
    category                   = "QueryStoreRuntimeStatistics"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }
  
  log {
    category                   = "QueryStoreWaitStatistics"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }
  
  log {
    category                   = "Errors"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }  

  log {
    category                   = "DatabaseWaitStatistics"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }  

  log {
    category                   = "Timeouts"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }  

  log {
    category                   = "Blocks"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }  

  log {
    category                   = "Deadlocks"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }  
 
  metric {
    category                   = "Basic"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }  

  metric {
    category                   = "InstanceAndAppAdvanced"

    retention_policy {
      enabled                  = false
    }
  } 
}
