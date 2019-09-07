module "auto_shutdown" {
  source                       = "./modules/auto-shutdown"
  resource_environment         = "${local.environment}"
  resource_group               = "${azurerm_resource_group.vdc_rg.name}"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  app_resource_group           = "${local.app_resource_group}"
  app_storage_replication_type = "${var.app_storage_replication_type}"
  tags                         = "${local.tags}"
  resource_group_ids           = [
                                 "${azurerm_resource_group.vdc_rg.id}",
                                 "${module.iis_app.app_resource_group_id}"
  ]

  deploy_auto_shutdown         = "${var.deploy_auto_shutdown}"

  diagnostics_instrumentation_key = "${azurerm_application_insights.vdc_insights.instrumentation_key}"
  diagnostics_storage_id       = "${azurerm_storage_account.vdc_diag_storage.id}"
  diagnostics_workspace_id     = "${azurerm_log_analytics_workspace.vcd_workspace.id}"
}

module "iis_app" {
  source                       = "./modules/iis-app"
  resource_environment         = "${local.environment}"
  resource_group               = "${local.app_resource_group}"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  tags                         = "${local.tags}"

  admin_username               = "${var.admin_username}"
  admin_password               = "${local.password}"
  app_devops                   = "${var.app_devops}"
  app_url                      = "${local.app_url}"
  app_web_vms                  = "${var.app_web_vms}"
  app_db_lb_address            = "${var.vdc_config["app_db_lb_address"]}"
  app_db_vms                   = "${var.app_db_vms}"
  #app_subnet_id                = "${azurerm_subnet.app_subnet.id}"
  #data_subnet_id               = "${azurerm_subnet.data_subnet.id}"
  app_subnet_id                = "${module.iaas_spoke_vnet.subnet_ids["app"]}"
  data_subnet_id               = "${module.iaas_spoke_vnet.subnet_ids["data"]}"
  release_agent_dependency_id  = ["var.release_agent_dependency_id"]
  diagnostics_storage_id       = "${azurerm_storage_account.vdc_diag_storage.id}"
  diagnostics_workspace_id     = "${azurerm_log_analytics_workspace.vcd_workspace.id}"
}

module "managed_bastion_hub" {
  source                       = "./modules/managed-bastion"
  resource_group               = "${azurerm_resource_group.vdc_rg.name}"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  tags                         = "${local.tags}"

  subnet_range                 = "${var.vdc_config["hub_bastion_subnet"]}"
  virtual_network_name         = "${azurerm_virtual_network.hub_vnet.name}"

  diagnostics_storage_id       = "${azurerm_storage_account.vdc_diag_storage.id}"
  diagnostics_workspace_id     = "${azurerm_log_analytics_workspace.vcd_workspace.id}"

  deploy_managed_bastion       = "${var.deploy_managed_bastion}"
}

module "p2s_vpn" {
  source                       = "./modules/p2s-vpn"
  resource_group               = "${azurerm_resource_group.vdc_rg.name}"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  tags                         = "${local.tags}"

  virtual_network_name         = "${azurerm_virtual_network.hub_vnet.name}"
  subnet_range                 = "${var.vdc_config["vpn_subnet"]}"
  vpn_range                    = "${var.vdc_config["vpn_range"]}"
  vpn_root_cert_name           = "${var.vpn_root_cert_name}"
  vpn_root_cert_file           = "${var.vpn_root_cert_file}"

  diagnostics_storage_id       = "${azurerm_storage_account.vdc_diag_storage.id}"
  diagnostics_workspace_id     = "${azurerm_log_analytics_workspace.vcd_workspace.id}"

  deploy_vpn                   = "${var.deploy_vpn}"
}

module "iaas_spoke_vnet" {
  source                       = "./modules/spoke-vnet"
  resource_group               = "${azurerm_resource_group.vdc_rg.name}"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  tags                         = "${local.tags}"

  address_space                = "${var.vdc_config["spoke_range"]}"
  bastion_subnet_range         = "${var.vdc_config["spoke_bastion_subnet"]}"
  deploy_managed_bastion       = "${var.deploy_managed_bastion}"
  dns_servers                  = "${azurerm_virtual_network.hub_vnet.dns_servers}"
  gateway_ip_address           = "${azurerm_firewall.iag.ip_configuration.0.private_ip_address}" # Delays provisioning to start after Azure FW is provisioned
# gateway_ip_address           = "${cidrhost(var.vdc_config["iag_subnet"], 4)}" # Azure FW uses the 4th available IP address in the range
  hub_gateway_dependency       = "${module.p2s_vpn.gateway_id}"
  hub_virtual_network_id       = "${azurerm_virtual_network.hub_vnet.id}"
  hub_virtual_network_name     = "${azurerm_virtual_network.hub_vnet.name}"
  spoke_virtual_network_name   = "${azurerm_resource_group.vdc_rg.name}-spoke-network"
  subnets                      = {
    app                        = "${var.vdc_config["app_subnet"]}"
    data                       = "${var.vdc_config["data_subnet"]}"
  }
  use_hub_gateway              = "${var.deploy_vpn}"

  diagnostics_storage_id       = "${azurerm_storage_account.vdc_diag_storage.id}"
  diagnostics_workspace_id     = "${azurerm_log_analytics_workspace.vcd_workspace.id}"
}