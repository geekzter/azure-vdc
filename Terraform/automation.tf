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
  name                         = "${azurerm_resource_group.vdc_rg.name}-functions"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  kind                         = "FunctionApp"

  sku {
    tier                       = "Dynamic"
    size                       = "Y1"
  }
}

resource "azurerm_function_app" "vdc_function" {
  name                         = "${azurerm_resource_group.vdc_rg.name}-function"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  app_service_plan_id          = "${azurerm_app_service_plan.vdc_functions.id}"
  storage_connection_string    = "${azurerm_storage_account.automation_storage.primary_connection_string}"

  app_settings = {
    "app_resource_group"       = "${azurerm_resource_group.app_rg.name}"
    "vdc_resource_group"       = "${azurerm_resource_group.vdc_rg.name}"
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
  principal_id                 = "${azurerm_function_app.vdc_function.identity.0.principal_id}"
}

resource "azurerm_role_assignment" "vdc_access" {
# name                         = "00000000-0000-0000-0000-000000000000"
  scope                        = "${azurerm_resource_group.vdc_rg.id}"
  role_definition_id           = "${azurerm_role_definition.vm_stop_start.id}"
# role_definition_name         = "Virtual Machine Contributor"
  principal_id                 = "${azurerm_function_app.vdc_function.identity.0.principal_id}"
}