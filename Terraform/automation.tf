# Automation account, used for runbooks
resource "azurerm_automation_account" "automation" {
  name                         = "${azurerm_resource_group.vdc_rg.name}-automation"
  location                     = "${azurerm_resource_group.vdc_rg.location}"
  resource_group_name          = "${azurerm_resource_group.vdc_rg.name}"
  sku_name                     = "Basic"
}
