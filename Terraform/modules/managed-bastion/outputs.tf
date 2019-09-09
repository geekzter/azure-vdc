output "arm_resource_ids" {
  value       = [
    # Managed Bastion
    "${azurerm_template_deployment.managed_bastion.0.outputs["resourceGroupId"]}/providers/Microsoft.Network/bastionHosts/${local.managed_bastion_name}",
  ]
}