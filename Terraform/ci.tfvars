# tf_deploy.ps1 loads <terraform-worksopace>.tfvars

resource_environment           = "ci"
resource_prefix                = "vdc"
location                       = "southcentralus"
workspace_location             = "southcentralus"

deploy_managed_bastion         = false