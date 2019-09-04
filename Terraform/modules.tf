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
  app_db_lb_address            = "${var.vdc_vnet["app_db_lb_address"]}"
  app_db_vms                   = "${var.app_db_vms}"
  app_subnet_id                = "${azurerm_subnet.app_subnet.id}"
  data_subnet_id               = "${azurerm_subnet.data_subnet.id}"
  release_agent_dependency_id  = ["var.release_agent_dependency_id"]
  diagnostics_storage_id       = "${azurerm_storage_account.vdc_diag_storage.id}"
  diagnostics_workspace_id     = "${azurerm_log_analytics_workspace.vcd_workspace.id}"
}

module "managed_bastion" {
  source                       = "./modules/managed-bastion"
  resource_group               = "${azurerm_resource_group.vdc_rg.name}"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  tags                         = "${local.tags}"

  subnet_range                 = "${var.vdc_vnet["bastion_subnet"]}"
  virtual_network_name         = "${azurerm_virtual_network.vnet.name}"

  diagnostics_storage_id       = "${azurerm_storage_account.vdc_diag_storage.id}"
  diagnostics_workspace_id     = "${azurerm_log_analytics_workspace.vcd_workspace.id}"

  deploy_managed_bastion       = "${var.deploy_managed_bastion}"
}

module "p2s_vpn" {
  source                       = "./modules/p2s-vpn"
  resource_group               = "${azurerm_resource_group.vdc_rg.name}"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  tags                         = "${local.tags}"

  virtual_network_name         = "${azurerm_virtual_network.vnet.name}"
  subnet_range                 = "${var.vdc_vnet["vpn_subnet"]}"
  vpn_range                    = "${var.vdc_vnet["vpn_range"]}"
  vpn_root_cert_name           = "${var.vpn_root_cert_name}"
  vpn_root_cert_file           = "${var.vpn_root_cert_file}"

  diagnostics_storage_id       = "${azurerm_storage_account.vdc_diag_storage.id}"
  diagnostics_workspace_id     = "${azurerm_log_analytics_workspace.vcd_workspace.id}"

  deploy_vpn                   = "${var.deploy_vpn}"
}