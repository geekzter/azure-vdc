module iaas_spoke_vnet {
  source                       = "./modules/spoke-vnet"
  resource_group_id            = azurerm_resource_group.vdc_rg.id
  location                     = azurerm_resource_group.vdc_rg.location
  tags                         = local.tags

  address_space                = var.vdc_config["iaas_spoke_range"]
  bastion_subnet_range         = var.vdc_config["iaas_spoke_bastion_subnet"]
  default_create_timeout       = var.default_create_timeout
  default_update_timeout       = var.default_update_timeout
  default_read_timeout         = var.default_read_timeout
  default_delete_timeout       = var.default_delete_timeout
  deploy_network_watcher       = var.deploy_network_watcher
  deploy_managed_bastion       = var.deploy_managed_bastion
  dns_servers                  = azurerm_virtual_network.hub_vnet.dns_servers
  enable_routetable_for_subnets = ["app","data"]
  gateway_ip_address           = azurerm_firewall.iag.ip_configuration.0.private_ip_address # Delays provisioning to start after Azure FW is provisioned
# gateway_ip_address           = cidrhost(var.vdc_config["iag_subnet"], 4) # Azure FW uses the 4th available IP address in the range
  hub_gateway_dependency       = module.p2s_vpn.gateway_id
  hub_virtual_network_id       = azurerm_virtual_network.hub_vnet.id
  private_dns_zones            = [for z in azurerm_private_dns_zone.zone : z.name]
  service_endpoints            = {
    app                        = [
                                 ]
    data                       = [
                                 ]
  }
    spoke_virtual_network_name   = "${azurerm_resource_group.vdc_rg.name}-iaas-spoke-network"
  subnets                      = {
    app                        = var.vdc_config["iaas_spoke_app_subnet"]
    data                       = var.vdc_config["iaas_spoke_data_subnet"]
  }
  subnet_delegations           = {}
  use_hub_gateway              = var.deploy_vpn

  diagnostics_storage_id       = azurerm_storage_account.vdc_diag_storage.id
  diagnostics_workspace_resource_id = azurerm_log_analytics_workspace.vcd_workspace.id
  diagnostics_workspace_workspace_id = azurerm_log_analytics_workspace.vcd_workspace.workspace_id
  network_watcher_name         = local.network_watcher_name
  network_watcher_resource_group_name = local.network_watcher_resource_group
  workspace_location           = local.workspace_location
}

locals {
  vm_agent_dependencies        = concat(module.iaas_spoke_vnet.access_dependencies,
                                 [
                                 azurerm_firewall_application_rule_collection.iag_app_rules.id,
                                 azurerm_firewall_network_rule_collection.iag_net_outbound_rules.id,
                                 try(azurerm_private_dns_a_record.aut_storage_blob_dns_record.0.id,""),
                                 try(azurerm_private_dns_a_record.diag_storage_blob_dns_record.0.id,""),
                                 try(azurerm_private_dns_a_record.diag_storage_table_dns_record.0.id,""),
                                 try(azurerm_private_dns_a_record.vault_dns_record.0.id,""),
                                 try(azurerm_storage_account_network_rules.automation_storage_rules.0.id,"")
  ])
  # HACK: This value is dependent on all elements of the list being created
  vm_connectivity_dependency   = join("|",[for dep in local.vm_agent_dependencies : substr(dep,0,1)])
}

module iis_app {
  source                       = "./modules/iis-app"
  deployment_name         = local.deployment_name
  resource_group               = local.iaas_app_resource_group
  vdc_resource_group_id        = azurerm_resource_group.vdc_rg.id
  location                     = azurerm_resource_group.vdc_rg.location
  tags                         = local.tags

  admin_object_id              = var.admin_object_id
  admin_password               = local.password
  admin_username               = var.admin_username
  app_devops                   = var.app_devops
  app_url                      = local.iaas_app_url
  app_web_vms                  = var.app_web_vms
  app_web_vm_number            = var.app_web_vm_number
  app_db_lb_address            = var.vdc_config["iaas_spoke_app_db_lb_address"]
  app_db_vms                   = var.app_db_vms
  app_db_vm_number             = var.app_db_vm_number
  app_subnet_id                = lookup(module.iaas_spoke_vnet.subnet_ids,"app","")
  automation_storage_name      = azurerm_storage_account.vdc_automation_storage.name
  data_subnet_id               = lookup(module.iaas_spoke_vnet.subnet_ids,"data","")
  default_create_timeout       = var.default_create_timeout
  default_update_timeout       = var.default_update_timeout
  default_read_timeout         = var.default_read_timeout
  default_delete_timeout       = var.default_delete_timeout
  deploy_monitoring_vm_extensions = var.deploy_monitoring_vm_extensions
  deploy_network_watcher       = var.deploy_network_watcher
  deploy_non_essential_vm_extensions = var.deploy_non_essential_vm_extensions
  deploy_security_vm_extensions = var.deploy_security_vm_extensions
  key_vault_id                 = azurerm_key_vault.vault.id
  key_vault_uri                = azurerm_key_vault.vault.vault_uri
  vm_connectivity_dependency   = local.vm_connectivity_dependency
  diagnostics_instrumentation_key = azurerm_application_insights.vdc_insights.instrumentation_key
  diagnostics_storage_id       = azurerm_storage_account.vdc_diag_storage.id
  diagnostics_workspace_resource_id = azurerm_log_analytics_workspace.vcd_workspace.id
  diagnostics_workspace_workspace_id = azurerm_log_analytics_workspace.vcd_workspace.workspace_id
  diagnostics_workspace_key    = azurerm_log_analytics_workspace.vcd_workspace.primary_shared_key
  network_watcher_name         = local.network_watcher_name
  network_watcher_resource_group_name = local.network_watcher_resource_group
  use_pipeline_environment     = var.use_pipeline_environment
}

module managed_bastion_hub {
  source                       = "./modules/managed-bastion"
  resource_group_id            = azurerm_resource_group.vdc_rg.id
  location                     = azurerm_resource_group.vdc_rg.location
  tags                         = local.tags

  subnet_range                 = var.vdc_config["hub_bastion_subnet"]
  virtual_network_id           = azurerm_virtual_network.hub_vnet.id

  default_create_timeout       = var.default_create_timeout
  default_update_timeout       = var.default_update_timeout
  default_read_timeout         = var.default_read_timeout
  default_delete_timeout       = var.default_delete_timeout
  diagnostics_storage_id       = azurerm_storage_account.vdc_diag_storage.id
  diagnostics_workspace_resource_id = azurerm_log_analytics_workspace.vcd_workspace.id

  deploy_managed_bastion       = var.deploy_managed_bastion
}

module p2s_vpn {
  source                       = "./modules/p2s-vpn"
  resource_group_id            = azurerm_resource_group.vdc_rg.id
  location                     = azurerm_resource_group.vdc_rg.location
  tags                         = local.tags

  default_create_timeout       = var.default_create_timeout
  default_update_timeout       = var.default_update_timeout
  default_read_timeout         = var.default_read_timeout
  default_delete_timeout       = var.default_delete_timeout
  
  virtual_network_id           = azurerm_virtual_network.hub_vnet.id
  subnet_range                 = var.vdc_config["hub_vpn_subnet"]
  vpn_range                    = var.vdc_config["vpn_range"]
  vpn_root_cert_name           = var.vpn_root_cert_name
  vpn_root_cert_file           = var.vpn_root_cert_file

  diagnostics_storage_id       = azurerm_storage_account.vdc_diag_storage.id
  diagnostics_workspace_resource_id = azurerm_log_analytics_workspace.vcd_workspace.id

  deploy_vpn                   = var.deploy_vpn
}

module paas_app {
  source                       = "./modules/paas-app"
  resource_group_name          = local.paas_app_resource_group
  vdc_resource_group_id        = azurerm_resource_group.vdc_rg.id
  location                     = azurerm_resource_group.vdc_rg.location
  tags                         = local.tags
  
  aad_auth_client_id_map       = var.paas_aad_auth_client_id_map
  admin_ips                    = local.admin_ips
  admin_ip_ranges              = local.admin_cidr_ranges
  admin_login                  = var.admin_login
  admin_object_id              = var.admin_object_id
  admin_username               = var.admin_username
  app_subnet_id                = lookup(module.paas_spoke_vnet.subnet_ids,"app","")
  management_subnet_ids        = concat(module.paas_spoke_vnet.management_subnet_ids,
                                 [
                                 azurerm_subnet.mgmt_subnet.id
  ])
  database_template_storage_key= var.app_database_template_storage_key
  data_subnet_id               = lookup(module.paas_spoke_vnet.subnet_ids,"data","")
  default_create_timeout       = var.default_create_timeout
  default_update_timeout       = var.default_update_timeout
  default_read_timeout         = var.default_read_timeout
  default_delete_timeout       = var.default_delete_timeout
  disable_public_database_access= var.disable_public_database_access
  enable_aad_auth              = var.enable_app_service_aad_auth
  enable_private_link          = var.enable_private_link
  grant_database_access        = var.grant_database_access
  iag_subnet_id                = azurerm_subnet.iag_subnet.id
  integrated_subnet_id         = lookup(module.paas_spoke_vnet.subnet_ids,"appservice","")
  integrated_subnet_range      = var.vdc_config["paas_spoke_appsvc_subnet"]
  integrated_vnet_id           = module.paas_spoke_vnet.spoke_virtual_network_id
  shared_resources_group       = var.shared_resources_group
  storage_import               = var.paas_app_storage_import
  storage_replication_type     = var.app_storage_replication_type
  vanity_certificate_name      = var.vanity_certificate_name
  vanity_certificate_path      = var.vanity_certificate_path
  vanity_certificate_password  = var.vanity_certificate_password
  vanity_dns_zone_id           = var.use_vanity_domain_and_ssl ? data.azurerm_dns_zone.vanity_domain.0.id : null
  vanity_domainname            = var.vanity_domainname
  vanity_fqdn                  = var.use_vanity_domain_and_ssl ? local.paas_app_fqdn : null
  vanity_url                   = local.paas_app_url
  waf_subnet_id                = azurerm_subnet.waf_subnet.id

  diagnostics_instrumentation_key = azurerm_application_insights.vdc_insights.instrumentation_key
  diagnostics_storage_id       = azurerm_storage_account.vdc_diag_storage.id
  diagnostics_workspace_resource_id = azurerm_log_analytics_workspace.vcd_workspace.id
}

module paas_spoke_vnet {
  source                       = "./modules/spoke-vnet"
  resource_group_id            = azurerm_resource_group.vdc_rg.id
  location                     = azurerm_resource_group.vdc_rg.location
  tags                         = local.tags

  address_space                = var.vdc_config["paas_spoke_range"]
  bastion_subnet_range         = var.vdc_config["paas_spoke_bastion_subnet"]
  default_create_timeout       = var.default_create_timeout
  default_update_timeout       = var.default_update_timeout
  default_read_timeout         = var.default_read_timeout
  default_delete_timeout       = var.default_delete_timeout
  deploy_managed_bastion       = var.deploy_managed_bastion
  deploy_network_watcher       = var.deploy_network_watcher
  dns_servers                  = azurerm_virtual_network.hub_vnet.dns_servers
  enable_routetable_for_subnets = [
                                  "appservice",
                                  "data"
                                  ]
  gateway_ip_address           = azurerm_firewall.iag.ip_configuration.0.private_ip_address # Delays provisioning to start after Azure FW is provisioned
  hub_gateway_dependency       = module.p2s_vpn.gateway_id
  hub_virtual_network_id       = azurerm_virtual_network.hub_vnet.id
  private_dns_zones            = [for z in azurerm_private_dns_zone.zone : z.name]
  service_endpoints            = {
    appservice                 = [
                                  "Microsoft.AzureActiveDirectory",
                                  "Microsoft.EventHub",
                                  "Microsoft.Sql",
                                  "Microsoft.Storage"
                                 ]
  }
  spoke_virtual_network_name   = "${azurerm_resource_group.vdc_rg.name}-paas-spoke-network"
  subnets                      = {
    app                        = var.vdc_config["paas_spoke_app_subnet"]
    appservice                 = var.vdc_config["paas_spoke_appsvc_subnet"]
    data                       = var.vdc_config["paas_spoke_data_subnet"]
  }

  subnet_delegations           = {
    appservice                 = "Microsoft.Web/serverFarms"
  }
  use_hub_gateway              = var.deploy_vpn

  diagnostics_storage_id       = azurerm_storage_account.vdc_diag_storage.id
  diagnostics_workspace_resource_id = azurerm_log_analytics_workspace.vcd_workspace.id
  diagnostics_workspace_workspace_id = azurerm_log_analytics_workspace.vcd_workspace.workspace_id
  network_watcher_name         = local.network_watcher_name
  network_watcher_resource_group_name = local.network_watcher_resource_group
  workspace_location           = var.workspace_location
}