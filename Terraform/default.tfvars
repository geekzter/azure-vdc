# tf_deploy.ps1 loads <terraform-worksopace>.tfvars

resource_prefix                = "vdc"
resource_environment           = "dev"
location                       = "eastus"
workspace_location             = "westeurope"

deploy_app_service_network_integration = true
deploy_auto_shutdown           = false
deploy_network_watcher         = false
deploy_non_essential_vm_extensions = false
deploy_managed_bastion         = false
deploy_private_dns_for_endpoint= true
deploy_vpn                     = false
paas_app_storage_import        = false
use_pipeline_environment       = false
use_vanity_domain_and_ssl      = true

app_db_vm_number               = 2
app_web_vm_number              = 2