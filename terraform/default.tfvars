# tf_deploy.ps1 loads <terraform-worksopace>.tfvars

resource_prefix                = "vdc"
deployment_name                = "dev"
# https://azure.microsoft.com/en-us/global-infrastructure/services/?products=sql-database,monitor,azure-bastion,private-link
# https://azure.microsoft.com/en-us/global-infrastructure/regions/
location                       = "eastus"
#location                       = "westeurope"
#automation_location            = "westeurope"
#workspace_location             = "westeurope"
