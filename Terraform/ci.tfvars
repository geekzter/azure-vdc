# tf_deploy.ps1 loads <terraform-worksopace>.tfvars

resource_environment           = "ci"
resource_prefix                = "vdc"
location                       = "westeurope"
workspace_location             = "westeurope"

deploy_auto_shutdown           = false
deploy_network_watcher         = false
deploy_non_essential_vm_extensions = false
deploy_managed_bastion         = false
deploy_vpn                     = false
enable_app_service_aad_auth    = true
paas_app_storage_import        = false
use_pipeline_environment       = false
use_vanity_domain_and_ssl      = true