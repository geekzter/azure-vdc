resource random_string password {
  length                       = 12
  upper                        = true
  lower                        = true
  number                       = true
  special                      = true
# override_special             = "!@#$%&*()-_=+[]{}<>:?" # default
# Avoid characters that may cause shell scripts to break
  override_special             = "." 
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

data azurerm_client_config current {}
data azurerm_subscription primary {}
data azurerm_container_registry vdc_images {
  name                         = var.container_registry
  resource_group_name          = var.shared_resources_group

  count                        = var.container_registry != null ? 1 : 0
}

locals {
  aad_auth_client_id           = var.aad_auth_client_id_map != null ? lookup(var.aad_auth_client_id_map, "${terraform.workspace}_client_id", null) : null
  admin_ips                    = "${tolist(var.admin_ips)}"
  admin_login_ps               = var.admin_login != null ? var.admin_login : "$null"
  admin_object_id_ps           = var.admin_object_id != null ? var.admin_object_id : "$null"
  # Last element of resource id is resource name
  integrated_vnet_name         = "${element(split("/",var.integrated_vnet_id),length(split("/",var.integrated_vnet_id))-1)}"
  integrated_subnet_name       = "${element(split("/",var.integrated_subnet_id),length(split("/",var.integrated_subnet_id))-1)}"
  linux_fx_version             = var.container_registry != null ? "DOCKER|${data.azurerm_container_registry.vdc_images.0.login_server}/${var.container}" : "DOCKER|appsvcsample/python-helloworld:latest"
  resource_group_name_short    = substr(lower(replace(var.resource_group_name,"-","")),0,20)
  password                     = ".Az9${random_string.password.result}"
  vanity_hostname              = var.vanity_fqdn != null ? element(split(".",var.vanity_fqdn),0) : null
  vdc_resource_group_name      = "${element(split("/",var.vdc_resource_group_id),length(split("/",var.vdc_resource_group_id))-1)}"
}

resource azurerm_resource_group app_rg {
  name                         = var.resource_group_name
  location                     = var.location

  tags                         = var.tags
}

resource azurerm_role_assignment demo_admin {
  scope                        = azurerm_resource_group.app_rg.id
  role_definition_name         = "Contributor"
  principal_id                 = var.admin_object_id

  count                        = var.admin_object_id != null ? 1 : 0
}

resource azurerm_storage_account app_storage {
  name                         = "${local.resource_group_name_short}stor"
  location                     = azurerm_resource_group.app_rg.location
  resource_group_name          = azurerm_resource_group.app_rg.name
  account_kind                 = "StorageV2"
  account_tier                 = "Standard"
  account_replication_type     = var.storage_replication_type
  enable_https_traffic_only    = true
 
  # managed with azurerm_storage_account_network_rules
  # network_rules {
  #   default_action             = "Deny"
  #   bypass                     = ["AzureServices","Logging","Metrics"] # Logging, Metrics, AzureServices, or None.
  #   ip_rules                   = var.admin_ip_ranges
  #   # Allow the Firewall subnet
  #   virtual_network_subnet_ids = [
  #                               var.iag_subnet_id,
  #                               var.integrated_subnet_id
  #   ]
  # } 

  provisioner "local-exec" {
    # TODO: Add --auth-mode login once supported
    command                    = "az storage logging update --account-name ${self.name} --log rwd --retention 90 --services b"
  }

  timeouts {
    create                     = var.default_create_timeout
    update                     = var.default_update_timeout
    read                       = var.default_read_timeout
    delete                     = var.default_delete_timeout
  }  

  tags                         = var.tags
  
  depends_on                   = [
                                  azurerm_app_service_virtual_network_swift_connection.network,
                                  # FIX for race condition: Error waiting for Azure Storage Account "vdccipaasappb1375stor" to be created: Future#WaitForCompletion: the number of retries has been exceeded: StatusCode=400 -- Original Error: Code="NetworkAclsValidationFailure" Message="Validation of network acls failure: SubnetsNotProvisioned:Cannot proceed with operation because subnets appservice of the virtual network /subscriptions//resourceGroups/vdc-ci-b1375/providers/Microsoft.Network/virtualNetworks/vdc-ci-b1375-paas-spoke-network are not provisioned. They are in Updating state.."
                                  azurerm_storage_container.archive_storage_container
  ]
}

resource azurerm_private_endpoint app_blob_storage_endpoint {
  name                         = "${azurerm_storage_account.app_storage.name}-blob-endpoint"
  resource_group_name          = azurerm_resource_group.app_rg.name
  location                     = azurerm_resource_group.app_rg.location
  subnet_id                    = var.data_subnet_id

  private_service_connection {
    is_manual_connection       = false
    name                       = "${azurerm_storage_account.app_storage.name}-blob-endpoint-connection"
    private_connection_resource_id = azurerm_storage_account.app_storage.id
    subresource_names          = ["blob"]
  }

  timeouts {
    create                     = var.default_create_timeout
    update                     = var.default_update_timeout
    read                       = var.default_read_timeout
    delete                     = var.default_delete_timeout
  }  

  count                        = var.enable_private_link ? 1 : 0
  tags                         = var.tags
}

resource azurerm_private_dns_a_record app_blob_storage_dns_record {
  name                         = azurerm_storage_account.app_storage.name
  zone_name                    = "privatelink.blob.core.windows.net"
  resource_group_name          = local.vdc_resource_group_name
  ttl                          = 300
  records                      = [azurerm_private_endpoint.app_blob_storage_endpoint.0.private_service_connection[0].private_ip_address]
  tags                         = var.tags

  count                        = var.enable_private_link ? 1 : 0
}
resource azurerm_private_endpoint app_table_storage_endpoint {
  name                         = "${azurerm_storage_account.app_storage.name}-table-endpoint"
  resource_group_name          = azurerm_resource_group.app_rg.name
  location                     = azurerm_resource_group.app_rg.location
  subnet_id                    = var.data_subnet_id

  private_service_connection {
    is_manual_connection       = false
    name                       = "${azurerm_storage_account.app_storage.name}-table-endpoint-connection"
    private_connection_resource_id = azurerm_storage_account.app_storage.id
    subresource_names          = ["table"]
  }

  timeouts {
    create                     = var.default_create_timeout
    update                     = var.default_update_timeout
    read                       = var.default_read_timeout
    delete                     = var.default_delete_timeout
  }  

  tags                         = var.tags

  count                        = var.enable_private_link ? 1 : 0
  # Create Private Endpoints one at a time
  depends_on                   = [azurerm_private_endpoint.app_blob_storage_endpoint]
}
resource azurerm_private_dns_a_record app_table_storage_dns_record {
  name                         = azurerm_storage_account.app_storage.name
  zone_name                    = "privatelink.table.core.windows.net"
  resource_group_name          = local.vdc_resource_group_name
  ttl                          = 300
  records                      = [azurerm_private_endpoint.app_table_storage_endpoint.0.private_service_connection[0].private_ip_address]
  tags                         = var.tags

  count                        = var.enable_private_link ? 1 : 0
}
resource azurerm_advanced_threat_protection app_storage {
  target_resource_id           = azurerm_storage_account.app_storage.id
  enabled                      = true
}

resource azurerm_storage_container app_storage_container {
  name                         = "data"
  storage_account_name         = azurerm_storage_account.app_storage.name
  container_access_type        = "private"

  count                        = var.storage_import ? 1 : 0

# depends_on                   = [azurerm_storage_account_network_rules.app_storage]
}

resource azurerm_storage_blob app_storage_blob_sample {
  name                         = "sample.txt"
  storage_account_name         = azurerm_storage_account.app_storage.name
  storage_container_name       = azurerm_storage_container.app_storage_container.0.name

  type                         = "Block"
  source                       = "../data/sample.txt"

  count                        = var.storage_import ? 1 : 0
}

# Remove all rules once storage account has been populated
resource azurerm_storage_account_network_rules app_storage_rules {
  resource_group_name          = azurerm_resource_group.app_rg.name
  storage_account_name         = azurerm_storage_account.app_storage.name
  default_action               = "Deny"

  depends_on                   = [azurerm_storage_container.app_storage_container,azurerm_storage_blob.app_storage_blob_sample]
}

resource azurerm_storage_account archive_storage {
  name                         = "${local.resource_group_name_short}arch"
  location                     = azurerm_resource_group.app_rg.location
  resource_group_name          = azurerm_resource_group.app_rg.name
  account_kind                 = "StorageV2"
  account_tier                 = "Standard"
  account_replication_type     = var.storage_replication_type
  enable_https_traffic_only    = true

  provisioner local-exec {
    # TODO: Add --auth-mode login once supported
    command                    = "az storage logging update --account-name ${self.name} --log rwd --retention 90 --services b"
  }

  tags                         = var.tags
}

resource azurerm_private_endpoint archive_blob_storage_endpoint {
  name                         = "${azurerm_storage_account.archive_storage.name}-blob-endpoint"
  resource_group_name          = azurerm_resource_group.app_rg.name
  location                     = azurerm_resource_group.app_rg.location
  subnet_id                    = var.data_subnet_id

  private_service_connection {
    is_manual_connection       = false
    name                       = "${azurerm_storage_account.archive_storage.name}-blob-endpoint-connection"
    private_connection_resource_id = azurerm_storage_account.archive_storage.id
    subresource_names          = ["blob"]
  }

  timeouts {
    create                     = var.default_create_timeout
    update                     = var.default_update_timeout
    read                       = var.default_read_timeout
    delete                     = var.default_delete_timeout
  }  

  tags                         = var.tags

  count                        = var.enable_private_link ? 1 : 0
  # Create Private Endpoints one at a time
  depends_on                   = [azurerm_private_endpoint.app_table_storage_endpoint]
}

resource azurerm_private_dns_a_record archive_blob_storage_dns_record {
  name                         = azurerm_storage_account.archive_storage.name
  zone_name                    = "privatelink.blob.core.windows.net"
  resource_group_name          = local.vdc_resource_group_name
  ttl                          = 300
  records                      = [azurerm_private_endpoint.archive_blob_storage_endpoint.0.private_service_connection[0].private_ip_address]
  tags                         = var.tags

  count                        = var.enable_private_link ? 1 : 0
}

resource azurerm_private_endpoint archive_table_storage_endpoint {
  name                         = "${azurerm_storage_account.archive_storage.name}-table-endpoint"
  resource_group_name          = azurerm_resource_group.app_rg.name
  location                     = azurerm_resource_group.app_rg.location
  subnet_id                    = var.data_subnet_id

  private_service_connection {
    is_manual_connection       = false
    name                       = "${azurerm_storage_account.archive_storage.name}-table-endpoint-connection"
    private_connection_resource_id = azurerm_storage_account.archive_storage.id
    subresource_names          = ["table"]
  }

  timeouts {
    create                     = var.default_create_timeout
    update                     = var.default_update_timeout
    read                       = var.default_read_timeout
    delete                     = var.default_delete_timeout
  }  

  tags                         = var.tags

  count                        = var.enable_private_link ? 1 : 0
  # Create Private Endpoints one at a time
  depends_on                   = [azurerm_private_endpoint.archive_blob_storage_endpoint]
}

resource azurerm_private_dns_a_record archive_table_storage_dns_record {
  name                         = azurerm_storage_account.archive_storage.name
  zone_name                    = "privatelink.table.core.windows.net"
  resource_group_name          = local.vdc_resource_group_name
  ttl                          = 300
  records                      = [azurerm_private_endpoint.archive_table_storage_endpoint.0.private_service_connection[0].private_ip_address]
  tags                         = var.tags

  count                        = var.enable_private_link ? 1 : 0
}

resource azurerm_advanced_threat_protection archive_storage {
  target_resource_id           = azurerm_storage_account.archive_storage.id
  enabled                      = true
}

resource azurerm_storage_container archive_storage_container {
  name                         = "eventarchive"
  storage_account_name         = azurerm_storage_account.archive_storage.name
  container_access_type        = "private"
}

resource azurerm_storage_account_network_rules archive_storage_rules {
  resource_group_name          = azurerm_resource_group.app_rg.name
  storage_account_name         = azurerm_storage_account.archive_storage.name
  default_action               = "Deny"
  bypass                       = ["AzureServices"] # Event Hub needs access
  ip_rules                     = [jsondecode(chomp(data.http.localpublicprefix.body)).data.prefix]

  depends_on                   = [azurerm_storage_container.archive_storage_container]
}

resource azurerm_app_service_plan paas_plan {
  name                         = "${var.resource_group_name}-appsvc-plan"
  location                     = azurerm_resource_group.app_rg.location
  resource_group_name          = azurerm_resource_group.app_rg.name

  # Required for containers
  kind                         = "Linux"
  reserved                     = true

  sku {
    tier                       = "PremiumV2"
    size                       = "P1v2"
  }

  tags                         = var.tags
}

# Use user assigned identity, so we can get hold of the Application/Client ID
# This also prevents a bidirectional dependency between App Service & SQL Database
resource azurerm_user_assigned_identity paas_web_app_identity {
  name                         = "${var.resource_group_name}-appsvc-identity"
  location                     = azurerm_resource_group.app_rg.location
  resource_group_name          = azurerm_resource_group.app_rg.name
}

locals {
  # No secrets in connection string
  sql_connection_string        = "Server=tcp:${azurerm_sql_server.app_sqlserver.fully_qualified_domain_name},1433;Database=${azurerm_sql_database.app_sqldb.name};"
}

resource azurerm_app_service paas_web_app {
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
    ASPNETCORE_ENVIRONMENT     = "Offline"
    ASPNETCORE_URLS            = "http://+:80"

    # Required for containers
    #       https://docs.microsoft.com/en-us/azure/container-registry/container-registry-authentication-managed-identity
    DOCKER_REGISTRY_SERVER_USERNAME = var.container_registry != null ? data.azurerm_container_registry.vdc_images.0.admin_username : ""
    DOCKER_REGISTRY_SERVER_PASSWORD = var.container_registry != null ? data.azurerm_container_registry.vdc_images.0.admin_password : ""
    WEBSITES_ENABLE_APP_SERVICE_STORAGE = false

    WEBSITE_DNS_SERVER         = "168.63.129.16" # Private DNS
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
    value                      = local.sql_connection_string
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

  # Configure more logging with Azure CLI
  provisioner local-exec {
    command                    = "az webapp log config --ids ${self.id} --application-logging true --detailed-error-messages true --failed-request-tracing true"
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
    linux_fx_version           = local.linux_fx_version
    # LocalGit removed since using containers for deployment
    scm_type                   = "None"
  }

  # Ignore container updates, those are deployed independently
  lifecycle {
    ignore_changes = [
      site_config.0.linux_fx_version, # deployments are made outside of Terraform
    ]
  }

  tags                         = var.tags
}

resource azurerm_dns_cname_record verify_record {
  name                         = "awverify.${local.vanity_hostname}"
  zone_name                    = var.vanity_domainname
  resource_group_name          = element(split("/",var.vanity_dns_zone_id),length(split("/",var.vanity_dns_zone_id))-5)
  ttl                          = 300
  record                       = "awverify.${replace(azurerm_app_service.paas_web_app.default_site_hostname,"www.","")}"

  count                        = var.vanity_fqdn != null ? 1 : 0
  tags                         = var.tags
} 
resource azurerm_dns_cname_record app_service_alias {
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

# https://docs.microsoft.com/en-us/azure/app-service/networking/private-endpoint
resource azurerm_private_endpoint app_service_endpoint {
  name                         = "${azurerm_app_service.paas_web_app.name}-endpoint"
  resource_group_name          = azurerm_resource_group.app_rg.name
  location                     = azurerm_resource_group.app_rg.location
  subnet_id                    = var.app_subnet_id

  private_service_connection {
    is_manual_connection       = false
    name                       = "${azurerm_app_service.paas_web_app.name}-endpoint-connection"
    private_connection_resource_id = azurerm_app_service.paas_web_app.id
    subresource_names          = ["sites"]
  }

  tags                         = var.tags
  count                        = var.enable_private_link ? 1 : 0
}
resource azurerm_private_dns_a_record app_service_dns_record {
  name                         = azurerm_app_service.paas_web_app.name
  zone_name                    = "privatelink.azurewebsites.net"
  resource_group_name          = local.vdc_resource_group_name
  ttl                          = 300
  records                      = [azurerm_private_endpoint.app_service_endpoint[0].private_service_connection[0].private_ip_address]
  tags                         = var.tags
  count                        = var.enable_private_link ? 1 : 0
}
resource azurerm_private_dns_a_record app_service_scm_dns_record {
  name                         = "${azurerm_app_service.paas_web_app.name}.scm"
  zone_name                    = "privatelink.azurewebsites.net"
  resource_group_name          = local.vdc_resource_group_name
  ttl                          = 300
  records                      = [azurerm_private_endpoint.app_service_endpoint[0].private_service_connection[0].private_ip_address]
  tags                         = var.tags
  count                        = var.enable_private_link ? 1 : 0
}

resource azurerm_monitor_diagnostic_setting app_service_logs {
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
}

### Event Hub
resource azurerm_eventhub_namespace app_eventhub {
  name                         = "${lower(replace(var.resource_group_name,"-",""))}eventhubnamespace"
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
      ip_mask                  = jsondecode(chomp(data.http.localpublicprefix.body)).data.prefix # We need this to make changes
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

  depends_on                   = [azurerm_app_service_virtual_network_swift_connection.network]
}

resource azurerm_eventhub app_eventhub {
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

  depends_on                   = [azurerm_storage_account_network_rules.app_storage_rules]
}
# Private endpoint connections on Event Hubs are only supported by namespaces created under a dedicated cluster
# resource azurerm_private_endpoint eventhub_endpoint {
#   name                         = "${azurerm_eventhub_namespace.app_eventhub.name}-endpoint"
#   resource_group_name          = azurerm_resource_group.app_rg.name
#   location                     = azurerm_resource_group.app_rg.location
#   subnet_id                    = var.data_subnet_id

#   private_service_connection {
#     is_manual_connection       = false
#     name                       = "${azurerm_eventhub_namespace.app_eventhub.name}-endpoint-connection"
#     private_connection_resource_id = azurerm_eventhub_namespace.app_eventhub.id
#     subresource_names          = ["namespace"]
#   }

#   tags                         = var.tags
# }

# resource azurerm_private_dns_a_record eventhub_dns_record {
#   name                         = azurerm_eventhub_namespace.app_eventhub.name
#   zone_name                    = "privatelink.servicebus.windows.net"
#   resource_group_name          = local.vdc_resource_group_name
#   ttl                          = 300
#   records                      = [azurerm_private_endpoint.eventhub_endpoint.private_service_connection[0].private_ip_address]

#   # Disable public access
#   # provisioner local-exec {
#   #   command                    = "az ..."
#   # }
#   tags                         = var.tags
# }

resource azurerm_monitor_diagnostic_setting eventhub_logs {
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

resource azurerm_sql_server app_sqlserver {
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

resource null_resource enable_sql_public_network_access {
  triggers                     = {
    always                     = timestamp()
  }
  # Enable public access, so Terraform can make changes e.g. from a hosted pipeline
  provisioner local-exec {
    command                    = "az sql server update -n ${azurerm_sql_server.app_sqlserver.name} -g ${azurerm_sql_server.app_sqlserver.resource_group_name} --set publicNetworkAccess='Enabled' --query 'publicNetworkAccess' -o tsv"
  }
}

resource azurerm_sql_firewall_rule tfclient {
  name                         = "TerraformClientRule"
  resource_group_name          = azurerm_resource_group.app_rg.name
  server_name                  = azurerm_sql_server.app_sqlserver.name
  start_ip_address             = chomp(data.http.localpublicip.body)
  end_ip_address               = chomp(data.http.localpublicip.body)

  depends_on                   = [null_resource.enable_sql_public_network_access]
}

resource azurerm_sql_firewall_rule adminclient {
  name                         = "AdminClientRule${count.index}"
  resource_group_name          = azurerm_resource_group.app_rg.name
  server_name                  = azurerm_sql_server.app_sqlserver.name
  start_ip_address             = element(local.admin_ips, count.index)
  end_ip_address               = element(local.admin_ips, count.index)
  depends_on                   = [null_resource.enable_sql_public_network_access]

  count                        = var.enable_private_link ? 0 : length(local.admin_ips)
}

resource azurerm_sql_virtual_network_rule iag_subnet {
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

  count                        = var.enable_private_link ? 0 : 1
  depends_on                   = [null_resource.enable_sql_public_network_access]
}

# https://docs.microsoft.com/en-us/azure/app-service/web-sites-integrate-with-vnet#service-endpoints
resource azurerm_sql_virtual_network_rule appservice_subnet {
  name                         = "AllowAppServiceSubnet"
  resource_group_name          = azurerm_resource_group.app_rg.name
  server_name                  = azurerm_sql_server.app_sqlserver.name
  subnet_id                    = var.integrated_subnet_id

  timeouts {
    create                     = var.default_create_timeout
    update                     = var.default_update_timeout
    read                       = var.default_read_timeout
    delete                     = var.default_delete_timeout
  }  

  count                        = var.enable_private_link && var.disable_public_database_access ? 0 : 1
  depends_on                   = [azurerm_app_service_virtual_network_swift_connection.network]
}

resource azurerm_private_endpoint sqlserver_endpoint {
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

  timeouts {
    create                     = var.default_create_timeout
    update                     = var.default_update_timeout
    read                       = var.default_read_timeout
    delete                     = var.default_delete_timeout
  }  

  provisioner "local-exec" {
    when                       = destroy
    command                    = "az sql server update -n ${replace(self.name,"-endpoint","")} -g ${self.resource_group_name} --set publicNetworkAccess='Enabled' --query 'publicNetworkAccess' -o tsv"
  }

  tags                         = var.tags

  count                        = var.enable_private_link ? 1 : 0
  # Create Private Endpoints one at a time
  #depends_on                   = [azurerm_private_endpoint.archive_table_storage_endpoint]
}
resource azurerm_private_dns_a_record sql_server_dns_record {
  name                         = azurerm_sql_server.app_sqlserver.name
  zone_name                    = "privatelink.database.windows.net"
  resource_group_name          = local.vdc_resource_group_name
  ttl                          = 300
  records                      = [azurerm_private_endpoint.sqlserver_endpoint.0.private_service_connection[0].private_ip_address]

  count                        = var.enable_private_link ? 1 : 0
  tags                         = var.tags
}

resource null_resource disable_sql_public_network_access {
  triggers                     = {
    always                     = timestamp()
  }
  # Disable public access
  provisioner local-exec {
    command                    = "az sql server update -n ${azurerm_sql_server.app_sqlserver.name} -g ${azurerm_sql_server.app_sqlserver.resource_group_name} --set publicNetworkAccess='Disabled' --query 'publicNetworkAccess' -o tsv"
  }

  count                        = var.enable_private_link && var.disable_public_database_access ? 1 : 0
  depends_on                   = [
                                  azurerm_private_dns_a_record.sql_server_dns_record,
                                  azurerm_sql_firewall_rule.tfclient,
                                  null_resource.grant_sql_access
                                 ]
}

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

locals {
  # FIX: Required for Azure Cloud Shell (azurerm_client_config.current.object_id not populated)
  dba_object_id                = data.azurerm_client_config.current.object_id != null && data.azurerm_client_config.current.object_id != "" ? data.azurerm_client_config.current.object_id : data.external.account_info.0.result.object_id
}

# This is for Terraform acting as the AAD DBA (e.g. to execute change scripts)
resource azurerm_sql_active_directory_administrator dba {
  # Configure as Terraform identity as DBA
  server_name                  = azurerm_sql_server.app_sqlserver.name
  resource_group_name          = azurerm_resource_group.app_rg.name
# login                        = "Terraform"
  login                        = local.dba_object_id
  object_id                    = local.dba_object_id
  tenant_id                    = data.azurerm_client_config.current.tenant_id
} 

resource null_resource grant_sql_access {
  # Add App Service MSI and DBA to Database
  provisioner "local-exec" {
    command                    = "../scripts/grant_database_access.ps1 -DBAName ${local.admin_login_ps} -DBAObjectId ${local.admin_object_id_ps} -MSIName ${azurerm_user_assigned_identity.paas_web_app_identity.name} -MSIClientId ${azurerm_user_assigned_identity.paas_web_app_identity.client_id} -SqlDatabaseName ${azurerm_sql_database.app_sqldb.name} -SqlServerFQDN ${azurerm_sql_server.app_sqlserver.fully_qualified_domain_name}"
    interpreter                = ["pwsh", "-nop", "-Command"]
  }

  count                        = var.grant_database_access ? 1 : 0
  # Terraform change scripts require Terraform to be the AAD DBA
  depends_on                   = [azurerm_sql_active_directory_administrator.dba]
}

resource azurerm_sql_database app_sqldb {
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

resource azurerm_monitor_diagnostic_setting sql_database_logs {
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
