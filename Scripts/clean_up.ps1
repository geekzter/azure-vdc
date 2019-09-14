#!/usr/bin/env pwsh

# Clean up Azure resources left over

### Arguments
param ( 
    [parameter(Mandatory=$false,HelpMessage="The Terraform workspace to use")][string]$prefix = "vdc",
    [parameter(Mandatory=$false,HelpMessage="The Terraform workspace to use")][string]$environment = "ci",
    [parameter(Mandatory=$false,HelpMessage="The Terraform workspace to use")][string]$suffix = "*",
    [parameter(Mandatory=$false)][string]$subscription=$env:ARM_SUBSCRIPTION_ID,
    [parameter(Mandatory=$false)][string]$tenantid=$env:ARM_TENANT_ID,
    [parameter(Mandatory=$false)][string]$clientid=$env:ARM_CLIENT_ID,
    [parameter(Mandatory=$false)][string]$clientsecret=$env:ARM_CLIENT_SECRET
) 

function AzLogin () {
    if (!(Get-AzTenant -TenantId $tenantid -ErrorAction SilentlyContinue)) {
        if(-not($clientid)) { Throw "You must supply a value for clientid" }
        if(-not($clientsecret)) { Throw "You must supply a value for clientsecret" }
        # Use Terraform ARM Backend config to authenticate to Azure
        $secureClientSecret = ConvertTo-SecureString $clientsecret -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ($clientid, $secureClientSecret)
        Connect-AzAccount -Tenant $tenantid -Subscription $subscription -ServicePrincipal -Credential $credential
    }
    Set-AzContext -Subscription $subscription -Tenant $tenantid
}

AzLogin

$resourceGroups = Get-AzResourceGroup | Where-Object {$_.ResourceGroupName -like "$prefix-$environment-*$suffix"}
$resourceGroupNames = $resourceGroups | Select-Object -ExpandProperty ResourceGroupName

$proceedanswer = Read-Host "If you wish to proceed removing these resource groups:`n$resourceGroupNames `nplease reply 'yes' - null or N aborts"
if ($proceedanswer -ne "yes") {
    Write-Host "`nReply is not 'yes' - Aborting " -ForegroundColor Red
    Exit
}
$resourceGroups | Remove-AzResourceGroup -AsJob -Force