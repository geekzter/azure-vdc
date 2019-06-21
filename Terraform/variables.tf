variable "resource_prefix" {
  description                  = "The prefix to put in front of resource names created"
  default                      = "vdc"
}

variable "resource_suffix" {
  description                  = "The suffix to put at the of resource names created"
  default                      = "" # Empty string triggers a random suffix
}

variable "resource_environment" {
  description = "The logical environment (tier) resource will be deployed in"
  default     = "" # Empty string defaults to workspace name
}

variable "tags" {
  description = "A map of the tags to use for the resources that are deployed"
  type        = "map"

  default = {
    application                = "Automated VDC"
    provisioner                = "terraform"
  }
} 

variable "release_web_url" {
  description = "The url of the Release Pipeline that deployed this resource"
  default     = "" 
}
variable "release_id" {
  description = "The ID Release Pipeline that deployed this resource"
  default     = ""
}
variable "release_user_email" {
  description = "The email address of the user that triggered the pipeline that deployed this resource"
  default     = ""
}

######### Resource Group #########
variable "location" {
  description                  = "The location/region where the virtual network is created. Changing this forces a new resource to be created."
  default                      = "westeurope"
}

variable "workspace_location" {
  description                  = "The location/region where the monitoring workspaces will be created."
  default                      = "westeurope"
}

########## VNet #########
variable "vdc_vnet" {
  type                         = "map"

  default = {
    vdc_range                 = "10.64.156.0/23"
    app_subnet                 = "10.64.156.0/25"
    data_subnet                = "10.64.156.128/25"
    iag_subnet                 = "10.64.157.0/26"
    waf_subnet                 = "10.64.157.64/26"
    mgmt_subnet                = "10.64.157.128/26"
    bastion_subnet             = "10.64.157.192/27"
    vpn_subnet                 = "10.64.157.224/27"
    vpn_range                  = "10.2.0.0/24"

    app_web_lb_address         = "10.64.156.4"
    app_db_lb_address          = "10.64.156.141"
    iag_address                = "10.64.157.4"
    bastion_address            = "10.64.157.132"
  }
}

variable "vdc_oms_solutions" {
# List of solutions: https://docs.microsoft.com/en-us/rest/api/loganalytics/workspaces/listintelligencepacks
  default                      = [
  # "ADAssessment",
  # "ADReplication",
  # "AgentHealthAssessment",
  # "AlertManagement",
    "AntiMalware",
    "ApplicationInsights",
    "AzureActivity",
    "AzureAppGatewayAnalytics",
    "AzureAutomation",
    "AzureNetworking",
    "AzureNSGAnalytics",
    "AzureSQLAnalytics",
    "AzureWebAppsAnalytics",
    "Backup",
  # "CapacityPerformance",
  # "ChangeTracking",
  # "CompatibilityAssessment",
    "Containers",
  # "DnsAnalytics",
    "KeyVault",
    "KeyVaultAnalytics",
  # "LogicAppB2B",
  # "LogicAppsManagement",
    "LogManagement",
    "NetworkMonitoring",
    "ProcessInvestigator",
  # "SCOMAssessment",
    "Security",
    "SecurityCenterFree",
    "ServiceDesk",
  # "ServiceFabric",
    "ServiceMap",
    "SiteRecovery",
    "SQLAssessment",
  # "Start-Stop-VM",
    "Updates",
  # "WireData",
  # "WireData2",
    ]
}

variable "app_web_vms" {
  default                      = ["10.64.156.5", "10.64.156.6"]
}

variable "app_db_vms" {
  default                      = ["10.64.156.142", "10.64.156.143"]
}

variable "admin_ip_ranges" {
  default                      = []
}
variable "admin_ips" {
  default                      = []
}

variable "rdp_port" {
# default                      = "3389" # Default for protocol
  default                      = "28934"
}

########## Credentials #########
variable "admin_username" {
  description                  = "The VDC admin user name"
  default                      = "vdcadmin"
}

######### Example App #########


# Import TF_VAR_app_vsts_pat environment variable

variable "app_devops" {
  type                         = "map"

  default = {
    account                    = "myaccount"
    team_project               = "VDC"
    web_deployment_group       = "AppServers"
    db_deployment_group        = "DBServers"
    pat                        = ""
  }
}

variable "app_storage_account_tier" {
  description                  = "Defines the Tier of storage account to be created. Valid options are Standard and Premium."
  default                      = "Standard"
}

variable "app_storage_replication_type" {
  description                  = "Defines the Replication Type to use for this storage account. Valid options include LRS, GRS etc."
  default                      = "LRS"
}

variable "app_web_vm_size" {
  description                  = "Specifies the size of the Web virtual machines."
  default                      = "Standard_D2s_v3"
}
variable "app_web_image_publisher" {
  description                  = "name of the publisher of the Web image (az vm image list)"
  default                      = "MicrosoftWindowsServer"
}
variable "app_web_image_offer" {
  description                  = "the name of the offer (az vm image list)"
  default                      = "WindowsServer"
}
variable "app_web_image_sku" {
  description                  = "image sku to apply (az vm image list)"
  default                      = "2019-Datacenter"
}
variable "app_web_image_version" {
  description                  = "version of the Web image to apply (az vm image list)"
  default                      = "latest"
}

variable "app_db_vm_size" {
  description                  = "Specifies the size of the DB virtual machines."
  default                      = "Standard_D2s_v3"
}
variable "app_db_image_publisher" {
  description                  = "name of the publisher of the DB image (az vm image list)"
  default                      = "MicrosoftWindowsServer"
}
variable "app_db_image_offer" {
  description                  = "the name of the offer (az vm image list)"
  default                      = "WindowsServer"
}
variable "app_db_image_sku" {
  description                  = "image sku to apply (az vm image list)"
  default                      = "2019-Datacenter"
}
variable "app_db_image_version" {
  description                  = "version of the DB image to apply (az vm image list)"
  default                      = "latest"
}
variable "vanity_domainname" {
  description                  = "The domain part of the vanity url"
}
variable "vanity_certificate_name" {
  description                  = "The name of the SSL certificate used for vanity url"
}

variable "vanity_certificate_path" {
  description                  = "The relative path to the SSL certificate PFX file used for vanity url"
}

variable "vanity_certificate_password" {
  description                  = "The full path to the SSL certificate PFX file used for vanity url"
}

variable "vpn_root_cert_name" {
  default                      = "P2SRootCert" 
}

variable "vpn_root_cert_file" {
  description                  = "The relative path to the certificate CER file used for P2S root"
}
