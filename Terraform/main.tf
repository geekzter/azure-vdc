# Random password generator
resource "random_string" "password" {
  length                      = 12
  upper                       = true
  lower                       = true
  number                      = true
  special                     = true
# override_special            = "!@#$%&*()-_=+[]{}<>:?" # default
# Avoid characters that may cause shell scripts to break
  override_special            = "." 
}

# Random resource suffix, this will prevent name collisions when creating resources in parallel
resource "random_string" "suffix" {
  length                      = 4
  upper                       = false
  lower                       = true
  number                      = false
  special                     = false
}

# These variables will be used throughout the Terraform templates
locals {
  # Making sure all character classes are represented, as random does not guarantee that  
  password                    = ".Az9${random_string.password.result}"
  suffix                      = "${var.resource_suffix != "" ? lower(var.resource_suffix) : random_string.suffix.result}" 
  vdc_resource_group          = "${lower(var.resource_prefix)}-vdc-${lower(local.suffix)}"
  app_resource_group          = "${lower(var.resource_prefix)}-app-${lower(local.suffix)}"
  app_hostname                = "${lower(var.resource_prefix)}apphost"
  app_dns_name                = "${lower(var.resource_prefix)}app_web_vm"
  admin_ip_tf                 = ["${chomp(data.http.localpublicip.body)}/32"]
  admin_ip_ranges_var         = "${var.admin_ip_ranges}"
  admin_ip_ranges             = "${concat(local.admin_ip_tf,local.admin_ip_ranges_var)}"
}

# Create Azure resource group to be used for VDC resources
resource "azurerm_resource_group" "vdc_rg" {
  name                        = "${local.vdc_resource_group}"
  location                    = "${var.location}"
}

data "http" "localpublicip" {
# Get public IP address of the machine running this terraform template
#                         url = "http://icanhazip.com"
                          url = "https://ipinfo.io/ip"
}

# Automation account, used for runbooks
resource "azurerm_automation_account" "automation" {
  name                         = "${azurerm_resource_group.vdc_rg.name}-automation"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"

  sku {
    name = "Basic"
  }
}