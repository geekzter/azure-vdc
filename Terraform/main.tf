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
  workspace_location           = "${var.workspace_location != "" ? var.workspace_location : var.location}" 
  automation_location          = "${var.automation_location != "" ? var.automation_location : local.workspace_location}" 
  password                     = ".Az9${random_string.password.result}"
  suffix                       = "${var.resource_suffix != "" ? lower(var.resource_suffix) : random_string.suffix.result}" 
  environment                  = "${var.resource_environment != "" ? lower(var.resource_environment) : terraform.workspace}" 
  vdc_resource_group           = "${lower(var.resource_prefix)}-${lower(local.environment)}-${lower(local.suffix)}"
  iaas_app_resource_group      = "${lower(var.resource_prefix)}-${lower(local.environment)}-iaasapp-${lower(local.suffix)}"
  paas_app_resource_group      = "${lower(var.resource_prefix)}-${lower(local.environment)}-paasapp-${lower(local.suffix)}"
  app_hostname                 = "${lower(local.environment)}apphost"
  app_dns_name                 = "${lower(local.environment)}app_web_vm"
  db_hostname                  = "${lower(local.environment)}dbhost"
  db_dns_name                  = "${lower(local.environment)}db_web_vm"
  admin_ip                     = ["${chomp(data.http.localpublicip.body)}"]
  admin_ip_cidr                = ["${chomp(data.http.localpublicip.body)}/30"] # /32 not allowed in network_rules
  admin_ips                    = "${setunion(local.admin_ip,var.admin_ips)}"
  admin_ip_ranges              = "${setunion([for ip in local.admin_ips : format("%s/30", ip)],var.admin_ip_ranges)}" # /32 not allowed in network_rules
  admin_cidr_ranges            = "${[for range in local.admin_ip_ranges : cidrsubnet(range,0,0)]}" # Make sure ranges have correct base address

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

  lifecycle                    = {
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
  url                          = "http://ipinfo.io/ip"
# url                          = "https://ipapi.co/ip" 
}

# Automation account, used for runbooks
resource "azurerm_automation_account" "automation" {
  name                         = "${azurerm_resource_group.vdc_rg.name}-automation"
  location                     = "${local.automation_location}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  sku_name                     = "Basic"
}