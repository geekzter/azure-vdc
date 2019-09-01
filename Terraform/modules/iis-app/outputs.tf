
output "app_resource_group" {
  value       = "${azurerm_resource_group.app_rg.name}"
}

output "app_resource_group_id" {
  value       = "${azurerm_resource_group.app_rg.id}"
}

output "app_web_lb_address" {
  value       = "${var.vdc_vnet["app_web_lb_address"]}"
}
