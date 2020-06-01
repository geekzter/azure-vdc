locals {
  client_config                = map(
    "environment",               local.deployment_name,
    "privatelinkfqdns",          join(",",[
      module.paas_app.sql_server_fqdn,
      azurerm_storage_account.vdc_diag_storage.primary_blob_host,
      azurerm_storage_account.vdc_diag_storage.primary_table_host,
    ]),
    "scripturl",                 azurerm_storage_blob.mgmt_prepare_script.url,
    "sqldatabase",               module.paas_app.sql_database,
    "sqlserver",                 module.paas_app.sql_server_fqdn,
    "suffix",                    local.suffix,
    "workspace",                 terraform.workspace
  )

  mgmt_vm_name                 = "${azurerm_resource_group.vdc_rg.name}-mgmt"
  mgmt_vm_computer_name        = "${substr(lower(replace(azurerm_resource_group.vdc_rg.name,"/a|e|i|o|u|y|-/","")),0,11)}mgmt"
}

resource azurerm_network_interface bas_if {
  name                         = "${azurerm_resource_group.vdc_rg.name}-mgmt-if"
  location                     = azurerm_resource_group.vdc_rg.location
  resource_group_name          = azurerm_resource_group.vdc_rg.name

  ip_configuration {
    name                       = "bas_ipconfig"
    subnet_id                  = azurerm_subnet.mgmt_subnet.id
    private_ip_address         = var.vdc_config["hub_mgmt_address"]
    private_ip_address_allocation = "static"
  }

  tags                         = local.tags
}

resource azurerm_storage_container scripts {
  name                         = "scripts"
  storage_account_name         = azurerm_storage_account.vdc_automation_storage.name
  container_access_type        = "container"
}

resource azurerm_storage_blob mgmt_prepare_script {
  name                         = "prepare_mgmtvm.ps1"
  storage_account_name         = azurerm_storage_account.vdc_automation_storage.name
  storage_container_name       = azurerm_storage_container.scripts.name

  type                         = "Block"
  source                       = "../scripts/host/prepare_mgmtvm.ps1"
}

resource azurerm_storage_blob configure_mgmtvm_roles {
  name                         = "configure_mgmtvm_roles.ps1"
  storage_account_name         = azurerm_storage_account.vdc_automation_storage.name
  storage_container_name       = azurerm_storage_container.scripts.name

  type                         = "Block"
  source                       = "../scripts/host/configure_mgmtvm_roles.ps1"
}

# Adapted from https://github.com/Azure/terraform-azurerm-diskencrypt/blob/master/main.tf
resource azurerm_key_vault_key disk_encryption_key {
  name                         = "${local.mgmt_vm_name}-disk-key"
  key_vault_id                 = azurerm_key_vault.vault.id
  key_type                     = "RSA"
  key_size                     = 2048
  key_opts                     = [
                                 "decrypt",
                                 "encrypt",
                                 "sign",
                                 "unwrapKey",
                                 "verify",
                                 "wrapKey",
  ]

  depends_on                   = [azurerm_firewall_application_rule_collection.iag_app_rules]
}

# AzureDiskEncryption VM extenstion breaks AutoLogon, use server side encryption
resource azurerm_disk_encryption_set mgmt_disks {
  name                         = "${local.mgmt_vm_name}-disk-key-set"
  location                     = azurerm_resource_group.vdc_rg.location
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  key_vault_key_id             = azurerm_key_vault_key.disk_encryption_key.id
  identity {
    type                       = "SystemAssigned"
  }
}

resource azurerm_key_vault_access_policy mgmt_disk_encryption_access {
  key_vault_id                 = azurerm_key_vault.vault.id
  tenant_id                    = azurerm_disk_encryption_set.mgmt_disks.identity.0.tenant_id
  object_id                    = azurerm_disk_encryption_set.mgmt_disks.identity.0.principal_id
  key_permissions = [
                                "get",
                                "unwrapKey",
                                "wrapKey",
  ]

  depends_on                   = [azurerm_firewall_application_rule_collection.iag_app_rules]
}

resource azurerm_role_assignment mgmt_disk_encryption_access {
  scope                        = azurerm_key_vault.vault.id
  role_definition_name         = "Reader"
  principal_id                 = azurerm_disk_encryption_set.mgmt_disks.identity.0.principal_id
}

resource azurerm_windows_virtual_machine mgmt {
  name                         = local.mgmt_vm_name
  computer_name                = local.mgmt_vm_computer_name
  location                     = azurerm_resource_group.vdc_rg.location
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  network_interface_ids        = [azurerm_network_interface.bas_if.id]
  size                         = var.management_vm_size
  admin_username               = var.admin_username
  admin_password               = local.password

  dynamic "os_disk" {
    for_each = range(var.use_server_side_disk_encryption ? 1 : 0) 
    content {
      name                     = "${local.mgmt_vm_name}-osdisk"
      caching                  = "ReadWrite"
      disk_encryption_set_id   = azurerm_disk_encryption_set.mgmt_disks.id
      storage_account_type     = "Premium_LRS"
    }
  }

  dynamic "os_disk" {
    for_each = range(var.use_server_side_disk_encryption ? 0 : 1) 
    content {
      name                     = "${local.mgmt_vm_name}-osdisk"
      caching                  = "ReadWrite"
      storage_account_type     = "Premium_LRS"
    }
  }

  source_image_reference {
    publisher                  = "MicrosoftWindowsServer"
    offer                      = var.app_web_image_offer
    sku                        = var.app_web_image_sku
    version                    = "latest"
  }

  # TODO: Does not work with AzureDiskEncryption VM extension
  additional_unattend_content {
    setting                    = "AutoLogon"
    content                    = templatefile("../scripts/host/AutoLogon.xml", { 
      count                    = 99, 
      username                 = var.admin_username, 
      password                 = local.password
    })
  }
  additional_unattend_content {
    setting                    = "FirstLogonCommands"
    content                    = templatefile("../scripts/host/ManagementFirstLogonCommands.xml", { 
      username                 = var.admin_username, 
      password                 = local.password, 
      hosts                    = concat(var.app_web_vms,var.app_db_vms),
      scripturl                = azurerm_storage_blob.mgmt_prepare_script.url,
      sqlserver                = module.paas_app.sql_server_fqdn
    })
  }

  custom_data                  = base64encode(jsonencode(local.client_config))

  # Required for AAD Login
  identity {
    type                       = "SystemAssigned"
  }

  # Not zone redundant, we'll rely on zone redundant Managed Bastion

  depends_on                   = [
                                  azurerm_firewall_application_rule_collection.iag_app_rules,
                                  azurerm_key_vault_access_policy.mgmt_disk_encryption_access,
                                  azurerm_role_assignment.mgmt_disk_encryption_access
                                 ]

  tags                         = local.tags
}

resource null_resource start_mgmt {
  # Always run this
  triggers                     = {
    always_run                 = timestamp()
  }

  provisioner local-exec {
    # Start VM, so we can execute script through SSH
    command                    = "az vm start --ids ${azurerm_windows_virtual_machine.mgmt.id}"
  }
}

resource azurerm_virtual_machine_extension mgmt_roles {
  name                         = "ServerRolesConfiguration"
  virtual_machine_id           = azurerm_windows_virtual_machine.mgmt.id
  publisher                    = "Microsoft.Compute"
  type                         = "CustomScriptExtension"
  type_handler_version         = "1.10"
  auto_upgrade_minor_version   = true
  settings                     = <<EOF
    {
      "fileUris": [
                                 "${azurerm_storage_blob.configure_mgmtvm_roles.url}"
      ]
    }
  EOF

  protected_settings           = <<EOF
    { 
      "commandToExecute"       : "powershell.exe -ExecutionPolicy Unrestricted -Command \"./configure_mgmtvm_roles.ps1\""
    } 
  EOF

  # provisioner local-exec {
  #   # Once extension has provisioned DNS server role, configure DNS on VNet
  #   command                    = "az network vnet update --ids ${azurerm_virtual_network.hub_vnet.id} --dns-servers ${azurerm_network_interface.bas_if.private_ip_address} --query 'dhcpOptions'"
  # }

  tags                         = local.tags
  depends_on                   = [
                                  null_resource.start_mgmt,
                                  azurerm_private_dns_a_record.aut_storage_blob_dns_record
                                 ]
}

resource azurerm_virtual_machine_extension mgmt_monitor {
  name                         = "MMAExtension"
  virtual_machine_id           = azurerm_windows_virtual_machine.mgmt.id
  publisher                    = "Microsoft.EnterpriseCloud.Monitoring"
  type                         = "MicrosoftMonitoringAgent"
  type_handler_version         = "1.0"
  auto_upgrade_minor_version   = true
  settings                     = <<EOF
    {
      "workspaceId"            : "${azurerm_log_analytics_workspace.vcd_workspace.workspace_id}",
      "azureResourceId"        : "${azurerm_windows_virtual_machine.mgmt.id}",
      "stopOnMultipleConnections": "true"
    }
  EOF
  protected_settings = <<EOF
    { 
      "workspaceKey"           : "${azurerm_log_analytics_workspace.vcd_workspace.primary_shared_key}"
    } 
  EOF

# count                        = var.deploy_monitoring_vm_extensions ? 1 : 0
  tags                         = local.tags
  depends_on                   = [null_resource.start_mgmt]
}

resource azurerm_role_assignment vm_admin {
  scope                        = azurerm_resource_group.vdc_rg.id
  role_definition_name         = "Virtual Machine Administrator Login"
  principal_id                 = var.admin_object_id

  count                        = var.admin_object_id != null ? 1 : 0
}

resource azurerm_virtual_machine_extension mgmt_aadlogin {
  name                         = "AADLoginForWindows"
  virtual_machine_id           = azurerm_windows_virtual_machine.mgmt.id
  publisher                    = "Microsoft.Azure.ActiveDirectory"
  type                         = "AADLoginForWindows"
  type_handler_version         = "1.0"
  auto_upgrade_minor_version   = true

  count                        = var.deploy_security_vm_extensions ? 1 : 0
  tags                         = local.tags
  depends_on                   = [
                                  null_resource.start_mgmt,
                                  azurerm_virtual_machine_extension.mgmt_monitor
                                 ]
} 

resource azurerm_virtual_machine_extension mgmt_bginfo {
  name                         = "BGInfo"
  virtual_machine_id           = azurerm_windows_virtual_machine.mgmt.id
  publisher                    = "Microsoft.Compute"
  type                         = "BGInfo"
  type_handler_version         = "2.1"
  auto_upgrade_minor_version   = true

  count                        = var.deploy_non_essential_vm_extensions ? 1 : 0
  tags                         = local.tags
  depends_on                   = [
                                  null_resource.start_mgmt,
                                  azurerm_virtual_machine_extension.mgmt_monitor
                                 ]
}

resource azurerm_virtual_machine_extension mgmt_diagnostics {
  name                         = "Microsoft.Insights.VMDiagnosticsSettings"
  virtual_machine_id           = azurerm_windows_virtual_machine.mgmt.id
  publisher                    = "Microsoft.Azure.Diagnostics"
  type                         = "IaaSDiagnostics"
  type_handler_version         = "1.17"
  auto_upgrade_minor_version   = true

  settings                     = templatefile("./vmdiagnostics.json", { 
    storage_account_name       = azurerm_storage_account.vdc_diag_storage.name, 
    virtual_machine_id         = azurerm_windows_virtual_machine.mgmt.id, 
    application_insights_key   = azurerm_application_insights.vdc_insights.instrumentation_key
  })

  protected_settings = <<EOF
    { 
      "storageAccountName"     : "${azurerm_storage_account.vdc_diag_storage.name}",
      "storageAccountKey"      : "${azurerm_storage_account.vdc_diag_storage.primary_access_key}",
      "storageAccountEndPoint" : "https://core.windows.net"
    } 
  EOF

  count                        = var.deploy_monitoring_vm_extensions ? 1 : 0
  tags                         = local.tags
  depends_on                   = [
                                  null_resource.start_mgmt,
                                  azurerm_virtual_machine_extension.mgmt_monitor,
#                                  azurerm_private_dns_a_record.diag_storage_table_dns_record,
#                                  azurerm_private_dns_a_record.diag_storage_blob_dns_record,
                                  azurerm_firewall_network_rule_collection.iag_net_outbound_http_rules
                                 ]
}
resource azurerm_virtual_machine_extension mgmt_dependency_monitor {
  name                         = "DAExtension"
  virtual_machine_id           = azurerm_windows_virtual_machine.mgmt.id
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

  count                        = var.deploy_monitoring_vm_extensions ? 1 : 0
  tags                         = local.tags
  depends_on                   = [
                                  null_resource.start_mgmt,
                                  azurerm_virtual_machine_extension.mgmt_monitor
                                 ]
}
resource azurerm_virtual_machine_extension mgmt_watcher {
  name                         = "AzureNetworkWatcherExtension"
  virtual_machine_id           = azurerm_windows_virtual_machine.mgmt.id
  publisher                    = "Microsoft.Azure.NetworkWatcher"
  type                         = "NetworkWatcherAgentWindows"
  type_handler_version         = "1.4"
  auto_upgrade_minor_version   = true

  count                        = var.deploy_network_watcher ? 1 : 0
  tags                         = local.tags
  depends_on                   = [
                                  null_resource.start_mgmt,
                                  azurerm_virtual_machine_extension.mgmt_monitor
                                 ]
}

# Delay DiskEncryption to mitigate race condition
resource null_resource mgmt_sleep {
  # Always run this
  triggers                     = {
    mgmt_vm                    = azurerm_windows_virtual_machine.mgmt.id
  }

  provisioner "local-exec" {
    command                    = "Start-Sleep 300"
    interpreter                = ["pwsh", "-nop", "-Command"]
  }

  count                        = (!var.use_server_side_disk_encryption && var.deploy_security_vm_extensions) ? 1 : 0
  depends_on                   = [azurerm_windows_virtual_machine.mgmt]
}
# Does not work with AutoLogon
# use server side encryption with azurerm_disk_encryption_set instead
resource azurerm_virtual_machine_extension mgmt_disk_encryption {
  name                         = "DiskEncryption"
  virtual_machine_id           = azurerm_windows_virtual_machine.mgmt.id
  publisher                    = "Microsoft.Azure.Security"
  type                         = "AzureDiskEncryption"
  type_handler_version         = "2.2"
  auto_upgrade_minor_version   = true

  settings = <<SETTINGS
    {
      "EncryptionOperation"    : "EnableEncryption",
      "KeyVaultURL"            : "${azurerm_key_vault.vault.vault_uri}",
      "KeyVaultResourceId"     : "${azurerm_key_vault.vault.id}",
      "KeyEncryptionKeyURL"    : "${azurerm_key_vault.vault.vault_uri}keys/${azurerm_key_vault_key.disk_encryption_key.name}/${azurerm_key_vault_key.disk_encryption_key.version}",       
      "KekVaultResourceId"     : "${azurerm_key_vault.vault.id}",
      "KeyEncryptionAlgorithm" : "RSA-OAEP",
      "VolumeType"             : "All"
    }
SETTINGS

  count                        = (!var.use_server_side_disk_encryption && var.deploy_security_vm_extensions) ? 1 : 0
  tags                         = local.tags

  depends_on                   = [
                                  azurerm_firewall_application_rule_collection.iag_app_rules,
#                                  azurerm_private_dns_a_record.vault_dns_record,
                                  null_resource.start_mgmt,
                                  null_resource.mgmt_sleep
                                  ]
}

# HACK: Use this as the last resource created for a VM, so we can set a destroy action to happen prior to VM (extensions) destroy
resource azurerm_monitor_diagnostic_setting mgmt_vm {
  name                         = "${azurerm_windows_virtual_machine.mgmt.name}-diagnostics"
  target_resource_id           = azurerm_windows_virtual_machine.mgmt.id
  storage_account_id           = azurerm_storage_account.vdc_diag_storage.id

  metric {
    category                   = "AllMetrics"

    retention_policy {
      enabled                  = false
    }
  }

  # Start VM, so we can destroy VM extensions
  provisioner local-exec {
    command                    = "az vm start --ids ${self.target_resource_id}"
    when                       = destroy
  }

  count                        = var.app_db_vm_number
  depends_on                   = [
#                                  azurerm_private_dns_a_record.diag_storage_table_dns_record,
#                                  azurerm_private_dns_a_record.diag_storage_blob_dns_record,
                                  azurerm_virtual_machine_extension.mgmt_aadlogin,
                                  azurerm_virtual_machine_extension.mgmt_bginfo,
                                  azurerm_virtual_machine_extension.mgmt_dependency_monitor,
                                  azurerm_virtual_machine_extension.mgmt_diagnostics,
                                  azurerm_virtual_machine_extension.mgmt_disk_encryption,
                                  azurerm_virtual_machine_extension.mgmt_monitor,
                                  azurerm_virtual_machine_extension.mgmt_roles,
                                  azurerm_virtual_machine_extension.mgmt_watcher
  ]
}

locals {
  virtual_machine_ids          = concat(module.iis_app.virtual_machine_ids, [azurerm_windows_virtual_machine.mgmt.id])
  virtual_machine_ids_string   = join(",",local.virtual_machine_ids)
}

# Automation account, used for runbooks
resource azurerm_automation_account automation {
  name                         = "${azurerm_resource_group.vdc_rg.name}-automation"
  location                     = local.automation_location
  resource_group_name          = azurerm_resource_group.vdc_rg.name
  sku_name                     = "Basic"
}

resource azurerm_automation_schedule daily {
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
#     command                      = "../scripts/schedule_vm_updates.ps1 -AutomationAccountName ${azurerm_automation_account.automation.name} -ResourceGroupName ${azurerm_automation_account.automation.resource_group_name} -VMResourceId ${local.virtual_machine_ids_string} -Frequency Daily -StartTime ${var.update_management_time}"
#     interpreter                  = ["pwsh", "-nop", "-Command"]
#   }

#   depends_on                     =[
#                                     azurerm_log_analytics_linked_service.automation,
#                                     azurerm_log_analytics_solution.oms_solutions,
# #                                   azurerm_virtual_machine_extension.mgmt_monitor,
# #                                   module.iis_app.monitoring_agent_ids,
#                                     module.iis_app
#                                   ]
# }

# Configure function resources with ARM template as Terraform doesn't (yet) support this
# https://docs.microsoft.com/en-us/azure/templates/microsoft.web/2018-11-01/sites/functions
# resource azurerm_template_deployment update_management {
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
# #                                azurerm_virtual_machine_extension.mgmt_monitor,
# #                                module.iis_app.monitoring_agent_ids,
#                                  module.iis_app
#                                  ]
# }