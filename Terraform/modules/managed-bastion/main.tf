# This is the tempale for Managed Bastion, IaaS bastion is defined in management.tf
resource "azurerm_subnet" "managed_bastion_subnet" {
  name                         = "AzureBastionSubnet"
  virtual_network_name         = "${var.virtual_network_name}"
  resource_group_name          = "${var.resource_group}"
  address_prefix               = "${var.subnet_range}"
}

resource "azurerm_public_ip" "managed_bastion_pip" {
  name                         = "${var.resource_group}-managed-bastion-pip"
  location                     = "${var.location}"
  resource_group_name          = "${var.resource_group}"
  allocation_method            = "Static"
  sku                          = "Standard"
  # Zone redundant
  #zones                        = ["1", "2", "3"]
}

# Configure Managed Bastion with ARM template as Terraform doesn't (yet) support this (preview) service
# https://docs.microsoft.com/en-us/azure/templates/microsoft.web/2018-11-01/sites/functions
resource "azurerm_template_deployment" "managed_bastion" {
  name                         = "${var.resource_group}-managed-bastion-template"
  resource_group_name          = "${var.resource_group}"
  deployment_mode              = "Incremental"
  template_body                = "${file("${path.module}/bastion.json")}"

  parameters                   = {
    location                   = "${var.location}"
    resourceGroup              = "${var.resource_group}"
    bastionHostName            = "${var.resource_group}-managed-bastion"
    subnetId                   = "${azurerm_subnet.managed_bastion_subnet.id}"
    publicIpAddressName        = "${azurerm_public_ip.managed_bastion_pip.name}"
  }

  count                        = "${var.deploy_managed_bastion ? 1 : 0}"

  depends_on                   = ["azurerm_subnet.managed_bastion_subnet","azurerm_public_ip.managed_bastion_pip"] # Explicit dependency for ARM templates
}