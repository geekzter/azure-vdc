variable "resource_group" {
  description                  = "The name of the resource group"
  default                      = "app"
}

variable "tags" {
  description = "A map of the tags to use for the resources that are deployed"
  type        = "map"

  default = {
    application                = "Automated VDC"
    provisioner                = "terraform"
  }
} 

variable "location" {
  description                  = "The location/region where the virtual network is created. Changing this forces a new resource to be created."
  default                      = "westeurope"
}

variable "diagnostics_storage_id" {
  description                  = "The id of the diagnostics storage account to use"
}
variable "workspace_id" {
  description                  = "The id of the Log Analytics workspace to use"
}

variable "virtual_network_name" {
    description                = "The name of the Virtual Network to connect the VPN to"
}


variable "vpn_root_cert_name" {
  default                      = "P2SRootCert" 
}

variable "vpn_root_cert_file" {
  description                  = "The relative path to the certificate CER file used for P2S root"
}

variable "vpn_range" {
    description                = "The client subnet range for VPN"
}
variable "vpn_subnet" {
    description                = "The subnet range for the VPN GW subnet"
}

variable "deploy_vpn" {
  description                  = "Whether to deploy the point to Site VPN"
  default                      = false
  type                         = bool
}