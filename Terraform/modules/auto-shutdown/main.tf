locals {
  # Last element of resource id is resource name
  resource_group_name          = element(split("/",var.resource_group_id),length(split("/",var.resource_group_id))-1)
}

data "azurerm_client_config" "current" {}
data "azurerm_subscription" "primary" {}

resource "azurerm_storage_account" "automation_storage" {
  name                         = "${lower(replace(local.resource_group_name,"-",""))}automation"
  location                     = var.location
  resource_group_name          = local.resource_group_name
  account_kind                 = "StorageV2"
  account_tier                 = "Standard"
  account_replication_type     = var.app_storage_replication_type
# enable_blob_encryption       = true
  enable_https_traffic_only    = true

  provisioner "local-exec" {
    command                    = "../Scripts/enable_storage_logging.ps1 -StorageAccountName ${self.name} -ResourceGroupName ${self.resource_group_name} "
    interpreter                = ["pwsh", "-nop", "-Command"]
  }
}

resource azurerm_advanced_threat_protection automation_storage {
  target_resource_id           = azurerm_storage_account.automation_storage.id
  enabled                      = true
}

resource "azurerm_app_service_plan" "vdc_functions" {
  name                         = "${local.resource_group_name}-functions-plan"
  location                     = var.location
  resource_group_name          = local.resource_group_name
  kind                         = "FunctionApp"

  sku {
    tier                       = "Dynamic"
    size                       = "Y1"
  }

  count                        = var.deploy_auto_shutdown ? 1 : 0
}

resource "azurerm_function_app" "vdc_functions" {
  name                         = "${local.resource_group_name}-functions"
  location                     = var.location
  resource_group_name          = local.resource_group_name
  app_service_plan_id          = azurerm_app_service_plan.vdc_functions.0.id
  storage_connection_string    = azurerm_storage_account.automation_storage.primary_connection_string
  enable_builtin_logging       = "true"

  app_settings = {
    # TODO: Make more generic e.g. using list of resource groups
    "app_resource_group"       = var.app_resource_group
    "vdc_resource_group"       = local.resource_group_name
    #"resource_group_ids"       = join(",",local.resource_group_name_ids)
    "APPINSIGHTS_INSTRUMENTATIONKEY" = var.diagnostics_instrumentation_key
  }

  identity {
    type                       = "SystemAssigned"
  }

  count                        = var.deploy_auto_shutdown ? 1 : 0

  version                      = "~2" # Required for PowerShell (Core)
}

# Grant functions access required
resource "azurerm_role_definition" "vm_stop_start" {
# role_definition_id           = "00000000-0000-0000-0000-000000000000"
  name                         = "Virtual Machine Operator (Custom ${local.resource_group_name})"
  scope                        = data.azurerm_subscription.primary.id

  permissions {
    actions                    = [
        "Microsoft.Compute/*/read",
        "Microsoft.Compute/virtualMachines/start/action",
        "Microsoft.Compute/virtualMachines/restart/action",
        "Microsoft.Compute/virtualMachines/deallocate/action"
        ]
    not_actions                = []
  }

  assignable_scopes            = var.resource_group_ids

  count                        = var.deploy_auto_shutdown ? 1 : 0
}

resource "azurerm_role_assignment" "resource_group_access" {
# name                         = "00000000-0000-0000-0000-000000000000"
  scope                        = element(var.resource_group_ids, count.index)
  role_definition_id           = azurerm_role_definition.vm_stop_start.0.id
  principal_id                 = azurerm_function_app.vdc_functions.0.identity.0.principal_id

  count                        = var.deploy_auto_shutdown ? length(var.resource_group_ids) : 0
}

# Configure function resources with ARM template as Terraform doesn't (yet) support this
# https://docs.microsoft.com/en-us/azure/templates/microsoft.web/2018-11-01/sites/functions
resource "azurerm_template_deployment" "vdc_shutdown_function_arm" {
  name                         = "${local.resource_group_name}-shutdown-function-arm"
  resource_group_name          = local.resource_group_name
  deployment_mode              = "Incremental"

  template_body                = file("${path.module}/automation-function.json")

  parameters                   = {
    functionsAppServiceName    = azurerm_function_app.vdc_functions.0.name
    functionName               = "VMShutdown"
    functionFile               = file("../Functions/VMShutdown/run.ps1")
    functionSchedule           = "0 0 23 * * *" # Every night at 23:00
    requirementsFile           = file("../Functions/requirements.psd1")
    profileFile                = file("../Functions/profile.ps1")
    hostFile                   = file("../Functions/host.json")
    proxiesFile                = file("../Functions/proxies.json")
  }

  count                        = var.deploy_auto_shutdown ? 1 : 0

  depends_on                   = [azurerm_function_app.vdc_functions] # Explicit dependency for ARM templates
}

resource "azurerm_monitor_diagnostic_setting" "vdc_function_logs" {
  name                         = "Function_Logs"
  target_resource_id           = azurerm_function_app.vdc_functions.0.id
  storage_account_id           = var.diagnostics_storage_id
  log_analytics_workspace_id   = var.diagnostics_workspace_resource_id

  log {
    category                   = "FunctionAppLogs"
    enabled                    = true

    retention_policy {
      enabled                  = false
    }
  }
  
  metric {
    category                   = "AllMetrics"

    retention_policy {
      enabled                  = false
    }
  }

  count                        = var.deploy_auto_shutdown ? 1 : 0
} 