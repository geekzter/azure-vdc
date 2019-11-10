#!/usr/bin/env pwsh

param (    
    [parameter(Mandatory=$false,HelpMessage="The environment tag to filter use")][string] $Environment,
    [parameter(Mandatory=$false,HelpMessage="The workspace tag to filter use")][string] $Workspace,
    [parameter(Mandatory=$false)][switch]$CountsOnly=$false,
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "Terraform"),
    [parameter(Mandatory=$false)][string]$subscription=$env:ARM_SUBSCRIPTION_ID,
    [parameter(Mandatory=$false)][string]$tenantid=$env:ARM_TENANT_ID,
    [parameter(Mandatory=$false)][string]$clientid=$env:ARM_CLIENT_ID,
    [parameter(Mandatory=$false)][string]$clientsecret=$env:ARM_CLIENT_SECRET
) 
if(-not($subscription)) { Throw "You must supply a value for subscription" }

# Log on to Azure if not already logged on
if (!(Get-AzTenant -TenantId $tenantid -ErrorAction SilentlyContinue)) {
    if(-not($tenantid)) { Throw "You must supply a value for tenantid" }
    if(-not($clientid)) { Throw "You must supply a value for clientid" }
    if(-not($clientsecret)) { Throw "You must supply a value for clientsecret" }
    # Use Terraform ARM Backend config to authenticate Azure CLI
    $secureClientSecret = ConvertTo-SecureString $clientsecret -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential ($clientid, $secureClientSecret)
    Connect-AzAccount -Tenant $tenantid -Subscription $subscription -ServicePrincipal -Credential $credential
}
Set-AzContext -Subscription $subscription

if ($CountsOnly) {
    $resourceQuery = "Resources | where tags['application']=='Automated VDC' | summarize resourceCount=count() by tostring(tags['environment']), tostring(tags['workspace']) | order by tags_workspace asc"
    Write-Host "`nQuery: $resourceQuery"
    Search-AzGraph -Query $resourceQuery | Format-Table
} else {
    $resourceQuery = "Resources | where tags['application']=='Automated VDC'"
    if ($Workspace) {
        $resourceQuery += " and tags['workspace']=='$Workspace'"         
    }
    if ($Environment) {
        $resourceQuery += " and tags['environment']=='$Environment'"         
    }
    $resourceQuery += " | project name, resourceGroup | order by name, resourceGroup asc"

    Write-Host "`nQuery: $resourceQuery"
    $result = Search-AzGraph -Query $resourceQuery -Subscription $subscription
    $result | Format-Table -Property name, resourceGroup 
    Write-Host "$($result.Count) item(s) found"
}