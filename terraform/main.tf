data "azurerm_client_config" "current" {}
data "azurerm_subscription" "primary" {}

# FIX: Required for Azure Cloud Shell (azurerm_client_config.current.object_id not populated)
# HACK: Retrieve user objectId in case it is not exposed in azurerm_client_config.current.object_id
data external account_info {
  program                      = [
                                 "az",
                                 "ad",
                                 "signed-in-user",
                                 "show",
                                 "--query",
                                 "{object_id:objectId}",
                                 "-o",
                                 "json",
                                 ]
  count                        = data.azurerm_client_config.current.object_id != null && data.azurerm_client_config.current.object_id != "" ? 0 : 1
}

data http localpublicip {
# Get public IP address of the machine running this terraform template
  url                          = "http://ipinfo.io/ip"
# url                          = "https://ipapi.co/ip" 
}

data http localpublicprefix {
# Get public IP prefix of the machine running this terraform template
  url                          = "https://stat.ripe.net/data/network-info/data.json?resource=${chomp(data.http.localpublicip.body)}"
}

# Random password generator
resource "random_string" "password" {
  length                       = 12
  upper                        = true
  lower                        = true
  number                       = true
  special                      = true
# override_special             = "!@#$%&*()-_=+[]{}<>:?" # default
# Avoid characters that may cause shell scripts to break
  override_special             = "!@#%*)(-_=+][]}{:?" 
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
  workspace_location           = var.workspace_location != null && var.workspace_location != "" ? var.workspace_location : var.location
  # https://docs.microsoft.com/en-us/azure/automation/how-to/region-mappings
  automation_location          = var.automation_location != null && var.automation_location != "" ? var.automation_location : replace(local.workspace_location,"/eastus$/","eastus2")
  password                     = ".Az9${random_string.password.result}"
# password                     = ".Az9${random_string.password.override_special}" # Test
  suffix                       = var.resource_suffix != "" ? lower(var.resource_suffix) : random_string.suffix.result
  deployment_name              = var.deployment_name != "" ? lower(var.deployment_name) : (length(terraform.workspace) <= 4 ? terraform.workspace : substr(lower(replace(terraform.workspace,"/a|e|i|o|u|y/","")),0,4))
  vdc_resource_group           = "${lower(var.resource_prefix)}-${lower(local.deployment_name)}-${lower(local.suffix)}"
  iaas_app_resource_group      = "${lower(var.resource_prefix)}-${lower(local.deployment_name)}-iaasapp-${lower(local.suffix)}"
  paas_app_resource_group      = "${lower(var.resource_prefix)}-${lower(local.deployment_name)}-paasapp-${lower(local.suffix)}"
  paas_app_resource_group_short= substr(lower(replace(local.paas_app_resource_group,"-","")),0,20)
  ipprefixdata                 = jsondecode(chomp(data.http.localpublicprefix.body))
  admin_ip                     = [
                                  chomp(data.http.localpublicip.body) 
  ]
  admin_ip_cidr                = [
                                  "${chomp(data.http.localpublicip.body)}/30", # /32 not allowed in network_rules
                                  # HACK: Complete prefix required when run from an environment where public ip changes e.g. Azure Pipeline Hosted Agents
                                  local.ipprefixdata.data.prefix 
  ] 
  admin_ips                    = setunion(local.admin_ip,var.admin_ips)
  admin_ip_ranges              = setunion([for ip in local.admin_ips : format("%s/30", ip)],var.admin_ip_ranges) # /32 not allowed in network_rules
  admin_cidr_ranges            = [for range in local.admin_ip_ranges : cidrsubnet(range,0,0)] # Make sure ranges have correct base address
  # FIX: Required for Azure Cloud Shell (azurerm_client_config.current.object_id not populated)
  automation_object_id         = data.azurerm_client_config.current.object_id != null && data.azurerm_client_config.current.object_id != "" ? data.azurerm_client_config.current.object_id : data.external.account_info.0.result.object_id

  tags                         = merge(
    var.tags,
    map(
      "deployment-name",         local.deployment_name,
      "environment",             terraform.workspace,
      "prefix",                  var.resource_prefix,
      "shutdown",                "true",
      "suffix",                  local.suffix,
      "workspace",               terraform.workspace,
      "release-id",              var.release_id,
      "release-url",             var.release_web_url,
      "release-user",            var.release_user_email
    )
  )

  lifecycle                    = {
    ignore_changes             = ["tags"]
  }
}

# Create Azure resource group to be used for VDC resources
resource "azurerm_resource_group" "vdc_rg" {
  name                         = local.vdc_resource_group
  location                     = var.location

  tags                         = local.tags
}

resource "azurerm_role_assignment" "demo_admin" {
  scope                        = azurerm_resource_group.vdc_rg.id
  role_definition_name         = "Contributor"
  principal_id                 = var.admin_object_id

  count                        = var.admin_object_id != null ? 1 : 0
}