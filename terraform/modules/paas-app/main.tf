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
  url                          = "https://ipinfo.io/ip"
# url                          = "https://ipapi.co/ip" 
}
data http localpublicprefix {
# Get public IP prefix of the machine running this terraform template
  url                          = "https://stat.ripe.net/data/network-info/data.json?resource=${local.publicip}"
}

data azurerm_subscription primary {}
data azurerm_container_registry vdc_images {
  name                         = var.container_registry
  resource_group_name          = var.shared_resources_group

  count                        = var.container_registry != null ? 1 : 0
}
data azurerm_storage_account diagnostics {
  name                         = local.diagnostics_storage_name
  resource_group_name          = local.vdc_resource_group_name
}

locals {
  aad_auth_client_id           = var.aad_auth_client_id_map != null ? lookup(var.aad_auth_client_id_map, "${terraform.workspace}_client_id", null) : null
  admin_ips                    = tolist(var.admin_ips)
  admin_login_ps               = var.admin_login != null ? var.admin_login : "$null"
  admin_object_id_ps           = var.admin_object_id != null ? var.admin_object_id : "$null"
  app_service_default_documents= [
                                 "default.aspx",
                                 "default.htm",
                                 "index.html"
                                 ]
  app_service_settings         = {
    # User assigned ID needs to be provided explicitely, this will be pciked up by the .NET application
    # https://github.com/geekzter/dotnetcore-sqldb-tutorial/blob/master/Data/MyDatabaseContext.cs
    APP_CLIENT_ID              = azurerm_user_assigned_identity.paas_web_app_identity.client_id 
    APPINSIGHTS_INSTRUMENTATIONKEY = var.diagnostics_instrumentation_key
    APPLICATIONINSIGHTS_CONNECTION_STRING = "InstrumentationKey=${var.diagnostics_instrumentation_key}"
    ASPNETCORE_ENVIRONMENT     = "Online"
    ASPNETCORE_URLS            = "http://+:80"

    # Using ACR admin credentials
    #DOCKER_REGISTRY_SERVER_USERNAME = var.container_registry != null ? data.azurerm_container_registry.vdc_images.0.admin_username : ""
    #DOCKER_REGISTRY_SERVER_PASSWORD = var.container_registry != null ? data.azurerm_container_registry.vdc_images.0.admin_password : ""
    # Using Service Principal credentials
    # https://docs.microsoft.com/en-us/azure/container-registry/container-registry-auth-service-principal
    DOCKER_REGISTRY_SERVER_USERNAME = (var.container_registry != null && var.container_registry_spn_app_id != null) != null ? var.container_registry_spn_app_id : ""
    DOCKER_REGISTRY_SERVER_PASSWORD = (var.container_registry != null && var.container_registry_spn_secret != null) != null ? var.container_registry_spn_secret : ""

    WEBSITES_ENABLE_APP_SERVICE_STORAGE = false # Required for containers

    WEBSITE_DNS_SERVER         = "168.63.129.16" # Private DNS
    WEBSITE_HTTPLOGGING_RETENTION_DAYS = "90"
    # https://docs.microsoft.com/en-us/azure/app-service/web-sites-integrate-with-vnet#regional-vnet-integration
    WEBSITE_VNET_ROUTE_ALL     = "1" # Egress via Hub VNet
  }
  app_service_settings_staging = merge(
    {
    for setting, value in local.app_service_settings : setting => value if setting != "ASPNETCORE_ENVIRONMENT"
    },
    {
      ASPNETCORE_ENVIRONMENT   = "Offline"
    }
  )

  # Last element of resource id is resource name
  diagnostics_storage_name     = element(split("/",var.diagnostics_storage_id),length(split("/",var.diagnostics_storage_id))-1)
  integrated_vnet_name         = element(split("/",var.integrated_vnet_id),length(split("/",var.integrated_vnet_id))-1)
  integrated_subnet_name       = element(split("/",var.integrated_subnet_id),length(split("/",var.integrated_subnet_id))-1)
  linux_fx_version             = var.container_registry != null && var.container != null ? "DOCKER|${data.azurerm_container_registry.vdc_images.0.login_server}/${var.container}" : "DOCKER|appsvcsample/python-helloworld:latest"
  resource_group_name_short    = substr(lower(replace(var.resource_group_name,"-","")),0,20)
  password                     = ".Az9${random_string.password.result}"
  publicip                     = chomp(data.http.localpublicip.body)
  publicprefix                 = jsondecode(chomp(data.http.localpublicprefix.body)).data.prefix
  vanity_hostname              = var.vanity_fqdn != null ? element(split(".",var.vanity_fqdn),0) : null
  vdc_resource_group_name      = element(split("/",var.vdc_resource_group_id),length(split("/",var.vdc_resource_group_id))-1)
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

  tags                         = var.tags
  count                        = var.enable_private_link ? 1 : 0
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
  storage_account_id           = azurerm_storage_account.app_storage.id
  default_action               = "Deny"

  count                        = var.restrict_public_access ? 1 : 0

  depends_on                   = [azurerm_storage_container.app_storage_container,azurerm_storage_blob.app_storage_blob_sample]
}
resource azurerm_monitor_diagnostic_setting app_storage {
  name                         = "${azurerm_storage_account.app_storage.name}-logs"
  target_resource_id           = "${azurerm_storage_account.app_storage.id}/blobServices/default/"
  storage_account_id           = var.diagnostics_storage_id
  log_analytics_workspace_id   = var.diagnostics_workspace_resource_id

  log {
    category                   = "StorageRead"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }

  count                        = var.enable_storage_diagnostic_setting ? 1 : 0
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
  storage_account_id           = azurerm_storage_account.archive_storage.id
  default_action               = "Deny"
  bypass                       = ["AzureServices"] # Event Hub needs access
  ip_rules                     = [local.publicprefix]

  count                        = var.restrict_public_access ? 1 : 0

  depends_on                   = [azurerm_storage_container.archive_storage_container]
}
resource azurerm_monitor_diagnostic_setting archive_storage {
  name                         = "${azurerm_storage_account.archive_storage.name}-logs"
  target_resource_id           = "${azurerm_storage_account.archive_storage.id}/blobServices/default/"
  storage_account_id           = var.diagnostics_storage_id
  log_analytics_workspace_id   = var.diagnostics_workspace_resource_id

  log {
    category                   = "StorageRead"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }

  count                        = var.enable_storage_diagnostic_setting ? 1 : 0
}

resource azurerm_app_service_plan paas_plan {
  name                         = "${var.resource_group_name}-appsvc-plan"
  location                     = azurerm_resource_group.app_rg.location
  resource_group_name          = azurerm_resource_group.app_rg.name

  # Required for containers
  kind                         = "Linux"
  reserved                     = true

  sku {
    tier                       = "PremiumV3"
    size                       = "P1v3"
  }

  tags                         = var.tags
}

# Use user assigned identity, so we can get hold of the Application/Client ID
# This also prevents a bidirectional dependency between App Service & SQL Database
resource azurerm_user_assigned_identity paas_web_app_identity {
  name                         = "${var.resource_group_name}-appsvc-identity"
  location                     = azurerm_resource_group.app_rg.location
  resource_group_name          = azurerm_resource_group.app_rg.name

  tags                         = var.tags
}

locals {
  # No secrets in connection string
  sql_connection_string        = "Server=tcp:${azurerm_sql_server.app_sqlserver.fully_qualified_domain_name},1433;Database=${azurerm_sql_database.app_sqldb.name};"
}

resource azurerm_storage_container application_logs {
  name                         = "applicationlogs"
  storage_account_name         = local.diagnostics_storage_name
  container_access_type        = "private"

  depends_on                   = [
  ]
}
data azurerm_storage_account_blob_container_sas application_logs {
  connection_string            = data.azurerm_storage_account.diagnostics.primary_connection_string
  container_name               = azurerm_storage_container.application_logs.name
  https_only                   = true

  start                        = formatdate("YYYY-MM-DD",timestamp())
  expiry                       = formatdate("YYYY-MM-DD",timeadd(timestamp(),"8760h")) # 1 year from now (365 days)

  permissions {
    read                       = true
    add                        = true
    create                     = true
    write                      = true
    delete                     = true
    list                       = true
  }
}

resource azurerm_storage_container http_logs {
  name                         = "httplogs"
  storage_account_name         = local.diagnostics_storage_name
  container_access_type        = "private"

  depends_on                   = [
  ]
}
data azurerm_storage_account_blob_container_sas http_logs {
  connection_string            = data.azurerm_storage_account.diagnostics.primary_connection_string
  container_name               = azurerm_storage_container.http_logs.name
  https_only                   = true

  start                        = formatdate("YYYY-MM-DD",timestamp())
  expiry                       = formatdate("YYYY-MM-DD",timeadd(timestamp(),"8760h")) # 1 year from now (365 days)

  permissions {
    read                       = true
    add                        = true
    create                     = true
    write                      = true
    delete                     = true
    list                       = true
  }
}

# WARNING: Make sure staging slot is kept in sync!
resource azurerm_app_service paas_web_app {
  name                         = "${var.resource_group_name}-appsvc-app"
  location                     = azurerm_resource_group.app_rg.location
  resource_group_name          = azurerm_resource_group.app_rg.name
  app_service_plan_id          = azurerm_app_service_plan.paas_plan.id

  app_settings                 = local.app_service_settings

  dynamic "auth_settings" {
    for_each = range(local.aad_auth_client_id != null ? 1 : 0) 
    content {
      active_directory {
        client_id              = local.aad_auth_client_id
        client_secret          = var.aad_auth_client_id_map["${terraform.workspace}_client_secret"]
      }
      default_provider         = "AzureActiveDirectory"
      enabled                  = var.enable_aad_auth
      issuer                   = "https://sts.windows.net/${var.tenant_id}/"
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
    application_logs {
      azure_blob_storage {
        level                  = "Error"
        retention_in_days      = 90
        sas_url                = "${azurerm_storage_container.application_logs.id}${data.azurerm_storage_account_blob_container_sas.application_logs.sas}"
      }
    }
    http_logs {
      azure_blob_storage {
        retention_in_days      = 90
        sas_url                = "${azurerm_storage_container.http_logs.id}${data.azurerm_storage_account_blob_container_sas.http_logs.sas}"
      }
    }
  }

  site_config {
    always_on                  = true # Better demo experience, no warmup needed
    app_command_line           = ""
    default_documents          = local.app_service_default_documents
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

    vnet_route_all_enabled     = true
  }

  lifecycle {
    ignore_changes             = [
                                 app_settings["ASPNETCORE_ENVIRONMENT"], # Swap slot outside of Terraform
                                 site_config.0.linux_fx_version, # Deploy containers outside of Terraform
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

  tags                         = var.tags
  count                        = var.vanity_fqdn != null ? 1 : 0
} 
resource azurerm_dns_cname_record app_service_alias {
  name                         = "${local.vanity_hostname}-appsvc"
  zone_name                    = var.vanity_domainname
  resource_group_name          = element(split("/",var.vanity_dns_zone_id),length(split("/",var.vanity_dns_zone_id))-5)
  ttl                          = 300
  record                       = azurerm_app_service.paas_web_app.default_site_hostname

  tags                         = var.tags
  count                        = var.vanity_fqdn != null ? 1 : 0
} 
resource azurerm_app_service_certificate vanity_ssl {
  name                         = var.vanity_certificate_name
  resource_group_name          = azurerm_app_service.paas_web_app.resource_group_name
  location                     = azurerm_app_service.paas_web_app.location
  pfx_blob                     = filebase64(var.vanity_certificate_path)
  password                     = var.vanity_certificate_password

  tags                         = var.tags
  count                        = var.vanity_fqdn != null ? 1 : 0
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

# TODO: Expose via Private Link & WAF, once supported
resource azurerm_app_service_slot staging {
  name                         = "staging"
  app_service_name             = azurerm_app_service.paas_web_app.name
  location                     = azurerm_app_service.paas_web_app.location
  resource_group_name          = azurerm_app_service.paas_web_app.resource_group_name
  app_service_plan_id          = azurerm_app_service_plan.paas_plan.id

  app_settings                 = local.app_service_settings_staging

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
    application_logs {
      azure_blob_storage {
        level                  = "Error"
        retention_in_days      = 90
        sas_url                = "${azurerm_storage_container.application_logs.id}${data.azurerm_storage_account_blob_container_sas.application_logs.sas}"
      }
    }
    http_logs {
      azure_blob_storage {
        retention_in_days      = 90
        sas_url                = "${azurerm_storage_container.http_logs.id}${data.azurerm_storage_account_blob_container_sas.http_logs.sas}"
      }
    }
  }

  site_config {
    always_on                  = true # Better demo experience, no warmup needed
    app_command_line           = ""
    default_documents          = local.app_service_default_documents
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
    dynamic "ip_restriction" {
      for_each = var.admin_ip_ranges
      content {
        ip_address             = ip_restriction.value
      }
    }

    # Required for containers
    linux_fx_version           = local.linux_fx_version
    # LocalGit removed since using containers for deployment
    scm_type                   = "None"
  }

  tags                        = azurerm_app_service.paas_web_app.tags

  lifecycle {
    ignore_changes             = [
                                 app_settings["ASPNETCORE_ENVIRONMENT"] # Swap slot outside of Terraform
    ]
  }
  depends_on                  = [
    azurerm_app_service_virtual_network_swift_connection.network,
    azurerm_private_endpoint.app_service_endpoint
  ]
}

### Event Hub
resource azurerm_eventhub_namespace app_eventhub {
  name                         = "${lower(replace(var.resource_group_name,"-",""))}eventhubnamespace"
  location                     = azurerm_resource_group.app_rg.location
  resource_group_name          = azurerm_resource_group.app_rg.name
  sku                          = "Standard"
  capacity                     = 1
  zone_redundant               = true

  # Service Endpoint support
  dynamic "network_rulesets" {
    for_each = range(var.restrict_public_access ? 1 : 0) 
    content {
      default_action           = "Deny"
      # Without this hole we can't make (automated) changes. Disable it later in the interactive demo                 
      ip_rule {
        action                 = "Allow"
        ip_mask                = local.publicprefix # We need this to make changes
      }

      # BUG: There is no variable named "var".
      # https://github.com/hashicorp/terraform/issues/22340
      # https://github.com/hashicorp/terraform/issues/24544
      # https://github.com/terraform-providers/terraform-provider-azurerm/issues/6338
      # https://github.com/terraform-providers/terraform-provider-azurerm/issues/7014
      # dynamic "ip_rule" {
      #   for_each               = var.admin_ip_ranges
      #   content {
      #     action               = "Allow"
      #     ip_mask              = ip_rule.value
      #   }
      # }
      virtual_network_rule {
        # Allow the Firewall subnet
        subnet_id              = var.iag_subnet_id
      }
      virtual_network_rule {
        subnet_id              = var.integrated_subnet_id
      }
    }
  }

  # Service Endpoint support
  dynamic "network_rulesets" {
    for_each = range(var.restrict_public_access ? 0 : 1) 
    content {
      default_action           = "Allow"
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
# Credentials are mandatory, but password is random and declared as output variable
  administrator_login          = var.admin_username
  administrator_login_password = local.password
  
  tags                         = var.tags
}

resource azurerm_mssql_server_extended_auditing_policy auditing {
  server_id                    = azurerm_sql_server.app_sqlserver.id
  storage_endpoint             = azurerm_storage_account.audit_storage.primary_blob_endpoint
  storage_account_access_key   = azurerm_storage_account.audit_storage.primary_access_key
  log_monitoring_enabled       = true
}

# resource azurerm_mssql_server_security_alert_policy policy {
#   resource_group_name          = azurerm_resource_group.app_rg.name
#   server_name                  = azurerm_sql_server.app_sqlserver.name
#   state                        = "Enabled"
#   storage_endpoint             = azurerm_storage_account.audit_storage.primary_blob_endpoint
#   storage_account_access_key   = azurerm_storage_account.audit_storage.primary_access_key
# }

resource azurerm_storage_account audit_storage {
  name                         = "${local.resource_group_name_short}adt"
  location                     = azurerm_resource_group.app_rg.location
  resource_group_name          = azurerm_resource_group.app_rg.name
  account_kind                 = "StorageV2"
  account_tier                 = "Standard"
  account_replication_type     = var.storage_replication_type
  enable_https_traffic_only    = true
 
  provisioner "local-exec" {
    # TODO: Add --auth-mode login once supported
    command                    = "az storage logging update --account-name ${self.name} --log rwd --retention 90 --services b"
  }

  # TODO: Add network rules using Managed Identity, once azurerm supports it
  #       https://docs.microsoft.com/en-us/azure/storage/common/storage-network-security?tabs=azure-cli#grant-access-from-azure-resource-instances-preview

  timeouts {
    create                     = var.default_create_timeout
    update                     = var.default_update_timeout
    read                       = var.default_read_timeout
    delete                     = var.default_delete_timeout
  }  

  tags                         = var.tags
  }
resource azurerm_storage_container sql_vulnerability {
  name                         = "sqlvulnerability"
  storage_account_name         = azurerm_storage_account.audit_storage.name
  container_access_type        = "private"
}

# resource azurerm_mssql_server_vulnerability_assessment assessment {
#   server_security_alert_policy_id = azurerm_mssql_server_security_alert_policy.policy.id
#   storage_container_path       = "${azurerm_storage_account.audit_storage.primary_blob_endpoint}${azurerm_storage_container.sql_vulnerability.name}/"
#   storage_account_access_key   = azurerm_storage_account.audit_storage.primary_access_key

#   dynamic "recurring_scans" {
#     for_each = range(var.alert_email != null && var.alert_email != "" ? 0 : 1) 
#     content {
#       enabled                  = true
#       email_subscription_admins= true
#     }
#   }

#   dynamic "recurring_scans" {
#     for_each = range(var.alert_email != null && var.alert_email != "" ? 1 : 0) 
#     content {
#       enabled                  = true
#       email_subscription_admins= true
#       emails                   = [
#         var.alert_email
#       ]
#     }
#   }

#   depends_on                   = [
#     # Wait for these resources to be created, so they are included in the baseline
#     azurerm_sql_active_directory_administrator.dba,
#     azurerm_sql_firewall_rule.adminclient,
#     azurerm_sql_firewall_rule.tfclientipprefix,
#     null_resource.disable_sql_public_network_access,
#     null_resource.grant_sql_access,
#   ]
# }

resource null_resource enable_sql_public_network_access {
  triggers                     = {
    always                     = timestamp()
  }
  # Enable public access, so Terraform can make changes e.g. from a hosted pipeline
  # BUG: # (ExternalAdministratorPrincipalType) Invalid or missing external administrator principal type. Please select from User, Application or Group.
  provisioner local-exec {
    command                    = "az sql server update -n ${azurerm_sql_server.app_sqlserver.name} -g ${azurerm_sql_server.app_sqlserver.resource_group_name} --set publicNetworkAccess='Enabled' --query 'publicNetworkAccess' -o tsv"
  }

  depends_on                   = [
    azurerm_mssql_server_extended_auditing_policy.auditing
  ]
}

resource azurerm_sql_firewall_rule tfclientipprefix {
  name                         = "TerraformClientIpPrefixRule"
  resource_group_name          = azurerm_resource_group.app_rg.name
  server_name                  = azurerm_sql_server.app_sqlserver.name
  start_ip_address             = cidrhost(local.publicprefix,0)
  end_ip_address               = cidrhost(local.publicprefix,pow(2,32-split("/",local.publicprefix)[1])-1)

  depends_on                   = [null_resource.enable_sql_public_network_access]
}

resource azurerm_sql_firewall_rule adminclient {
  name                         = "AdminClientRule${count.index+1}"
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
  depends_on                   = [
    azurerm_app_service_virtual_network_swift_connection.network,
    null_resource.enable_sql_public_network_access
  ]
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
  depends_on                   = [null_resource.enable_sql_public_network_access]
}
resource azurerm_private_dns_a_record sql_server_dns_record {
  name                         = azurerm_sql_server.app_sqlserver.name
  zone_name                    = "privatelink.database.windows.net"
  resource_group_name          = local.vdc_resource_group_name
  ttl                          = 300
  records                      = [azurerm_private_endpoint.sqlserver_endpoint.0.private_service_connection[0].private_ip_address]

  count                        = var.enable_private_link ? 1 : 0
  tags                         = var.tags
  depends_on                   = [null_resource.enable_sql_public_network_access]
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
                                  azurerm_sql_firewall_rule.tfclientipprefix,
                                  null_resource.grant_sql_access,

                                  # Wait until all SQL DB resources have been created
                                  azurerm_monitor_diagnostic_setting.sql_database_logs
  ]
}

# This is for Terraform acting as the AAD DBA (e.g. to execute change scripts)
resource azurerm_sql_active_directory_administrator dba {
  # Configure as Terraform identity as DBA
  server_name                  = azurerm_sql_server.app_sqlserver.name
  resource_group_name          = azurerm_resource_group.app_rg.name
# login                        = "Terraform"
  login                        = var.dba_object_id
  object_id                    = var.dba_object_id
  tenant_id                    = var.tenant_id
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

  threat_detection_policy {
    state                      = "Enabled"
  }

  zone_redundant               = true

  tags                         = var.tags
} 

# resource azurerm_mssql_database_vulnerability_assessment_rule_baseline app_va1258_baseline {
#   server_vulnerability_assessment_id = azurerm_mssql_server_vulnerability_assessment.assessment.id
#   database_name                = azurerm_sql_database.app_sqldb.name
#   rule_id                      = "VA1258"
#   baseline_name                = "default"
#   baseline_result {
#     result                     = [
#       var.admin_login
#     ]
#   }

#   count                        = var.enable_custom_vulnerability_baseline ? 1 : 0
# }

# resource azurerm_mssql_database_vulnerability_assessment_rule_baseline master_va2063_baseline {
#   server_vulnerability_assessment_id = azurerm_mssql_server_vulnerability_assessment.assessment.id
#   database_name                = azurerm_sql_database.app_sqldb.name
#   rule_id                      = "VA2063"
#   baseline_name                = "master"
#   baseline_result {
#     result                     = [
#       azurerm_sql_firewall_rule.tfclientipprefix.name,
#       azurerm_sql_firewall_rule.tfclientipprefix.start_ip_address,
#       azurerm_sql_firewall_rule.tfclientipprefix.end_ip_address
#     ]
#   }
#   dynamic "baseline_result" {
#     for_each = azurerm_sql_firewall_rule.adminclient
#     content {
#       result                   = [
#         baseline_result.value["name"],
#         baseline_result.value["start_ip_address"],
#         baseline_result.value["end_ip_address"],
#       ]
#     }
#   }

#   count                        = var.enable_custom_vulnerability_baseline ? 1 : 0
# }

# resource azurerm_mssql_database_vulnerability_assessment_rule_baseline master_va2065_baseline {
#   server_vulnerability_assessment_id = azurerm_mssql_server_vulnerability_assessment.assessment.id
#   database_name                = azurerm_sql_database.app_sqldb.name
#   rule_id                      = "VA2065"
#   baseline_name                = "master"
#   baseline_result {
#     result                     = [
#       azurerm_sql_firewall_rule.tfclientipprefix.name,
#       azurerm_sql_firewall_rule.tfclientipprefix.start_ip_address,
#       azurerm_sql_firewall_rule.tfclientipprefix.end_ip_address
#     ]
#   }
#   dynamic "baseline_result" {
#     for_each = azurerm_sql_firewall_rule.adminclient
#     content {
#       result                   = [
#         baseline_result.value["name"],
#         baseline_result.value["start_ip_address"],
#         baseline_result.value["end_ip_address"],
#       ]
#     }
#   }

#   count                        = var.enable_custom_vulnerability_baseline ? 1 : 0
# }

# resource azurerm_mssql_database_vulnerability_assessment_rule_baseline app_va2109_baseline {
#   server_vulnerability_assessment_id = azurerm_mssql_server_vulnerability_assessment.assessment.id
#   database_name                = azurerm_sql_database.app_sqldb.name
#   rule_id                      = "VA2109"
#   baseline_name                = "default"
#   baseline_result {
#     result                     = [
#       var.admin_login,
#       "db_accessadmin",
#       "EXTERNAL_GROUP",
#       "EXTERNAL"
#     ]
#   }
#   baseline_result {
#     result                     = [
#       var.admin_login,
#       "db_ddladmin",
#       "EXTERNAL_GROUP",
#       "EXTERNAL"
#     ]
#   }
#   baseline_result {
#     result                     = [
#       var.admin_login,
#       "db_owner",
#       "EXTERNAL_GROUP",
#       "EXTERNAL"
#     ]
#   }
#   baseline_result {
#     result                     = [
#       var.admin_login,
#       "db_securityadmin",
#       "EXTERNAL_GROUP",
#       "EXTERNAL"
#     ]
#   }

#   count                        = var.enable_custom_vulnerability_baseline ? 1 : 0
# }

# resource azurerm_mssql_database_vulnerability_assessment_rule_baseline master_va2130_baseline {
#   server_vulnerability_assessment_id = azurerm_mssql_server_vulnerability_assessment.assessment.id
#   database_name                = azurerm_sql_database.app_sqldb.name
#   rule_id                      = "VA2130"
#   baseline_name                = "master"
#   dynamic "baseline_result" {
#     for_each = range(var.admin_object_id != null ? 1 : 0) 
#     content {
#       result                   = [
#         var.admin_object_id,
#         # "0x00000000000000000000000000000000"
#       ]
#     }
#   }
#   baseline_result {
#     result                     = [
#       var.admin_username,
#       # "0x0000000000000000000000000000000000000000000000000000000000000000"
#     ]
#   }

#   count                        = var.enable_custom_vulnerability_baseline ? 1 : 0
# }

resource azurerm_monitor_diagnostic_setting sql_database_logs {
  name                         = "SqlDatabase_Logs"
  target_resource_id           = azurerm_sql_database.app_sqldb.id
  storage_account_id           = var.diagnostics_storage_id
  log_analytics_workspace_id   = var.diagnostics_workspace_resource_id

  log {
    category                   = "SQLSecurityAuditEvents"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }

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

  metric {
    category                   = "WorkloadManagement"

    retention_policy {
      enabled                  = false
    }
  } 

  depends_on                   = [
    azurerm_mssql_server_extended_auditing_policy.auditing,
    # azurerm_mssql_database_extended_auditing_policy.auditing
  ]
}