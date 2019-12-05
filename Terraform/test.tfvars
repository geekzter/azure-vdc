# tf_deploy.ps1 loads <terraform-worksopace>.tfvars

resource_prefix                = "vdc"
resource_environment           = "test"
location                       = "eastus"
workspace_location             = "westeurope"

deploy_auto_shutdown           = true
deploy_network_watcher         = true
deploy_managed_bastion         = true
deploy_vpn                     = true
paas_app_storage_import        = true
use_vanity_domain_and_ssl      = true