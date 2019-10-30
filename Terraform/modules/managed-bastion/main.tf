locals {
  managed_bastion_name         = "${local.virtual_network_name}-managed-bastion"
  resource_group_name          = "${element(split("/",var.resource_group_id),length(split("/",var.resource_group_id))-1)}"
  virtual_network_name         = "${element(split("/",var.virtual_network_id),length(split("/",var.virtual_network_id))-1)}"
}

# This is the tempale for Managed Bastion, IaaS bastion is defined in management.tf
resource "azurerm_subnet" "managed_bastion_subnet" {
  name                         = "AzureBastionSubnet"
  virtual_network_name         = "${local.virtual_network_name}"
  resource_group_name          = "${local.resource_group_name}"
  address_prefix               = "${var.subnet_range}"
}

resource "azurerm_public_ip" "managed_bastion_pip" {
  name                         = "${local.virtual_network_name}-managed-bastion-pip"
  location                     = "${var.location}"
  resource_group_name          = "${local.resource_group_name}"
  allocation_method            = "Static"
  sku                          = "Standard" # Zone redundant
}

/* 
# Configure Managed Bastion with ARM template as Terraform doesn't (yet) support this (preview) service
# https://docs.microsoft.com/en-us/azure/templates/microsoft.web/2018-11-01/sites/functions
resource "azurerm_template_deployment" "managed_bastion" {
  name                         = "${local.virtual_network_name}-managed-bastion-template"
  resource_group_name          = "${local.resource_group_name}"
  deployment_mode              = "Incremental"
  template_body                = "${file("${path.module}/bastion.json")}"

  parameters                   = {
    location                   = "${var.location}"
    resourceGroup              = "${local.resource_group_name}"
    bastionHostName            = "${local.managed_bastion_name}"
    subnetId                   = "${azurerm_subnet.managed_bastion_subnet.id}"
    publicIpAddressName        = "${azurerm_public_ip.managed_bastion_pip.name}"
  }

  count                        = "${var.deploy_managed_bastion ? 1 : 0}"

  depends_on                   = ["azurerm_subnet.managed_bastion_subnet","azurerm_public_ip.managed_bastion_pip"] # Explicit dependency for ARM templates
} 
*/

resource "azurerm_bastion_host" "managed_bastion" {
  name                         = "${replace(local.virtual_network_name,"-","")}managedbastion"
  location                     = "${var.location}"
  resource_group_name          = "${local.resource_group_name}"

  ip_configuration {
    name                       = "configuration"
    subnet_id                  = "${azurerm_subnet.managed_bastion_subnet.id}"
    public_ip_address_id       = "${azurerm_public_ip.managed_bastion_pip.id}"
  }

  count                        = "${var.deploy_managed_bastion ? 1 : 0}"
}