locals {
   mgmt_vm_name                = "${substr(lower(replace(azurerm_resource_group.vdc_rg.name,"-","")),0,16)}mgmt"
}

resource "azurerm_network_interface" "bas_if" {
  name                         = "${azurerm_resource_group.vdc_rg.name}-bastion-if"
  location                     = azurerm_resource_group.vdc_rg.location
  resource_group_name          = azurerm_resource_group.vdc_rg.name

  ip_configuration {
    name                       = "bas_ipconfig"
    subnet_id                  = azurerm_subnet.mgmt_subnet.id
    private_ip_address         = var.vdc_config["hub_bastion_address"]
    private_ip_address_allocation = "static"
  }

  tags                         = local.tags
}

resource "azurerm_storage_container" "scripts" {
  name                         = "scripts"
  storage_account_name         = azurerm_storage_account.vdc_automation_storage.name
  container_access_type        = "container"
}

resource "azurerm_storage_blob" "bastion_prepare_script" {
  name                         = "prepare_bastion.ps1"
  storage_account_name         = azurerm_storage_account.vdc_automation_storage.name
  storage_container_name       = azurerm_storage_container.scripts.name

  type                         = "Block"
  source                       = "../Scripts/host/prepare_bastion.ps1"
}

resource "azurerm_windows_virtual_machine" "bastion" {
  name                         = local.mgmt_vm_name
  location                     = azurerm_resource_group.vdc_rg.location
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  network_interface_ids        = [azurerm_network_interface.bas_if.id]
  size                         = var.management_vm_size
  admin_username               = var.admin_username
  admin_password               = local.password

  os_disk {
    name                       = "${local.mgmt_vm_name}-osdisk"
    caching                    = "ReadWrite"
    storage_account_type       = "Premium_LRS"
  }

  source_image_reference {
    publisher                  = "MicrosoftWindowsServer"
    offer                      = "WindowsServer"
    sku                        = "2019-Datacenter"
    version                    = "latest"
  }

  additional_unattend_content {
    setting                    = "AutoLogon"
    content                    = templatefile("../Scripts/host/AutoLogon.xml", { 
      count                    = 1, 
      username                 = var.admin_username, 
      password                 = local.password
    })
  }
  additional_unattend_content {
    setting                    = "FirstLogonCommands"
    content                    = templatefile("../Scripts/host/BastionFirstLogonCommands.xml", { 
      username                 = var.admin_username, 
      password                 = local.password, 
      hosts                    = concat(var.app_web_vms,var.app_db_vms),
      scripturl                = azurerm_storage_blob.bastion_prepare_script.url,
      sqlserver                = module.paas_app.sql_server_fqdn
    })
  }

  custom_data                  = base64encode("Hello World")

  # Required for AAD Login
  identity {
    type                       = "SystemAssigned"
  }

  # Not zone redundant, we'll rely on zone redundant managed bastion

  depends_on                   = [azurerm_firewall_application_rule_collection.iag_app_rules]

  tags                         = local.tags
}

resource null_resource start_bastion {
  # Always run this
  triggers                     = {
    always_run                 = timestamp()
  }

  provisioner local-exec {
    # Start VM, so we can execute script through SSH
    command                    = "az vm start --ids ${azurerm_windows_virtual_machine.bastion.id}"
  }
}

# resource "azurerm_virtual_machine_extension" "bastion_aadlogin" {
#   name                         = "${azurerm_windows_virtual_machine.bastion.name}/AADLoginForWindows"
#   virtual_machine_id           = "azurerm_windows_virtual_machine.bastion.id
#   publisher                    = "Microsoft.Azure.ActiveDirectory"
#   type                         = "AADLoginForWindows"
#   type_handler_version         = "0.3"
#   auto_upgrade_minor_version   = true

#   count                        = var.deploy_non_essential_vm_extensions ? 1 : 0
#   tags                         = local.tags
# } 

resource "azurerm_virtual_machine_extension" "bastion_bginfo" {
  name                         = "BGInfo"
  virtual_machine_id           = azurerm_windows_virtual_machine.bastion.id
  publisher                    = "Microsoft.Compute"
  type                         = "BGInfo"
  type_handler_version         = "2.1"
  auto_upgrade_minor_version   = true

  # Start VM, so we can destroy the extension
  provisioner local-exec {
    command                    = "az vm start --ids ${self.virtual_machine_id}"
    when                       = destroy
  }

  count                        = var.deploy_non_essential_vm_extensions ? 1 : 0
  tags                         = local.tags
  depends_on                   = [null_resource.start_bastion]
}

resource "azurerm_virtual_machine_extension" "bastion_dependency_monitor" {
  name                         = "DAExtension"
  virtual_machine_id           = azurerm_windows_virtual_machine.bastion.id
  publisher                    = "Microsoft.Azure.Monitoring.DependencyAgent"
  type                         = "DependencyAgentWindows"
  type_handler_version         = "9.5"
  auto_upgrade_minor_version   = true
  settings                     = <<EOF
    {
      "workspaceId"            : "${azurerm_log_analytics_workspace.vcd_workspace.workspace_id}"
    }
  EOF

  protected_settings = <<EOF
    { 
      "workspaceKey"           : "${azurerm_log_analytics_workspace.vcd_workspace.primary_shared_key}"
    } 
  EOF

  # Start VM, so we can destroy the extension
  provisioner local-exec {
    command                    = "az vm start --ids ${self.virtual_machine_id}"
    when                       = destroy
  }

  count                        = var.deploy_non_essential_vm_extensions ? 1 : 0
  tags                         = local.tags
  depends_on                   = [null_resource.start_bastion]
}
resource "azurerm_virtual_machine_extension" "bastion_monitor" {
  name                         = "MMAExtension"
  virtual_machine_id           = azurerm_windows_virtual_machine.bastion.id
  publisher                    = "Microsoft.EnterpriseCloud.Monitoring"
  type                         = "MicrosoftMonitoringAgent"
  type_handler_version         = "1.0"
  auto_upgrade_minor_version   = true
  settings                     = <<EOF
    {
      "workspaceId"            : "${azurerm_log_analytics_workspace.vcd_workspace.workspace_id}",
      "azureResourceId"        : "${azurerm_windows_virtual_machine.bastion.id}",
      "stopOnMultipleConnections": "true"
    }
  EOF

  protected_settings = <<EOF
    { 
      "workspaceKey"           : "${azurerm_log_analytics_workspace.vcd_workspace.primary_shared_key}"
    } 
  EOF

  count                        = var.deploy_non_essential_vm_extensions ? 1 : 0
  tags                         = local.tags
  depends_on                   = [null_resource.start_bastion]
}

resource "azurerm_virtual_machine_extension" "bastion_watcher" {
  name                         = "AzureNetworkWatcherExtension"
  virtual_machine_id           = azurerm_windows_virtual_machine.bastion.id
  publisher                    = "Microsoft.Azure.NetworkWatcher"
  type                         = "NetworkWatcherAgentWindows"
  type_handler_version         = "1.4"
  auto_upgrade_minor_version   = true

  # Start VM, so we can destroy the extension
  provisioner local-exec {
    command                    = "az vm start --ids ${self.virtual_machine_id}"
    when                       = destroy
  }

  count                        = var.deploy_network_watcher && var.deploy_non_essential_vm_extensions ? 1 : 0
  tags                         = local.tags
  depends_on                   = [null_resource.start_bastion]
}

# BUG: Get's recreated every run
#      https://github.com/terraform-providers/terraform-provider-azurerm/issues/3909
# resource "azurerm_network_connection_monitor" "storage_watcher" {
#   name                         = "${module.paas_app.storage_account_name}-watcher"
#   location                     = azurerm_resource_group.vdc_rg.location
#   resource_group_name          = local.network_watcher_resource_group
#   network_watcher_name         = local.network_watcher_name

#   source {
#     virtual_machine_id         = azurerm_windows_virtual_machine.bastion.id
#   }

#   destination {
#     address                    = module.paas_app.blob_storage_fqdn
#     port                       = 443
#   }

#   count                        = var.deploy_network_watcher ? 1 : 0
#   depends_on                   = [azurerm_virtual_machine_extension.bastion_watcher]

#   tags                         = local.tags
# }

# resource "azurerm_network_connection_monitor" "eventhub_watcher" {
#   name                         = "${module.paas_app.eventhub_name}-watcher"
#   location                     = azurerm_resource_group.vdc_rg.location
#   resource_group_name          = local.network_watcher_resource_group
#   network_watcher_name         = local.network_watcher_name

#   source {
#     virtual_machine_id         = azurerm_windows_virtual_machine.bastion.id
#   }

#   destination {
#     address                    = module.paas_app.eventhub_namespace_fqdn
#     port                       = 443
#   }

#   count                        = var.deploy_network_watcher ? 1 : 0
#   depends_on                   = [azurerm_virtual_machine_extension.bastion_watcher]

#   tags                         = local.tags
# } 

locals {
  virtual_machine_ids          = concat(module.iis_app.virtual_machine_ids, [azurerm_windows_virtual_machine.bastion.id])
  virtual_machine_ids_string   = join(",",local.virtual_machine_ids)
}

# Automation account, used for runbooks
resource "azurerm_automation_account" "automation" {
  name                         = "${azurerm_resource_group.vdc_rg.name}-automation"
  location                     = local.automation_location
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  sku_name                     = "Basic"
}

resource "azurerm_automation_schedule" "daily" {
  name                         = "${azurerm_automation_account.automation.name}-daily"
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  automation_account_name      = azurerm_automation_account.automation.name
  frequency                    = "Day"
  interval                     = 1
  # https://docs.microsoft.com/en-us/previous-versions/windows/embedded/ms912391(v=winembedded.11)?redirectedfrom=MSDN
  timezone                     = "W. Europe Standard Time"
  start_time                   = timeadd(timestamp(), "1h30m")
  description                  = "Daily schedule"
}

# Disable until there is an Azure CLI equivalent to New-AzAutomationSoftwareUpdateConfiguration
# https://github.com/Azure/azure-cli/issues/5403
# https://github.com/Azure/azure-cli/issues/12761
# resource null_resource windows_updates {
#   # Create Windows Update Schedule
#   provisioner "local-exec" {
#     command                      = "../Scripts/schedule_vm_updates.ps1 -AutomationAccountName ${azurerm_automation_account.automation.name} -ResourceGroupName ${azurerm_automation_account.automation.resource_group_name} -VMResourceId ${local.virtual_machine_ids_string} -Frequency Daily -StartTime ${var.update_management_time}"
#     interpreter                  = ["pwsh", "-nop", "-Command"]
#   }

#   depends_on                     =[
#                                     azurerm_log_analytics_linked_service.automation,
#                                     azurerm_log_analytics_solution.oms_solutions,
# #                                   azurerm_virtual_machine_extension.bastion_monitor,
# #                                   module.iis_app.monitoring_agent_ids,
#                                     module.iis_app
#                                   ]
# }

# Configure function resources with ARM template as Terraform doesn't (yet) support this
# https://docs.microsoft.com/en-us/azure/templates/microsoft.web/2018-11-01/sites/functions
# resource "azurerm_template_deployment" "update_management" {
#   name                         = "${azurerm_automation_account.automation.name}-updates"
#   resource_group_name          = azurerm_resource_group.vdc_rg.name
#   deployment_mode              = "Incremental"

#   template_body                = file("${path.module}/tmpew.json")
#   # template_body                = file("${path.module}/updatemanagement.json")
#   # parameters                   = {
#   #   automationName             = azurerm_automation_account.automation.name
#   #   startTime                  = timeadd(timestamp(), "1h30m")
#   #   virtualMachineIdsString    = join(",", local.virtual_machine_ids)
#   # }

#   depends_on                   = [
#                                  azurerm_log_analytics_linked_service.automation,
#                                  azurerm_log_analytics_solution.oms_solutions,
# #                                azurerm_virtual_machine_extension.bastion_monitor,
# #                                module.iis_app.monitoring_agent_ids,
#                                  module.iis_app
#                                  ]
# }