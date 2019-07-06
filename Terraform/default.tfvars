# tf_deploy.ps1 loads <terraform-worksopace>.tfvars

resource_prefix                = "vdc"
resource_environment           = "dev"
location                       = "westeurope"
workspace_location             = "westeurope"

deploy_managed_bastion         = false