# tf_deploy.ps1 loads <terraform-worksopace>.tfvars

enable_custom_vulnerability_baseline = false

resource_prefix                = "vdc"
deployment_name                = "dev"
# https://azure.microsoft.com/en-us/global-infrastructure/services/?products=sql-database,monitor,azure-bastion,private-link
# https://azure.microsoft.com/en-us/global-infrastructure/regions/
#location                       = "eastus"
location                       = "northeurope"
#location                       = "southeastasia"
#location                       = "westeurope"
#location                       = "uksouth"
# https://docs.microsoft.com/en-us/azure/automation/how-to/region-mappings
#automation_location            = "westeurope"
#workspace_location             = "westeurope"
