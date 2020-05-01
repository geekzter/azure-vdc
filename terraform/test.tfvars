# tf_deploy.ps1 loads <terraform-worksopace>.tfvars

resource_prefix                = "vdc"
resource_environment           = "test"
location                       = "westeurope"
workspace_location             = "westeurope"

deploy_managed_bastion         = true
deploy_network_watcher         = false
deploy_non_essential_vm_extensions = true
deploy_security_vm_extensions  = true
deploy_vpn                     = false
enable_app_service_aad_auth    = true
grant_database_access          = true
paas_app_storage_import        = false
use_pipeline_environment       = false
use_server_side_disk_encryption = false
use_vanity_domain_and_ssl      = true
