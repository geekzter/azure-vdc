
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
  source                       = "../Scripts/prepare_bastion.ps1"
}

data "template_file" "bastion_first_commands" {
  template = file("../Scripts/FirstLogonCommands.xml")

  vars                         = {
    host1                      = element(var.app_web_vms, 0)
    host2                      = element(var.app_web_vms, 1)
    username                   = var.admin_username
    password                   = local.password
    scripturl                  = azurerm_storage_blob.bastion_prepare_script.url
    sqlserver                  = module.paas_app.sql_server_fqdn
  }
}

resource "azurerm_virtual_machine" "bastion" {
  name                         = "${azurerm_resource_group.vdc_rg.name}-bastion"
  location                     = azurerm_resource_group.vdc_rg.location
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  network_interface_ids        = [azurerm_network_interface.bas_if.id]
  vm_size                      = "Standard_D2s_v3"

  # Uncomment this line to delete the OS disk automatically when deleting the VM
  delete_os_disk_on_termination = true

  # Uncomment this line to delete the data disks automatically when deleting the VM
  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher                  = "MicrosoftWindowsServer"
    offer                      = "WindowsServer"
    sku                        = "2019-Datacenter"
    version                    = "latest"
  }

  storage_os_disk {
    name                       = "${azurerm_resource_group.vdc_rg.name}-bastion-osdisk"
    caching                    = "ReadWrite"
    create_option              = "FromImage"
    managed_disk_type          = "Premium_LRS"
  }

  # Optional data disks
  storage_data_disk {
    name                       = "${azurerm_resource_group.vdc_rg.name}-bastion-datadisk"
    managed_disk_type          = "Premium_LRS"
    create_option              = "Empty"
    lun                        = 0
    disk_size_gb               = "255"
  }

  os_profile {
    computer_name              = "bastion"
    admin_username             = var.admin_username
    admin_password             = local.password
  }

  os_profile_windows_config {
    provision_vm_agent         = true
    enable_automatic_upgrades  = true

    additional_unattend_config {
      pass                     = "oobeSystem"
      component                = "Microsoft-Windows-Shell-Setup"
      setting_name             = "AutoLogon"
      content                  = templatefile("../Scripts/AutoLogon.xml", { 
        count                  = 1, 
        username               = var.admin_username, 
        password               = local.password
      })
    }

    additional_unattend_config {
      pass                     = "oobeSystem"
      component                = "Microsoft-Windows-Shell-Setup"
      setting_name             = "FirstLogonCommands"
      content                  = templatefile("../Scripts/FirstLogonCommands.xml", { 
        username               = var.admin_username, 
        password               = local.password, 
        host1                  = element(var.app_web_vms, 0), 
        host2                  = element(var.app_web_vms, 1),
        scripturl              = azurerm_storage_blob.bastion_prepare_script.url,
        sqlserver              = module.paas_app.sql_server_fqdn
      })
    }
  }

  # Required for AAD Login
  identity {
    type                       = "SystemAssigned"
  }

  # Not zone redundant, we'll rely on zone redundant managed bastion

  depends_on                   = [azurerm_firewall_application_rule_collection.iag_app_rules]

  tags                         = local.tags
}

# resource "azurerm_virtual_machine_extension" "bastion_aadlogin" {
#   name                         = "${azurerm_virtual_machine.bastion.name}/AADLoginForWindows"
#   virtual_machine_id           = "${azurerm_virtual_machine.bastion.id}"
#   publisher                    = "Microsoft.Azure.ActiveDirectory"
#   type                         = "AADLoginForWindows"
#   type_handler_version         = "0.3"
#   auto_upgrade_minor_version   = true

#   tags                         = local.tags
# } 

resource "azurerm_virtual_machine_extension" "bastion_bginfo" {
  name                         = "BGInfo"
  virtual_machine_id           = azurerm_virtual_machine.bastion.id
  publisher                    = "Microsoft.Compute"
  type                         = "BGInfo"
  type_handler_version         = "2.1"
  auto_upgrade_minor_version   = true

  tags                         = local.tags
}

resource "azurerm_virtual_machine_extension" "bastion_dependency_monitor" {
  name                         = "DAExtension"
  virtual_machine_id           = azurerm_virtual_machine.bastion.id
  publisher                    = "Microsoft.Azure.Monitoring.DependencyAgent"
  type                         = "DependencyAgentWindows"
  type_handler_version         = "9.5"
  auto_upgrade_minor_version   = true
  settings                     = <<EOF
    {
      "workspaceId": "${azurerm_log_analytics_workspace.vcd_workspace.workspace_id}"
    }
  EOF

  protected_settings = <<EOF
    { 
      "workspaceKey": "${azurerm_log_analytics_workspace.vcd_workspace.primary_shared_key}"
    } 
  EOF

  tags                         = local.tags
}

resource "azurerm_virtual_machine_extension" "bastion_monitor" {
  name                         = "MicrosoftMonitoringAgent"
  virtual_machine_id           = azurerm_virtual_machine.bastion.id
  publisher                    = "Microsoft.EnterpriseCloud.Monitoring"
  type                         = "MicrosoftMonitoringAgent"
  type_handler_version         = "1.0"
  auto_upgrade_minor_version   = true
  settings                     = <<EOF
    {
      "workspaceId": "${azurerm_log_analytics_workspace.vcd_workspace.workspace_id}"
    }
  EOF

  protected_settings = <<EOF
    { 
      "workspaceKey": "${azurerm_log_analytics_workspace.vcd_workspace.primary_shared_key}"
    } 
  EOF

  tags                         = local.tags
}

resource "azurerm_virtual_machine_extension" "bastion_watcher" {
  name                         = "AzureNetworkWatcherExtension"
  virtual_machine_id           = azurerm_virtual_machine.bastion.id
  publisher                    = "Microsoft.Azure.NetworkWatcher"
  type                         = "NetworkWatcherAgentWindows"
  type_handler_version         = "1.4"
  auto_upgrade_minor_version   = true

  count                        = var.deploy_network_watcher ? 1 : 0

  tags                         = local.tags
}

# BUG: Get's recreated every run
#      https://github.com/terraform-providers/terraform-provider-azurerm/issues/3909
# resource "azurerm_network_connection_monitor" "storage_watcher" {
#   name                         = "${module.paas_app.storage_account_name}-watcher"
#   location                     = azurerm_resource_group.vdc_rg.location
#   resource_group_name          = local.network_watcher_resource_group
#   network_watcher_name         = local.network_watcher_name

#   source {
#     virtual_machine_id         = azurerm_virtual_machine.bastion.id
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
#     virtual_machine_id         = azurerm_virtual_machine.bastion.id
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
  virtual_machine_ids            = concat(module.iis_app.virtual_machine_ids, [azurerm_virtual_machine.bastion.id])
  virtual_machine_ids_string     = join(",",local.virtual_machine_ids)
}

resource null_resource windows_updates {
  # Create Windows Update Schedule
  provisioner "local-exec" {
    command                      = "../Scripts/schedule_vm_updates.ps1 -AutomationAccountName ${azurerm_automation_account.automation.name} -ResourceGroupName ${azurerm_automation_account.automation.resource_group_name} -VMResourceId ${local.virtual_machine_ids_string} -Frequency Daily -StartTime ${var.update_management_time}"
    interpreter                  = ["pwsh", "-nop", "-Command"]
  }

  depends_on                     =[
                                    azurerm_log_analytics_linked_service.automation,
                                    azurerm_log_analytics_solution.oms_solutions,
                                    azurerm_virtual_machine_extension.bastion_monitor,
                                    module.iis_app.monitoring_agent_ids,
                                    module.iis_app
                                  ]
}