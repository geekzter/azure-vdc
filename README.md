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

## VDC
This projects contains the following components
- A hub network with subnets for shared components (dmz, mgmt, etc)
- Azure Firewall used as Internet Access Gateway (egress, outbound FQDN whitelisting)
- Application Gateway as Web Application Firewall (WAF, HTTP ingress)
- A Management VM that is used as jump server to connect to other VM's. 
- A Managed Bastion as well
- A Point to Site (P2S VPN), with transitive access to PaaS services
- Infrastructure provisioning through Terraform, PowerShell and Azure Pipelines
- An IIS VM application deployed in a spoke network, with subnet segregation (app, data)
  - AppServers auto-joined to Azure Pipelines Deployment Group, application deployment from Azure Pipeline
- An App Service web application integrated into another spoke network (experimental)
  - Several PaaS services connected as Service Endpoints into the AzureFirewall subnet, or through PrivateLink
  - Application deployed from Azure DevOps Pipeline
- Azure Active Directory Authentication
  - User AAD auth to App Service
  - MSI auth between application tiers
  - AAD auth to VM's (RDP)
  - AAD auth on Point-to-Site VPN

### Pre-Requisites
This project uses Terraform, PowerShell 7, Azure CLI, ASP.NET Framework (IIS app), ASP.NET Core (App Service app), and Azure Pipelines. You will need an Azure subscription for created resources and Terraform Backend. Use the links below and/or a package manager of your choice (e.g. apt, brew, chocolatey, scoop) to install required components.

### Getting Started
The quickstart uses defauls settings that disables some features. To use all featues (e.g. VPN, SSL domains, CI/CD), more is involved:
1.	Clone repository:  
`git clone https://github.com/geekzter/azure-vdc.git`  
2.  Change to the `terraform` directrory  
`cd terraform`
3.  Set up storage account for [Terraform Azure Backend](https://www.terraform.io/docs/backends/types/azurerm.html), configure `backend.tf` (copy `backend.tf.sample`) with the details of the storage account created. Make sure the user used for Azure CLI is in the `Storage Blob Data Contributor` or `Storage Blob Data Owner`role (It is not enough to have Owner/Contributor rights, as this is Data Plane access). Alternatively, you can set `ARM_ACCESS_KEY` or `ARM_SAS_TOKEN` environment variables e.g.  
`$env:ARM_ACCESS_KEY=$(az storage account keys list -n STORAGE_ACCOUNT --query "[0].value" -o tsv)`   
or   
`$env:ARM_SAS_TOKEN=$(az storage container generate-sas -n STORAGE_CONTAINER --permissions acdlrw --expiry 202Y-MM-DD --account-name STORAGE_ACCOUNT -o tsv)`   
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
The Automated VDC has a number of features that are turned off by default. This can be because the feature has pre-requisites (e.g. certificates, or you need to own a domain). Another reason is the use of Azure preview features, or features that just simply take a long time to provision. Features are toggled by a corresponding variable in [`variables.tf`](./Terraform/variables.tf).
|Feature|Toggle|Dependencies and Pre-requisites|
|---|---|---|
|Azure&nbsp;Bastion. Provisions the [Azure Bastion](https://azure.microsoft.com/en-us/services/azure-bastion/) service in each Virtual Network|`deploy_managed_bastion`|None|
|Non&#x2011;essential&nbsp;VM&nbsp;Extensions. Controls whether these extensions are provisioned: `TeamServicesAgent` (for VM's that are not a deployment target for an Azure Pipeline), `BGInfo`, `DependencyAgentWindows`, `NetworkWatcherAgentWindows`|`deploy_non_essential_vm_extensions` (implies `deploy_security_vm_extensions`)|PowerShell 7|
|[Network&nbsp;Watcher](https://azure.microsoft.com/en-us/services/network-watcher/)|`deploy_network_watcher`|`deploy_non_essential_vm_extensions` also needs to be set. This requires PowerShell 7|
|Security&nbsp;VM&nbsp;Extensions. Controls whether these extensions are provisioned: `AADLoginForWindows`, `AzureDiskEncryption`|`deploy_security_vm_extensions`|None|
|VPN, provisions [Point-to-Site (P2S) VPN](https://docs.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-howto-point-to-site-rm-ps)|`deploy_vpn`|You need to have the [Azure VPN application](https://go.microsoft.com/fwlink/?linkid=2117554) [provisioned](https://docs.microsoft.com/en-us/azure/vpn-gateway/openvpn-azure-ad-tenant) in your Azure Active Directory tenant.|
|AAD&nbsp;Authentication. [Configure](https://docs.microsoft.com/en-us/azure/app-service/configure-authentication-provider-aad) App Service to authenticate using Azure Active Directory|`enable_app_service_aad_auth`|SSL and a vanity domain needs to have been set up. You also need to create an Azure AD App registration and configure the `paas_aad_auth_client_id_map` map for at least the `default` workspace (see example in [`config.auto.tfvars.sample`](./Terraform/config.auto.tfvars.sample))). (Note: Terraform could provision this pre-requiste as well, but I'm assuming you don't have suffiient AAD permissions as this requires a Service Principal to create Service Principals in automation)|
|Grant access to SQL Database for App Service MSI and user/group defined by `admin_object_id`. This is required for database import and therefore application deployment|`grant_database_access`|PowerShell 7|
|Pipeline&nbsp;agent&nbsp;type. By default a [Deployment Group](https://docs.microsoft.com/en-us/azure/devops/pipelines/release/deployment-groups/) will be used. Setting this to `true` will instead use an [Environment](https://docs.microsoft.com/en-us/azure/devops/pipelines/process/environments)|`use_pipeline_environment`|Multi-stage YAML Pipelines|
|SSL&nbsp;&&nbsp;Vanity&nbsp;domain. Use HTTPS and Vanity domains (e.g. yourdomain.com)|`use_vanity_domain_and_ssl`|You need to own a domain, and delegate the management of the domain to [Azure DNS](https://azure.microsoft.com/en-us/services/dns/). The domain name and resource group holding the Azure DNS for it need to be configured using `vanity_domainname` and `shared_resources_group` respectively. You need a wildcard SSL certificate and configure its location by setting `vanity_certificate_*` (see example in [`config.auto.tfvars.sample`](./Terraform/config.auto.tfvars.sample)).

### Resources
- [Azure CLI](http://aka.ms/azure-cli)
- [Azure Pipelines](https://azure.microsoft.com/en-us/services/devops/pipelines/)
- [PowerShell Core](https://github.com/PowerShell/PowerShell)
- [Terraform Azure Backend](https://www.terraform.io/docs/backends/types/azurerm.html)
- [Terraform Azure Provider](https://www.terraform.io/docs/providers/azurerm/index.html)
- [Terraform Learning](https://learn.hashicorp.com/terraform/)
- [Visual Studio Code](https://github.com/Microsoft/vscode)

### Limitations & Known Issue's
- Release Pipelines not yet available in YAML as the Azure DevOps Environments used in multi-staged YAML pipelines do not support automatic provisioning of agents yet. See [issue on GitHub](https://github.com/MicrosoftDocs/vsts-docs/issues/7698)

### Integration
- Terraform output is exported as ad-hoc Azure Pipeline variables by `tf_deploy.ps1`, so they can be used in subsequent tasks in an Azure Pipeline Job

## Disclaimer
This project is provided as-is, and is not intended as a blueprint on how a VDC should be deployed, or Azure components and Terraform should be used. It is merely an example on how you can use the technology. The project creates a number of Azure resources, you are responsible for monitoring and managing cost. You can configure auto shutdown on VM's through the Azure Portal, with the [Start/stop VMs during off-hours solution](https://docs.microsoft.com/en-us/azure/automation/automation-solution-vm-management), or with functions in my [azure-governance](https://github.com/geekzter/azure-governance/tree/master/functions) repo.