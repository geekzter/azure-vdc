
resource "azurerm_network_interface" "bas_if" {
  name                         = "${azurerm_resource_group.vdc_rg.name}-bastion-if"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
# Security group is associated at the Management subnet level
# network_security_group_id    = "${azurerm_network_security_group.mgmt_nsg.id}"

  ip_configuration {
    name                       = "bas_ipconfig"
    subnet_id                  = "${azurerm_subnet.mgmt_subnet.id}"
    private_ip_address         = "${var.vdc_vnet["bastion_address"]}"
    private_ip_address_allocation = "static"
  }

  tags                         = "${local.tags}"
}

data "template_file" "bastion_first_commands" {
  template = "${file("../Scripts/FirstLogonCommands.xml")}"

  vars                         = {
    host                       = "${azurerm_public_ip.iag_pip.ip_address}"
    port                       = "${var.rdp_port}"
    username                   = "${var.admin_username}"
    password                   = "${local.password}"
  }
}

resource "azurerm_virtual_machine" "bastion" {
  name                         = "${azurerm_resource_group.vdc_rg.name}-bastion"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  network_interface_ids        = ["${azurerm_network_interface.bas_if.id}"]
  vm_size                      = "Standard_D2s_v3"

  # Uncomment this line to delete the OS disk automatically when deleting the VM
  delete_os_disk_on_termination = true

  # Uncomment this line to delete the data disks automatically when deleting the VM
  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher                  = "MicrosoftWindowsServer"
    offer                      = "WindowsServer"
    sku                        = "2016-Datacenter"
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
    disk_size_gb               = "1023"
  }

  os_profile {
    computer_name              = "bastion"
    admin_username             = "${var.admin_username}"
    admin_password             = "${local.password}"
  }

  os_profile_windows_config {
    provision_vm_agent         = true
    enable_automatic_upgrades  = true


    additional_unattend_config {
      pass                     = "oobeSystem"
      component                = "Microsoft-Windows-Shell-Setup"
      setting_name             = "FirstLogonCommands"
      # TODO: Add DB VM's
      content                  = "<FirstLogonCommands><SynchronousCommand><CommandLine>cmdkey.exe /generic:${element(var.app_web_vms, 0)} /user:${var.admin_username} /pass:${local.password}</CommandLine><Description>Save RDP credentials</Description><Order>1</Order></SynchronousCommand><SynchronousCommand><CommandLine>cmdkey.exe /generic:${element(var.app_web_vms, 1)} /user:${var.admin_username} /pass:${local.password}</CommandLine><Description>Save RDP credentials</Description><Order>2</Order></SynchronousCommand></FirstLogonCommands>"
    }
  }

  # Required for AAD Login
  identity {
    type                       = "SystemAssigned"
  }

  /*
  # TODO: Windows only
  provisioner "local-exec" {
    command                    = <<EOF
      cmdkey.exe /generic:${azurerm_public_ip.iag_pip.ip_address}:${var.rdp_port} /user:${var.admin_username} /pass:${local.password}
      cmdkey.exe /generic:${var.vdc_vnet["bastion_address"]} /user:${var.admin_username} /pass:${local.password}
      echo To connect to bastion, type:
      echo type 'mstsc.exe /v:${azurerm_public_ip.bas_pip.ip_address}'
      echo or (if connected via VPN):
      echo type 'mstsc.exe /v:${var.vdc_vnet["bastion_address"]}'
    EOF
  }
  */

  tags                         = "${local.tags}"
}

/* resource "azurerm_virtual_machine_extension" "bastion_aadlogin" {
# name                         = "${azurerm_virtual_machine.bastion.name}/AADLoginForWindows"
  name                         = "AADLoginForWindows"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  virtual_machine_name         = "${azurerm_virtual_machine.bastion.name}"
  publisher                    = "Microsoft.Azure.ActiveDirectory"
  type                         = "AADLoginForWindows"
  type_handler_version         = "0.3"
  auto_upgrade_minor_version   = true

  tags                         = "${local.tags}"
} */

resource "azurerm_virtual_machine_extension" "bastion_bginfo" {
  name                         = "bastion_bginfo"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  virtual_machine_name         = "${azurerm_virtual_machine.bastion.name}"
  publisher                    = "Microsoft.Compute"
  type                         = "BGInfo"
  type_handler_version         = "2.1"
  auto_upgrade_minor_version   = true

  tags                         = "${local.tags}"
}