# Automated VDC
This project contains a sample starter Virtual Datacenter (VDC), which follows a Hub & Spoke network topology

[![Build status](https://dev.azure.com/ericvan/VDC/_apis/build/status/vdc-terraform-apply-simple-ci?branchName=master)](https://dev.azure.com/ericvan/VDC/_build/latest?definitionId=72&branchName=master)
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

## Full version
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
  - AAD auth to App Service
  - AAD auth between application tiers using MSI
  - Application deployed from Azure DevOps Pipeline

### Pre-Requisites
This project uses Terraform, PowerShell Core, Azure CLI, ASP.NET Framework (IIS app), ASP.NET Core (App Service app), and Azure Pipelines. You will need an Azure subscription for created resources and Terraform Backend. Use the links below and/or a package manager of your choice (e.g. apt, brew, chocolatey, scoop) to install required components.

### Getting Started
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
5.  Customize `variables.tf` or create a `.auto.tfvars` file that contains your customized configuration (see [Features](###Features) below)
6.  Run  
`terraform plan`  
or  
`./tf_deploy.ps1 -plan -workspace default`  
to simmulate what happens if terraform would provision resources. 
7.  Run  
`terraform apply`  
or  
`./tf_deploy.ps1 -apply -workspace default`  
to provision resources
8.  Create build pipeline to build IIS application, see `Pipelines/iis-asp.net-ci.yml`
9.  Create build pipeline to build APp Service application, see `azure-pipelines.yml` located here: [dotnetcore-sqldb-tutorial](https://github.com/geekzter/dotnetcore-sqldb-tutorial/blob/master/azure-pipelines.yml)
10.  Create Terraform CI pipeline using either `vdc-terraform-apply-simple-ci.yml` or `vdc-terraform-apply-ci.yml`

### Features ###
The Automated VDC has a number of features that are turned off by default. This can be because the feature has pre-requisites (e.g. certificates, or you need to own a domain). Another reason is the use of Azure preview features, or features that just simply take a long time to provision. Features are toggled by a corresponding variable in `variables.tf`.
|Feature|Toggle|Dependencies and Pre-requisites|
|---|---|---|
|Auto&nbsp;Shutdown, Azure Function to deallocate VM's, runs daily|`deploy_auto_shutdown`|This deployment depends on nested ARM template deployment using `azurerm_template_deployment`|
|Non&#x2011;essential&nbsp;VM&nbsp;Extensions. Controls whether these extensions are provisioned: `TeamServicesAgent` (for VM's that are not a deployment target for an Azure Pipeline), `BGInfo`, `DependencyAgentWindows`, `NetworkWatcherAgentWindows`|`deploy_non_essential_vm_extensions`|None|
|Azure&nbsp;Bastion. Provisions the Azure Bastion service in each Virtual Network|`deploy_managed_bastion`|None|
|Network&nbsp;Watcher|`deploy_network_watcher`|`deploy_non_essential_vm_extensions` also needs to be set|
|VPN, provisions Point-to-Site (P2S) VPN|`deploy_vpn`|You need to create certificates used by P2S VPN with `create_certs.ps1` on Windows. These certificates need to exist in the `Certificates` sub-directory. Variable `vpn_root_cert_file` needs to be set (see example in `config.auto.tfvars.sample`).|
|AAD&nbsp;Authentication. Configure App Service to authenticate using Azure Active Directory|`enable_app_service_aad_auth`|SSL and a vanity domain needs to have been set up. You also need to create an Azure AD App registration and configure the `paas_aad_auth_client_id_map` map for at least the `default` workspace (see example in `config.auto.tfvars.sample`). (Note: Terraform could provision this pre-requiste as well, but I'm assuming you don't have suffiient AAD permissions as this requires a Service Principal to create Service Principals in automation)|
|Pipeline&nbsp;agent&nbsp;type. By default a Deployment Group will be used. Setting this to true will instead use an Environment|`use_pipeline_environment`|Multi-stage YAML Pipelines|
|SSL&nbsp;&&nbsp;Vanity&nbsp;domain. Use HTTPS and Vanity domains (e.g. yourdomain.com)|`use_vanity_domain_and_ssl`|You need to own a domain, and delegated the management of the domain to Azure DNS. The domain name and resource group holding the Azure DNS for it need to be configured using `vanity_domainname` and `shared_resources_group` respectively. You need a wildcard SSL certificate and store it in the `Certificates` sub-directory. `vanity_certificate_*` need to be set accordingly (see example in `config.auto.tfvars.sample`).

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