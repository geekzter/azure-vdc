# tf_deploy.ps1 loads <terraform-worksopace>.tfvars

resource_prefix                = "vdc"
resource_environment           = "dev"
location                       = "westeurope"
workspace_location             = "westeurope"

deploy_auto_shutdown           = false
deploy_managed_bastion         = false
deploy_vpn                     = false
use_vanity_domain_and_ssl      = true