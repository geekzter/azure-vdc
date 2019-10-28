output "arm_resource_ids" {
  value       = [
    for b in azurerm_template_deployment.managed_bastion : "${b.outputs["resourceGroupId"]}/providers/Microsoft.Network/bastionHosts/${local.managed_bastion_name}"
  ]
}