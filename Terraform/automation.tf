# Automation account, used for runbooks
resource "azurerm_automation_account" "automation" {
  name                         = "${azurerm_resource_group.vdc_rg.name}-automation"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"

  sku {
    name = "Basic"
  }
}

resource "azurerm_storage_account" "automation_storage" {
  name                         = "${lower(replace(local.vdc_resource_group,"-",""))}automation"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
# account_kind                 = "StorageV2"
  account_tier                 = "Standard"
  account_replication_type     = "LRS"
}

resource "azurerm_app_service_plan" "vdc_functions" {
  name                         = "${azurerm_resource_group.vdc_rg.name}-functions-plan"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  kind                         = "FunctionApp"

  sku {
    tier                       = "Dynamic"
    size                       = "Y1"
  }
}

resource "azurerm_function_app" "vdc_functions" {
  name                         = "${azurerm_resource_group.vdc_rg.name}-functions"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  app_service_plan_id          = "${azurerm_app_service_plan.vdc_functions.id}"
  storage_connection_string    = "${azurerm_storage_account.automation_storage.primary_connection_string}"
  enable_builtin_logging       = "true"

  app_settings = {
    "app_resource_group"       = "${azurerm_resource_group.app_rg.name}"
    "vdc_resource_group"       = "${azurerm_resource_group.vdc_rg.name}"
    "APPINSIGHTS_INSTRUMENTATIONKEY" = "${azurerm_application_insights.vdc_insights.instrumentation_key}"
  }

  identity {
    type                       = "SystemAssigned"
  }

  version                      = "~2" # Required for PowerShell (Core)
}

# Grant functions access required
resource "azurerm_role_definition" "vm_stop_start" {
# role_definition_id           = "00000000-0000-0000-0000-000000000000"
  name                         = "Virtual Machine Operator (Custom ${azurerm_resource_group.vdc_rg.name})"
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

  assignable_scopes            = [
    "${azurerm_resource_group.app_rg.id}",
    "${azurerm_resource_group.vdc_rg.id}",
  ]
}

resource "azurerm_role_assignment" "app_access" {
# name                         = "00000000-0000-0000-0000-000000000000"
  scope                        = "${azurerm_resource_group.app_rg.id}"
  role_definition_id           = "${azurerm_role_definition.vm_stop_start.id}"
# role_definition_name         = "Virtual Machine Contributor"
  principal_id                 = "${azurerm_function_app.vdc_functions.identity.0.principal_id}"
}

resource "azurerm_role_assignment" "vdc_access" {
# name                         = "00000000-0000-0000-0000-000000000000"
  scope                        = "${azurerm_resource_group.vdc_rg.id}"
  role_definition_id           = "${azurerm_role_definition.vm_stop_start.id}"
# role_definition_name         = "Virtual Machine Contributor"
  principal_id                 = "${azurerm_function_app.vdc_functions.identity.0.principal_id}"
}

# Configure function resources with ARM template as Terraform doesn't (yet) support this
# https://docs.microsoft.com/en-us/azure/templates/microsoft.web/2018-11-01/sites/functions
resource "azurerm_template_deployment" "vdc_shutdown_function_arm" {
  name                         = "${azurerm_resource_group.vdc_rg.name}-shutdown-function-arm"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  deployment_mode              = "Incremental"

  template_body                = <<DEPLOY
{
    "$schema": "https://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "functionsAppServiceName": {
            "type": "string"
        },
        "functionName": {
            "type": "string"
        },
        "functionSchedule": {
            "type": "string"
        },
        "functionFile": {
            "type": "string"
        },
        "requirementsFile": {
            "type": "string"
        },
        "profileFile": {
            "type": "string"
        },
        "hostFile": {
            "type": "string"
        },
        "proxiesFile": {
            "type": "string"
        }
    },
    "resources": [
        {
          "name": "[concat(parameters('functionsAppServiceName'), '/', parameters('functionName'))]",
          "type": "Microsoft.Web/sites/functions",
          "apiVersion": "2018-11-01",
          "properties": {
              "config": {
                  "bindings": [
                      {
                          "name": "Timer",
                          "type": "timerTrigger",
                          "direction": "in",
                          "schedule": "[parameters('functionSchedule')]"
                      }
                  ],
                  "disabled": false
              },
              "files": {
                  "run.ps1": "[parameters('functionFile')]",
                  "../requirements.psd1": "[parameters('requirementsFile')]",
                  "../profile.ps1": "[parameters('profileFile')]",
                  "../host.json": "[parameters('hostFile')]",
                  "../proxies.json": "[parameters('proxiesFile')]"
              }
          }
        }        
    ]
}
DEPLOY

  parameters {
    "functionsAppServiceName"  = "${azurerm_function_app.vdc_functions.name}"
    "functionName"             = "VMShutdown"
    "functionFile"             = "${file("../Functions/VMShutdown/run.ps1")}"
    "functionSchedule"         = "0 0 23 * * *" # Every night at 23:00
    "requirementsFile"         = "${file("../Functions/requirements.psd1")}"
    "profileFile"              = "${file("../Functions/profile.ps1")}"
    "hostFile"                 = "${file("../Functions/host.json")}"
    "proxiesFile"              = "${file("../Functions/proxies.json")}"
  }

  depends_on                   = ["azurerm_function_app.vdc_functions"] # Explicit dependency for ARM templates
}