# tf_deploy.ps1 loads <terraform-worksopace>.tfvars

resource_prefix                = "vdc"
resource_environment           = "test"
location                       = "westeurope"
workspace_location             = "westeurope"

deploy_auto_shutdown           = true
deploy_connection_monitors     = false
deploy_managed_bastion         = true
deploy_vpn                     = true
use_vanity_domain_and_ssl      = true