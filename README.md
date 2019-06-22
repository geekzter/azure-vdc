# Automated VDC
This project contains a sample Virtual Network deployment, typically used as part of a Virtual Datacenter (VDC)
It does not contain all components of a complete VDC (DNS, AD DC's, File Transfer)

[![Build Status](https://dev.azure.com/ericvan/VDC/_apis/build/status/vdc-terraform-validate-ci?branchName=master)](https://dev.azure.com/ericvan/VDC/_build/latest?definitionId=43&branchName=master)

![alt text](diagram.png "Architecture")

## Components & Features
This projects contains the following components
- A Virtual Network with subnet segregation (dmz, app, data, mgmt)
- Azure Firewall used as Internet Access Gateway (IAG, e.g. outbound fqdn whitelisting)
- Application Gateway as Web Application Firewall (WAF, inbound HTTP)
- Application VM's with IIS enabled, as Azure Pipeline agent deployed
- A Bastion server that is used as jump server to connect to other VM's. Note this should not be needed in practice as all operation should use Infrastructure as Code (cattle vs. pets) approach
- Additional Managed Bastion (service in preview) as `azurerm_template_deployment` resource (Terraform manages dependencies). You can access the Managed Bastion using this [Portal link](https://aka.ms/BastionHost). The Bastion VM will be removed once the Managed Bastion reaches General Availability.
- Several PaaS services connected as Service Endpoints into the AzureFirewall subnet
- A Point to Site (P2S VPN), that can be leveraged for transitive access to PaaS services using HTTPS Service Endpoints
- Infrastructure provisioning through Terraform, PowerShell and (optionally) Azure Pipeline
- AppServers auto-joined to Azure Pipelines Deployment Group, application deployment from Azure Pipeline

## Pre-Requisites
These project uses Terraform, PowerShell Core with Az module, ASP.NET, and Azure Pipelines. You will need an Azure subscription for created resources and Terraform Backend. Use the links below and/or a package manager of your choice (e.g. brew, chocolatey, scoop) to install required components

## Getting Started
1.	Clone repository (e.g. using Visual Studio Code, GitHub Desktop)
2.  Set up storage account for Terraform Azure Backend, and configure environment variables `ARM_SUBSCRIPTION_ID`, `ARM_TENANT_ID`, `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET` accordingly. 
3.	Initialize Terraform backend `terraform init` or `tf_deploy.ps1 -init`
4.  Create Azure Pipelines [Deployment Group](https://docs.microsoft.com/en-us/azure/devops/pipelines/release/deployment-groups/?view=azure-devops), to be used for ASP.NET application
5.  Customize `variables.tf` or create a `.auto.tfvars` (see `config.auto.tfvars.sample`) file that contains your customized confuguration
6.  Run `terraform plan` or `tf_deploy.ps1 -plan` to simmulate what happens if terraform would provision resources. 
7.  Run `terraform apply` or `tf_deploy.ps1 -apply` to create resources. 
8.  Create build pipeline to build ASP.NET app `SampleIisWebApp`, see `azure-pipelines.yml`
9.  Create release pipeline to deploy built ASP.NET `SampleIisWebApp` app to VDC app servers
10.	Run `print_hosts_file_entries.ps1` to get the input for hosts file on the P2S client that is needed for tunneled Service Endpoint access

## Sources
- [Azure Pipelines](https://azure.microsoft.com/en-us/services/devops/pipelines/)
- [PowerShell Core](https://github.com/PowerShell/PowerShell)
- [PowerShell Azure Module](https://github.com/Azure/azure-powershell)
- [Terraform Azure Backend](https://www.terraform.io/docs/providers/azurerm/index.html)
- [Terraform Azure Provider](https://www.terraform.io/docs/backends/types/azurerm.html)
- [Terraform Download](https://www.terraform.io/downloads.html)
- [Terraform Learning](https://learn.hashicorp.com/terraform/)
- [Visual Studio Code](https://github.com/Microsoft/vscode)
- [Visual Studio](https://visualstudio.microsoft.com/free-developer-offers/)

## Limitations & Known Issue's
- Release Pipelines not yet available in YAML, therefore not included

## Disclaimer
This project is provided as-is, and is not intended as blueprint on howa VDC should be deployed, or Azure components and Terraform should be used. It is merely an example on how you can use the technology. The project creates a number of Azure resources, you are responsible for monitoring cost.