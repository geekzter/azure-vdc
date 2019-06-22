# This is the tempale for Managed Bastion, IaaS bastion is defined in management.tf
resource "azurerm_subnet" "managed_bastion_subnet" {
  name                         = "AzureBastionSubnet"
  virtual_network_name         = "${azurerm_virtual_network.vnet.name}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  address_prefix               = "${var.vdc_vnet["bastion_subnet"]}"
}

resource "azurerm_public_ip" "managed_bastion_pip" {
  name                         = "${azurerm_resource_group.vdc_rg.name}-managed-bastion-pip"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  allocation_method            = "Static"
  sku                          = "Standard"
}

# Configure Managed Bastion with ARM template as Terraform doesn't (yet) support this (preview) service
# https://docs.microsoft.com/en-us/azure/templates/microsoft.web/2018-11-01/sites/functions
resource "azurerm_template_deployment" "managed_bastion" {
  name                         = "${azurerm_resource_group.vdc_rg.name}-managed-bastion-template"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  deployment_mode              = "Incremental"

  template_body                = <<DEPLOY
{
    "$schema": "http://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "location": {
            "type": "String"
        },
        "resourceGroup": {
            "type": "String"
        },
        "bastionHostName": {
            "type": "String"
        },
        "subnetId": {
            "type": "String"
        },
        "publicIpAddressName": {
            "type": "String"
        }
    },
    "resources": [
        {
            "type": "Microsoft.Network/bastionHosts",
            "apiVersion": "2018-10-01",
            "name": "[parameters('bastionHostName')]",
            "location": "[parameters('location')]",
            "tags": {},
            "properties": {
                "ipConfigurations": [
                    {
                        "name": "IpConf",
                        "properties": {
                            "subnet": {
                                "id": "[parameters('subnetId')]"
                            },
                            "publicIPAddress": {
                                "id": "[resourceId(parameters('resourceGroup'), 'Microsoft.Network/publicIpAddresses', parameters('publicIpAddressName'))]"
                            }
                        }
                    }
                ]
            }
        }
    ]
}
DEPLOY

  parameters                   = {
    location                   = "${azurerm_resource_group.vdc_rg.location}"
    resourceGroup              = "${azurerm_resource_group.vdc_rg.name}"
    bastionHostName            = "${azurerm_resource_group.vdc_rg.name}-managed-bastion"
    subnetId                   = "${azurerm_subnet.managed_bastion_subnet.id}"
    publicIpAddressName        = "${azurerm_public_ip.managed_bastion_pip.name}"
  }

  depends_on                   = ["azurerm_subnet.managed_bastion_subnet","azurerm_public_ip.managed_bastion_pip"] # Explicit dependency for ARM templates
}