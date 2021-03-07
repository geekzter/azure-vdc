# tf_deploy.ps1 loads <terraform-worksopace>.tfvars


resource_prefix                = "vdc"
deployment_name                = "test"
location                       = "uksouth"
workspace_location             = "uksouth"

deploy_managed_bastion         = true
deploy_monitoring_vm_extensions = true
deploy_network_watcher         = true
deploy_non_essential_vm_extensions = true
deploy_security_vm_extensions  = true
deploy_vpn                     = true
disable_public_database_access  = true
enable_app_service_aad_auth    = true
enable_custom_vulnerability_baseline = true
enable_private_link            = true
grant_database_access          = true
paas_app_storage_import        = true
use_pipeline_environment       = true
use_server_side_disk_encryption = true
use_vanity_domain_and_ssl      = true