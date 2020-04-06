# Automated VDC
This project contains a sample starter Virtual Datacenter (VDC), which follows a Hub & Spoke network topology

[![Build status](https://dev.azure.com/ericvan/VDC/_apis/build/status/vdc-terraform-plan-ci?branchName=master)](https://dev.azure.com/ericvan/VDC/_build/latest?definitionId=45&branchName=master)
![alt text](diagram.png "Architecture")

## TL;DR: Quickstart
To get started you just need [Git](https://git-scm.com/), [Terraform](https://www.terraform.io/downloads.html) and [Azure CLI](http://aka.ms/azure-cli). Of course you'll need an [Azure subscription](https://portal.azure.com/#blade/Microsoft_Azure_Billing/SubscriptionsBlade) to deploy to.  
`git clone https://github.com/geekzter/azure-vdc.git`  
`cd Terraform`  
Login with Azure CLI:  
`az login`  
This also authenticates the Terraform [azurerm](https://www.terraform.io/docs/providers/azurerm/guides/azure_cli.html) provider. Optionally, you can select the subscription to target:  
`az account set --subscription="00000000-0000-0000-0000-000000000000"`  
You can provision resources by first initializing Terraform:   
`terraform init`  
And then running:  
`terraform apply`

## Components & Features
This projects contains the following components
- A hub network with subnets for shared components (dmz, mgmt, etc)
- Azure Firewall used as Internet Access Gateway (egress, outbound FQDN whitelisting)
- Application Gateway as Web Application Firewall (WAF, HTTP ingress)
- A Management server that is used as jump server to connect to other VM's. 
- A Managed Bastion as well
- A Point to Site (P2S VPN), with transitive access to PaaS services
- Infrastructure provisioning through Terraform, PowerShell and Azure Pipelines
- An IIS VM application deployed in a spoke network, with subnet segregation (app, data)
  - AppServers auto-joined to Azure Pipelines Deployment Group, application deployment from Azure Pipeline
- An App Service web application integrated into another spoke network (experimental)
  - Several PaaS services connected as Service Endpoints into the AzureFirewall subnet, or through PrivateLink
  - AAD auth between application tiers using MSI
  - Application deployed from Azure DevOps Pipeline

## Pre-Requisites (all features)
This project uses Terraform, PowerShell Core, Azure CLI, ASP.NET Framework (IIS app), ASP.NET Core (App Service app), and Azure Pipelines. You will need an Azure subscription for created resources and Terraform Backend. Use the links below and/or a package manager of your choice (e.g. apt, brew, chocolatey, scoop) to install required components.

## Getting Started (all features)
The quickstart uses defauls settings that disables some features. To use all featues (e.g. VPN, SSL domains, CI/CD), more is involved:
1.	Clone repository:  
`git clone https://github.com/geekzter/azure-vdc.git`  
2.  Change to the Terraform directrory  
`cd Terraform`
3.  Set up storage account for [Terraform Azure Backend](https://www.terraform.io/docs/backends/types/azurerm.html), configure `backend.tf` (copy `backend.tf.sample`) with the details of the storage account created. Make sure the user used for Azure CLI is in the `Storage Blob Data Contributor` or `Storage Blob Data Owner`role (It is not enough to have Owner/Contributor rights, as this is Data Plane access). Alternatively, you can set `ARM_ACCESS_KEY` or `ARM_SAS_TOKEN` environment variables e.g.  
`$env:ARM_ACCESS_KEY=$(az storage account keys list -n STORAGE_ACCOUNT --query "[0].value" -o tsv)`
4.	Initialize Terraform backend by running  
`terraform init`  
or  
`./tf_deploy.ps1 -init -workspace default`
5.	To deploy the VPN, set `deploy_vpn = true` in `variables.tf` or your `.auto.tfvars` file (see `config.auto.tfvars.sample`).  
Run  
`./create_certs.ps1`  
(Windows only at this point) to create the certificates required.
6.  To use SSL for the demo app, set `use_vanity_domain_and_ssl = true` in `variables.tf` or your `.auto.tfvars` file. You will need to configure SSL certificates using the `vanity_` variables
6.  Create Azure Pipelines [Deployment Group](https://docs.microsoft.com/en-us/azure/devops/pipelines/release/deployment-groups/?view=azure-devops), to be used for IIS application
7.  Customize `variables.tf` or create a `.auto.tfvars` file that contains your customized configuration
8.  Run  
`terraform plan`  
or  
`./tf_deploy.ps1 -plan -workspace default`  
to simmulate what happens if terraform would provision resources. 
9.  Run  
`terraform apply`  
or  
`./tf_deploy.ps1 -apply -workspace default`  
to provision resources
10.  Create build pipeline to build IIS application, see `Pipelines/iis-asp.net-ci.yml`
11.  Create build pipeline to build APp Service application, see `azure-pipelines.yml` located here: [dotnetcore-sqldb-tutorial](https://github.com/geekzter/dotnetcore-sqldb-tutorial/blob/master/azure-pipelines.yml)
12.  Create Terraform CI pipeline using either `vdc-terraform-apply-simple-ci.yml` or `vdc-terraform-apply-ci.yml`


## Sources
- [Azure CLI](http://aka.ms/azure-cli)
- [Azure Pipelines](https://azure.microsoft.com/en-us/services/devops/pipelines/)
- [PowerShell Core](https://github.com/PowerShell/PowerShell)
- [Terraform Azure Backend](https://www.terraform.io/docs/backends/types/azurerm.html)
- [Terraform Azure Provider](https://www.terraform.io/docs/providers/azurerm/index.html)
- [Terraform Download](https://www.terraform.io/downloads.html)
- [Terraform Learning](https://learn.hashicorp.com/terraform/)
- [Visual Studio Code](https://github.com/Microsoft/vscode)

## Limitations & Known Issue's
- Release Pipelines not yet available in YAML as the Azure DevOps Environments used in multi-staged YAML pipelines do not support automatic provisioning of agents yet. See [issue on GitHub](https://github.com/MicrosoftDocs/vsts-docs/issues/7698)

## Integration
- Terraform output is exported as ad-hoc Azure Pipeline variables by `tf_deploy.ps1`, so they can be used un subsequent tasks in an Azure Pipeline Job

## Disclaimer
This project is provided as-is, and is not intended as a blueprint on how a VDC should be deployed, or Azure components and Terraform should be used. It is merely an example on how you can use the technology. The project creates a number of Azure resources, you are responsible for monitoring and managing cost.