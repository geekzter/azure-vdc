# tf_deploy.ps1 loads <terraform-worksopace>.tfvars

resource_environment           = "ci"
resource_prefix                = "vdc"
location                       = "westeurope"
workspace_location             = "westeurope"

deploy_auto_shutdown           = false
deploy_network_watcher         = false
deploy_managed_bastion         = true
deploy_private_dns_for_endpoint= true
deploy_vpn                     = true
use_vanity_domain_and_ssl      = true