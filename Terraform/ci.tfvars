# tf_deploy.ps1 loads <terraform-worksopace>.tfvars

resource_environment           = "ci"
resource_prefix                = "vdc"
location                       = "southcentralus"
workspace_location             = "southcentralus"

deploy_auto_shutdown           = true
deploy_network_watcher         = false
deploy_managed_bastion         = true
deploy_vpn                     = true
use_vanity_domain_and_ssl      = true