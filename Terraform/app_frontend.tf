resource "azurerm_resource_group" "app_rg" {
  name                        = "${local.app_resource_group}"
  location                    = "${var.location}"
}

resource "azurerm_availability_set" "app_web_avset" {
  name                        = "${azurerm_resource_group.app_rg.name}-web-avset"
  location                    = "${azurerm_resource_group.app_rg.location}"
  resource_group_name         = "${azurerm_resource_group.app_rg.name}"
  platform_fault_domain_count = 2
  platform_update_domain_count= 2
  managed                     = true
}

resource "azurerm_network_interface" "app_web_if" {
  name                        = "${azurerm_resource_group.app_rg.name}-web-nic${count.index}"
  location                    = "${azurerm_resource_group.app_rg.location}"
  resource_group_name         = "${azurerm_resource_group.app_rg.name}"
  count                       = 2

  ip_configuration {
    name                      = "app_web_ipconfig"
    subnet_id                 = "${azurerm_subnet.app_subnet.id}"
    private_ip_address        = "${element(var.app_web_vms, count.index)}"
    private_ip_address_allocation           = "Static"
  }
}

resource "azurerm_virtual_machine" "app_web_vm" {
  name                        = "${azurerm_resource_group.app_rg.name}-web-vm${count.index}"
  location                    = "${azurerm_resource_group.app_rg.location}"
  resource_group_name         = "${azurerm_resource_group.app_rg.name}"
  availability_set_id         = "${azurerm_availability_set.app_web_avset.id}"
  vm_size                     = "${var.app_web_vm_size}"
  network_interface_ids       = ["${element(azurerm_network_interface.app_web_if.*.id, count.index)}"]
  count                       = 2

  storage_image_reference {
    publisher                 = "${var.app_web_image_publisher}"
    offer                     = "${var.app_web_image_offer}"
    sku                       = "${var.app_web_image_sku}"
    version                   = "${var.app_web_image_version}"
  }
  # Uncomment this line to delete the OS disk automatically when deleting the VM
    delete_os_disk_on_termination = true

  # Uncomment this line to delete the data disks automatically when deleting the VM
    delete_data_disks_on_termination = true

  storage_os_disk {
    name                      = "${azurerm_resource_group.app_rg.name}-web-vm${count.index}-osdisk"
    caching                   = "ReadWrite"
    create_option             = "FromImage"
    managed_disk_type         = "Premium_LRS"
  }

 # Optional data disks
  storage_data_disk {
    name                      = "${azurerm_resource_group.app_rg.name}-web-vm${count.index}-datadisk"
    managed_disk_type         = "Premium_LRS"
    create_option             = "Empty"
    lun                       = 0
    disk_size_gb              = "1023"
  }

  os_profile {
    computer_name             = "${local.app_hostname}${count.index}"
    admin_username            = "${var.admin_username}"
    admin_password            = "${local.password}"
  }

  os_profile_windows_config {
    provision_vm_agent        = true
    enable_automatic_upgrades = true
  }
  
  provisioner "local-exec" {
    command                   = <<EOF
      cmdkey.exe /generic:${element(var.app_web_vms, count.index)} /user:${var.admin_username} /pass:${local.password}
      echo To connect to application VM${count.index}, from the Bastion type:
      echo type 'mstsc.exe /v:${element(var.app_web_vms, count.index)}'
    EOF
  }
}

resource "azurerm_virtual_machine_extension" "app_web_vm_watcher" {
  name                        = "app_web_vm_watcher"
  location                    = "${azurerm_resource_group.app_rg.location}"
  resource_group_name         = "${azurerm_resource_group.app_rg.name}"
  virtual_machine_name        = "${element(azurerm_virtual_machine.app_web_vm.*.name, count.index)}"
  publisher                   = "Microsoft.Azure.NetworkWatcher"
  type                        = "NetworkWatcherAgentWindows"
  type_handler_version        = "1.4"
  auto_upgrade_minor_version  = true
  count                       = 2
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
}

resource "azurerm_virtual_machine_extension" "app_web_vm_pipeline" {
  name                        = "app_web_vm_release"
  location                    = "${azurerm_resource_group.app_rg.location}"
  resource_group_name         = "${azurerm_resource_group.app_rg.name}"
  virtual_machine_name        = "${element(azurerm_virtual_machine.app_web_vm.*.name, count.index)}"
  publisher                   = "Microsoft.VisualStudio.Services"
  type                        = "TeamServicesAgent"
  type_handler_version        = "1.23"
  auto_upgrade_minor_version  = true
  count                       = 2
  settings                    = <<EOF
    {
      "VSTSAccountName": "${var.app_devops["account"]}",        
      "VSTSAccountUrl": "https://${var.app_devops["account"]}.visualstudio.com", 
      "TeamProject": "${var.app_devops["team_project"]}",
      "DeploymentGroup": "${var.app_devops["web_deployment_group"]}"
    }
  EOF

  protected_settings = <<EOF
    { 
      "PATToken": "${var.app_devops["pat"]}" 
    } 
  EOF
}