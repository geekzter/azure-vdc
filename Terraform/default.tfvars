# tf_deploy.ps1 loads <terraform-worksopace>.tfvars

resource_prefix                = "vdc"
resource_environment           = "dev"
location                       = "southcentralus"
workspace_location             = "southcentralus"

deploy_auto_shutdown           = true
deploy_managed_bastion         = true
deploy_vpn                     = true
use_vanity_domain_and_ssl      = false