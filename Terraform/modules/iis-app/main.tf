locals {
  app_hostname                 = "${lower(var.resource_environment)}apphost"
  app_dns_name                 = "${lower(var.resource_environment)}app_web_vm"
  db_hostname                  = "${lower(var.resource_environment)}dbhost"
  db_dns_name                  = "${lower(var.resource_environment)}db_web_vm"
  vdc_resource_group_name      = "${element(split("/",var.vdc_resource_group_id),length(split("/",var.vdc_resource_group_id))-1)}"
  watcher_name                 = "${element(split("/",var.diagnostics_watcher_id),length(split("/",var.diagnostics_watcher_id))-1)}"
}

resource "azurerm_resource_group" "app_rg" {
  name                         = "${var.resource_group}"
  location                     = "${var.location}"

  tags                         = "${var.tags}"
}

resource "azurerm_availability_set" "app_web_avset" {
  name                         = "${azurerm_resource_group.app_rg.name}-web-avset"
  location                     = "${azurerm_resource_group.app_rg.location}"
  resource_group_name          = "${azurerm_resource_group.app_rg.name}"
  platform_fault_domain_count  = 3
  platform_update_domain_count = 3
  managed                      = true

  tags                         = "${var.tags}"

  depends_on                   = ["azurerm_resource_group.app_rg"]
}

resource "azurerm_network_interface" "app_web_if" {
  name                         = "${azurerm_resource_group.app_rg.name}-web-nic${count.index}"
  location                     = "${azurerm_resource_group.app_rg.location}"
  resource_group_name          = "${azurerm_resource_group.app_rg.name}"
  count                        = 2

  ip_configuration {
    name                       = "app_web_ipconfig"
    subnet_id                  = "${var.app_subnet_id}"
    private_ip_address         = "${element(var.app_web_vms, count.index)}"
    private_ip_address_allocation = "Static"
  }

  tags                         = "${var.tags}"
}

resource "azurerm_virtual_machine" "app_web_vm" {
  name                         = "${azurerm_resource_group.app_rg.name}-web-vm${count.index}"
  location                     = "${azurerm_resource_group.app_rg.location}"
  resource_group_name          = "${azurerm_resource_group.app_rg.name}"
  availability_set_id          = "${azurerm_availability_set.app_web_avset.id}"
  vm_size                      = "${var.app_web_vm_size}"
  network_interface_ids        = ["${element(azurerm_network_interface.app_web_if.*.id, count.index)}"]
  # Make zone redundant
# zones                        = ["${count.index % 3}"]
  count                        = 2

  storage_image_reference {
    publisher                  = "${var.app_web_image_publisher}"
    offer                      = "${var.app_web_image_offer}"
    sku                        = "${var.app_web_image_sku}"
    version                    = "${var.app_web_image_version}"
  }
  # Uncomment this line to delete the OS disk automatically when deleting the VM
    delete_os_disk_on_termination = true

  # Uncomment this line to delete the data disks automatically when deleting the VM
    delete_data_disks_on_termination = true

  storage_os_disk {
    name                       = "${azurerm_resource_group.app_rg.name}-web-vm${count.index}-osdisk"
    caching                    = "ReadWrite"
    create_option              = "FromImage"
    managed_disk_type          = "Premium_LRS"
  }

 # Optional data disks
  storage_data_disk {
    name                       = "${azurerm_resource_group.app_rg.name}-web-vm${count.index}-datadisk"
    managed_disk_type          = "Premium_LRS"
    create_option              = "Empty"
    lun                        = 0
    disk_size_gb               = "1023"
  }

  os_profile {
    computer_name              = "${local.app_hostname}${count.index}"
    admin_username             = "${var.admin_username}"
    admin_password             = "${var.admin_password}"
  }

  os_profile_windows_config {
    provision_vm_agent         = true
    enable_automatic_upgrades  = true
  }
    
  # Required for AAD Login
  identity {
    type                       = "SystemAssigned"
  }
  
  provisioner "local-exec" {
    # cmdkey.exe /generic:${element(var.app_web_vms, count.index)} /user:${var.admin_username} /pass:${var.admin_password}
    command                    = <<EOF
      echo To connect to application VM${count.index}, from the Bastion type:
      echo type 'mstsc.exe /v:${element(var.app_web_vms, count.index)}'
    EOF
  }

  tags                         = "${var.tags}"
}

resource "azurerm_virtual_machine_extension" "app_web_vm_watcher" {
  name                         = "app_web_vm_watcher"
  location                     = "${azurerm_resource_group.app_rg.location}"
  resource_group_name          = "${azurerm_resource_group.app_rg.name}"
  virtual_machine_name         = "${element(azurerm_virtual_machine.app_web_vm.*.name, count.index)}"
  publisher                    = "Microsoft.Azure.NetworkWatcher"
  type                         = "NetworkWatcherAgentWindows"
  type_handler_version         = "1.4"
  auto_upgrade_minor_version   = true
  count                        = 2

  tags                         = "${var.tags}"
}
resource "azurerm_virtual_machine_extension" "app_web_vm_bginfo" {
  name                        = "app_web_vm_bginfo"
  location                    = "${azurerm_resource_group.app_rg.location}"
  resource_group_name         = "${azurerm_resource_group.app_rg.name}"
  virtual_machine_name        = "${element(azurerm_virtual_machine.app_web_vm.*.name, count.index)}"
  publisher                   = "Microsoft.Compute"
  type                        = "BGInfo"
  type_handler_version        = "2.1"
  auto_upgrade_minor_version  = true
  count                       = 2

  tags                         = "${var.tags}"
}

resource "azurerm_virtual_machine_extension" "app_web_vm_pipeline" {
  name                        = "app_web_vm_release"
  location                    = "${azurerm_resource_group.app_rg.location}"
  resource_group_name         = "${azurerm_resource_group.app_rg.name}"
  virtual_machine_name        = "${element(azurerm_virtual_machine.app_web_vm.*.name, count.index)}"
  publisher                   = "Microsoft.VisualStudio.Services"
  type                        = "TeamServicesAgent"
  type_handler_version        = "1.26"
  auto_upgrade_minor_version  = true
  count                       = 2
  settings                    = <<EOF
    {
      "VSTSAccountName": "${var.app_devops["account"]}",        
      "TeamProject": "${var.app_devops["team_project"]}",
      "DeploymentGroup": "${var.app_devops["web_deployment_group"]}",
      "AgentName": "${local.app_hostname}${count.index}",
      "Tags": "${var.resource_environment}"
    }
  EOF

  protected_settings = <<EOF
    { 
      "PATToken": "${var.app_devops["pat"]}" 
    } 
  EOF

  tags                         = "${merge(
    var.tags,
    map(
      "dummy-dependency",        "${var.release_agent_dependency}"
    )
  )}"
}

resource "azurerm_network_connection_monitor" "devops_watcher" {
# name                         = "${element(azurerm_virtual_machine.app_web_vm.*.name, count.index)}-devops-watcher"
  name                         = "${local.app_hostname}${count.index}-${var.app_devops["account"]}.visualstudio.com"
  location                     = "${var.location}"
  resource_group_name          = "${local.vdc_resource_group_name}"
  network_watcher_name         = "${local.watcher_name}"

  auto_start                   = true
  interval_in_seconds          = 60
  source {
    virtual_machine_id         = "${element(azurerm_virtual_machine.app_db_vm.*.id, count.index)}"
  }

  destination {
    address                    = "${var.app_devops["account"]}.visualstudio.com"
    port                       = 443
  }
  count                        = "${var.deploy_connection_monitors ? 2 : 0}"  

  depends_on                   = ["azurerm_virtual_machine_extension.app_web_vm_watcher"]

  tags                         = "${var.tags}"
}

resource "azurerm_availability_set" "app_db_avset" {
  name                         = "${azurerm_resource_group.app_rg.name}-db-avset"
  location                     = "${azurerm_resource_group.app_rg.location}"
  resource_group_name          = "${azurerm_resource_group.app_rg.name}"
  platform_fault_domain_count  = 3
  platform_update_domain_count = 3
  managed                      = true

  tags                         = "${var.tags}"
  depends_on                   = ["azurerm_resource_group.app_rg"]
}

resource "azurerm_lb" "app_db_lb" {
  resource_group_name          = "${azurerm_resource_group.app_rg.name}"
  name                         = "${azurerm_resource_group.app_rg.name}-db-lb"
  location                     = "${azurerm_resource_group.app_rg.location}"

  frontend_ip_configuration {
    name                       = "LoadBalancerFrontEnd"
    subnet_id                  = "${var.data_subnet_id}"
    private_ip_address         = "${var.app_db_lb_address}"
  }

  tags                         = "${var.tags}"
}

resource "azurerm_lb_backend_address_pool" "app_db_backend_pool" {
  name                         = "BackendPool1"
  resource_group_name          = "${azurerm_resource_group.app_rg.name}"
  loadbalancer_id              = "${azurerm_lb.app_db_lb.id}"

}

resource "azurerm_lb_rule" "app_db_lb_rule_tds" {
  resource_group_name          = "${azurerm_resource_group.app_rg.name}"
  loadbalancer_id              = "${azurerm_lb.app_db_lb.id}"
  name                         = "LBRule"
  protocol                     = "tcp"
  frontend_port                = 1423
  backend_port                 = 1423
  frontend_ip_configuration_name = "LoadBalancerFrontEnd"
  enable_floating_ip           = false
  backend_address_pool_id      = "${azurerm_lb_backend_address_pool.app_db_backend_pool.id}"
  idle_timeout_in_minutes      = 5
  probe_id                     = "${azurerm_lb_probe.app_db_lb_probe_tds.id}"

  depends_on                   = ["azurerm_lb_probe.app_db_lb_probe_tds"]

}

resource "azurerm_lb_probe" "app_db_lb_probe_tds" {
  resource_group_name          = "${azurerm_resource_group.app_rg.name}"
  loadbalancer_id              = "${azurerm_lb.app_db_lb.id}"
  name                         = "TcpProbe"
  protocol                     = "tcp"
  port                         = 1423
  interval_in_seconds          = 5
  number_of_probes             = 2
}

resource "azurerm_network_interface" "app_db_if" {
  name                         = "${azurerm_resource_group.app_rg.name}-db-nic${count.index}"
  location                     = "${azurerm_resource_group.app_rg.location}"
  resource_group_name          = "${azurerm_resource_group.app_rg.name}"
  count                        = 2

  ip_configuration {
    name                       = "app_db_ipconfig"
    subnet_id                  = "${var.data_subnet_id}"
    private_ip_address         = "${element(var.app_db_vms, count.index)}"
    private_ip_address_allocation = "Static"
  }

  tags                         = "${var.tags}"
}

resource "azurerm_network_interface_backend_address_pool_association" "app_db_if_backend_pool" {
  network_interface_id         = "${element(azurerm_network_interface.app_db_if.*.id, count.index)}"
  ip_configuration_name        = "${element(azurerm_network_interface.app_db_if.*.ip_configuration.0.name, count.index)}"
  backend_address_pool_id      = "${azurerm_lb_backend_address_pool.app_db_backend_pool.id}"
  count                        = 2
}

resource "azurerm_virtual_machine" "app_db_vm" {
  name                         = "${azurerm_resource_group.app_rg.name}-db-vm${count.index}"
  location                     = "${azurerm_resource_group.app_rg.location}"
  resource_group_name          = "${azurerm_resource_group.app_rg.name}"
  availability_set_id          = "${azurerm_availability_set.app_db_avset.id}"
  vm_size                      = "${var.app_db_vm_size}"
  network_interface_ids        = ["${element(azurerm_network_interface.app_db_if.*.id, count.index)}"]
  # Make zone redundant (# VM's > 2, =< 3)
  #zones                        = ["${count.index % 3}"]
  count                        = 2

  storage_image_reference {
    publisher                  = "${var.app_db_image_publisher}"
    offer                      = "${var.app_db_image_offer}"
    sku                        = "${var.app_db_image_sku}"
    version                    = "${var.app_db_image_version}"
  }
  # Uncomment this line to delete the OS disk automatically when deleting the VM
    delete_os_disk_on_termination = true

  # Uncomment this line to delete the data disks automatically when deleting the VM
    delete_data_disks_on_termination = true

  storage_os_disk {
    name                       = "${azurerm_resource_group.app_rg.name}-db-vm${count.index}-osdisk"
    caching                    = "ReadWrite"
    create_option              = "FromImage"
    managed_disk_type          = "Premium_LRS"
  }

 # Optional data disks
  storage_data_disk {
    name                       = "${azurerm_resource_group.app_rg.name}-db-vm${count.index}-datadisk"
    managed_disk_type          = "Premium_LRS"
    create_option              = "Empty"
    lun                        = 0
    disk_size_gb               = "1023"
  }

  os_profile {
    computer_name              = "${local.app_hostname}${count.index}"
    admin_username             = "${var.admin_username}"
    admin_password             = "${var.admin_password}"
  }

  os_profile_windows_config {
    provision_vm_agent         = true
    enable_automatic_upgrades  = true
  }

  # Required for AAD Login
  identity {
    type                       = "SystemAssigned"
  }
  
  provisioner "local-exec" {
    # cmdkey.exe /generic:${element(var.app_db_vms, count.index)} /user:${var.admin_username} /pass:${var.admin_password}
    command                    = <<EOF
      echo To connect to application VM${count.index}, from the Bastion type:
      echo type 'mstsc.exe /v:${element(var.app_db_vms, count.index)}'
    EOF
  }

  tags                         = "${var.tags}"
}

resource "azurerm_virtual_machine_extension" "app_db_vm_watcher" {
  name                         = "app_db_vm_watcher"
  location                     = "${azurerm_resource_group.app_rg.location}"
  resource_group_name          = "${azurerm_resource_group.app_rg.name}"
  virtual_machine_name         = "${element(azurerm_virtual_machine.app_db_vm.*.name, count.index)}"
  publisher                    = "Microsoft.Azure.NetworkWatcher"
  type                         = "NetworkWatcherAgentWindows"
  type_handler_version         = "1.4"
  auto_upgrade_minor_version   = true
  count                        = 2

  tags                         = "${var.tags}"
}
resource "azurerm_virtual_machine_extension" "app_db_vm_bginfo" {
  name                         = "app_db_vm_bginfo"
  location                     = "${azurerm_resource_group.app_rg.location}"
  resource_group_name          = "${azurerm_resource_group.app_rg.name}"
  virtual_machine_name         = "${element(azurerm_virtual_machine.app_db_vm.*.name, count.index)}"
  publisher                    = "Microsoft.Compute"
  type                         = "BGInfo"
  type_handler_version         = "2.1"
  auto_upgrade_minor_version   = true
  count                        = 2

  tags                         = "${var.tags}"
}

resource "azurerm_virtual_machine_extension" "app_db_vm_pipeline" {
  name                         = "app_db_vm_release"
  location                     = "${azurerm_resource_group.app_rg.location}"
  resource_group_name          = "${azurerm_resource_group.app_rg.name}"
  virtual_machine_name         = "${element(azurerm_virtual_machine.app_db_vm.*.name, count.index)}"
  publisher                    = "Microsoft.VisualStudio.Services"
  type                         = "TeamServicesAgent"
  type_handler_version         = "1.26"
  auto_upgrade_minor_version   = true
  count                        = 2
  settings                     = <<EOF
    {
      "VSTSAccountName": "${var.app_devops["account"]}",        
      "TeamProject": "${var.app_devops["team_project"]}",
      "DeploymentGroup": "${var.app_devops["db_deployment_group"]}",
      "AgentName": "${local.db_hostname}${count.index}",
      "Tags": "${var.resource_environment}"
    }
  EOF

  protected_settings = <<EOF
    { 
      "PATToken": "${var.app_devops["pat"]}" 
    } 
  EOF

  tags                         = "${merge(
    var.tags,
    map(
      "dummy-dependency",        "${var.release_agent_dependency}"
    )
  )}"
}

resource "azurerm_monitor_diagnostic_setting" "db_lb_logs" {
  name                         = "${azurerm_lb.app_db_lb.name}-logs"
  target_resource_id           = "${azurerm_lb.app_db_lb.id}"
  storage_account_id           = "${var.diagnostics_storage_id}"
  log_analytics_workspace_id   = "${var.diagnostics_workspace_id}"

  log {
    category                   = "LoadBalancerAlertEvent"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }

  log {
    category                   = "LoadBalancerProbeHealthStatus"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }
}