data "azurerm_client_config" "current" {}
data "azurerm_subscription" "primary" {}

# Random password generator
resource "random_string" "password" {
  length                       = 12
  upper                        = true
  lower                        = true
  number                       = true
  special                      = true
# override_special             = "!@#$%&*()-_=+[]{}<>:?" # default
# Avoid characters that may cause shell scripts to break
  override_special             = "." 
}

# Random resource suffix, this will prevent name collisions when creating resources in parallel
resource "random_string" "suffix" {
  length                       = 4
  upper                        = false
  lower                        = true
  number                       = false
  special                      = false
}

# These variables will be used throughout the Terraform templates
locals {
  # Making sure all character classes are represented, as random does not guarantee that  
  password                     = ".Az9${random_string.password.result}"
  suffix                       = "${var.resource_suffix != "" ? lower(var.resource_suffix) : random_string.suffix.result}" 
  environment                  = "${var.resource_environment != "" ? lower(var.resource_environment) : terraform.workspace}" 
# resource_group               = "${lower(var.resource_prefix)}-${lower(local.environment)}-${lower(local.suffix)}"
  vdc_resource_group           = "${lower(var.resource_prefix)}-${lower(local.environment)}-${lower(local.suffix)}"
  app_resource_group           = "${lower(var.resource_prefix)}-${lower(local.environment)}-app-${lower(local.suffix)}"
  app_hostname                 = "${lower(var.resource_prefix)}apphost"
  app_dns_name                 = "${lower(var.resource_prefix)}app_web_vm"
  admin_ip                     = ["${chomp(data.http.localpublicip.body)}"]
  admin_ip_cidr                = ["${chomp(data.http.localpublicip.body)}/32"]
  admin_ips                    = "${distinct(concat(local.admin_ip,var.admin_ips))}"
  admin_ip_ranges              = "${distinct(concat(local.admin_ip_cidr,var.admin_ip_ranges))}"

  tags                         = "${merge(
    var.tags,
    map(
      "environment",           "${local.environment}",
      "workspace",             "${terraform.workspace}",
      "release-id",            "${var.release_id}",
      "release-url",           "${var.release_web_url}",
      "release-user",          "${var.release_user_email}"
    )
  )}"

  lifecycle {
    ignore_changes             = ["tags"]
  }
}

# Create Azure resource group to be used for VDC resources
resource "azurerm_resource_group" "vdc_rg" {
  name                         = "${local.vdc_resource_group}"
  location                     = "${var.location}"

  tags                         = "${local.tags}"
}

data "http" "localpublicip" {
# Get public IP address of the machine running this terraform template
# url                          = "http://icanhazip.com"
  url                          = "https://ipinfo.io/ip"
}
