data "azurerm_client_config" "current" {}
data "azurerm_subscription" "primary" {}

resource "azurerm_storage_account" "automation_storage" {
  name                         = "${lower(replace(var.resource_group,"-",""))}automation"
  location                     = "${var.location}"
  resource_group_name          = "${var.resource_group}"
# account_kind                 = "StorageV2"
  account_tier                 = "Standard"
  #account_replication_type     = "${var.app_storage_replication_type}"
  account_replication_type     = "LRS"
}

resource "azurerm_app_service_plan" "vdc_functions" {
  name                         = "${var.resource_group}-functions-plan"
  location                     = "${var.location}"
  resource_group_name          = "${var.resource_group}"
  kind                         = "FunctionApp"

  sku {
    tier                       = "Dynamic"
    size                       = "Y1"
  }

  count                        = "${var.deploy_auto_shutdown ? 1 : 0}"
}

resource "azurerm_function_app" "vdc_functions" {
  name                         = "${var.resource_group}-functions"
  location                     = "${var.location}"
  resource_group_name          = "${var.resource_group}"
  app_service_plan_id          = "${azurerm_app_service_plan.vdc_functions.0.id}"
  storage_connection_string    = "${azurerm_storage_account.automation_storage.primary_connection_string}"
  enable_builtin_logging       = "true"

  app_settings = {
    # TODO: Make more generic e.g. using list of resource groups
    "app_resource_group"       = "${var.app_resource_group}"
    "vdc_resource_group"       = "${var.resource_group}"
    #"resource_group_ids"       = "${join(",",var.resource_group_ids)}"
    "APPINSIGHTS_INSTRUMENTATIONKEY" = "${var.diagnostics_instrumentation_key}"
  }

  identity {
    type                       = "SystemAssigned"
  }

  count                        = "${var.deploy_auto_shutdown ? 1 : 0}"

  version                      = "~2" # Required for PowerShell (Core)
}

# Grant functions access required
resource "azurerm_role_definition" "vm_stop_start" {
# role_definition_id           = "00000000-0000-0000-0000-000000000000"
  name                         = "Virtual Machine Operator (Custom ${var.resource_group})"
  scope                        = "${data.azurerm_subscription.primary.id}"

  permissions {
    actions                    = [
        "Microsoft.Compute/*/read",
        "Microsoft.Compute/virtualMachines/start/action",
        "Microsoft.Compute/virtualMachines/restart/action",
        "Microsoft.Compute/virtualMachines/deallocate/action"
        ]
    not_actions                = []
  }

  assignable_scopes            = "${var.resource_group_ids}"

  count                        = "${var.deploy_auto_shutdown ? 1 : 0}"
}

resource "azurerm_role_assignment" "resource_group_access" {
# name                         = "00000000-0000-0000-0000-000000000000"
  scope                        = "${element(var.resource_group_ids, count.index)}" 
  role_definition_id           = "${azurerm_role_definition.vm_stop_start.0.id}"
  principal_id                 = "${azurerm_function_app.vdc_functions.0.identity.0.principal_id}"

  count                        = "${var.deploy_auto_shutdown ? length(var.resource_group_ids) : 0}"
}

# Configure function resources with ARM template as Terraform doesn't (yet) support this
# https://docs.microsoft.com/en-us/azure/templates/microsoft.web/2018-11-01/sites/functions
resource "azurerm_template_deployment" "vdc_shutdown_function_arm" {
  name                         = "${var.resource_group}-shutdown-function-arm"
  resource_group_name          = "${var.resource_group}"
  deployment_mode              = "Incremental"

  template_body                = "${file("${path.module}/automation-function.json")}"

  parameters                   = {
    functionsAppServiceName    = "${azurerm_function_app.vdc_functions.0.name}"
    functionName               = "VMShutdown"
    functionFile               = "${file("../Functions/VMShutdown/run.ps1")}"
    functionSchedule           = "0 0 23 * * *" # Every night at 23:00
    requirementsFile           = "${file("../Functions/requirements.psd1")}"
    profileFile                = "${file("../Functions/profile.ps1")}"
    hostFile                   = "${file("../Functions/host.json")}"
    proxiesFile                = "${file("../Functions/proxies.json")}"
  }

  count                        = "${var.deploy_auto_shutdown ? 1 : 0}"

  depends_on                   = ["azurerm_function_app.vdc_functions"] # Explicit dependency for ARM templates
}

# TODO: Not yet available for Azure Functions
/* 
resource "azurerm_monitor_diagnostic_setting" "vdc_function_logs" {
  name                         = "Function_Logs"
  target_resource_id           = "${azurerm_function_app.vdc_functions.0.id}"
  storage_account_id           = "${var.diagnostics_storage_id}"
  log_analytics_workspace_id   = "${var.diagnostics_workspace_id}"

  log {
    category                   = "FunctionExecutionLogs"
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

  count                        = "${var.deploy_auto_shutdown ? 1 : 0}"
}  */