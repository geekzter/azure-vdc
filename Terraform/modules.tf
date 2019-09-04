module "auto_shutdown" {
  source                       = "./modules/auto-shutdown"
  resource_environment         = "${local.environment}"
  resource_group               = "${azurerm_resource_group.vdc_rg.name}"
  app_resource_group           = "${local.app_resource_group}"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  tags                         = "${local.tags}"
  resource_group_ids           = [
                                 "${azurerm_resource_group.vdc_rg.id}",
                                 "${module.iis_app.app_resource_group_id}"
  ]

  deploy_auto_shutdown         = "${var.deploy_auto_shutdown}"

  app_insights_key             = "${azurerm_application_insights.vdc_insights.instrumentation_key}"
  diagnostics_storage_id       = "${azurerm_storage_account.vdc_diag_storage.id}"
  workspace_id                 = "${azurerm_log_analytics_workspace.vcd_workspace.id}"
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
  app_db_vms                   = "${var.app_db_vms}"
  app_subnet_id                = "${azurerm_subnet.app_subnet.id}"
  data_subnet_id               = "${azurerm_subnet.data_subnet.id}"
  devops_firewall_dependency_id = ["var.devops_firewall_dependency_id"]
  diagnostics_storage_id       = "${azurerm_storage_account.vdc_diag_storage.id}"
  release_web_url              = "${var.release_web_url}"
  release_id                   = "${var.release_id}"
  release_user_email           = "${var.release_user_email}"
  vanity_domainname            = "${var.vanity_domainname}"
  vanity_certificate_name      = "${var.vanity_certificate_name}"
  vanity_certificate_path      = "${var.vanity_certificate_path}"
  vanity_certificate_password  = "${var.vanity_certificate_password}"
  use_vanity_domain_and_ssl    = "${var.use_vanity_domain_and_ssl}"
  workspace_id                 = "${azurerm_log_analytics_workspace.vcd_workspace.id}"
}

module "p2s_vpn" {
  source                       = "./modules/p2s-vpn"
  resource_group               = "${azurerm_resource_group.vdc_rg.name}"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  tags                         = "${local.tags}"

  virtual_network_name         = "${azurerm_virtual_network.vnet.name}"
  vpn_root_cert_name           = "${var.vpn_root_cert_name}"
  vpn_root_cert_file           = "${var.vpn_root_cert_file}"
  vpn_range                    = "${var.vdc_vnet["vpn_range"]}"
  vpn_subnet                   = "${var.vdc_vnet["vpn_subnet"]}"

  diagnostics_storage_id       = "${azurerm_storage_account.vdc_diag_storage.id}"
  workspace_id                 = "${azurerm_log_analytics_workspace.vcd_workspace.id}"
}