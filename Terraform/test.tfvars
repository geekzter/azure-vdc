# tf_deploy.ps1 loads <terraform-worksopace>.tfvars

resource_prefix                = "vdc"
resource_environment           = "test"
location                       = "eastus"
workspace_location             = "westeurope"

#deploy_app_service_network_integration = true
deploy_auto_shutdown           = false
deploy_network_watcher         = true
deploy_managed_bastion         = true
deploy_private_dns_for_endpoint= true
deploy_vpn                     = true
paas_app_storage_import        = false
use_vanity_domain_and_ssl      = true