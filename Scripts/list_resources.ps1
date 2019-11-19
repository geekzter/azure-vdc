#!/usr/bin/env pwsh

param (    
    [parameter(Mandatory=$false,HelpMessage="The environment tag to filter use")][string] $Environment,
    [parameter(Mandatory=$false,HelpMessage="The workspace tag to filter use")][string] $Workspace,
    [parameter(Mandatory=$false)][switch]$All=$false,
    [parameter(Mandatory=$false)][switch]$Resources=$false,
    [parameter(Mandatory=$false)][switch]$Summary=$false,
    [parameter(Mandatory=$false)][switch]$Workspaces=$false,
    [parameter(Mandatory=$false)][string]$subscription=$env:ARM_SUBSCRIPTION_ID,
    [parameter(Mandatory=$false)][string]$tenantid=$env:ARM_TENANT_ID,
    [parameter(Mandatory=$false)][string]$clientid=$env:ARM_CLIENT_ID,
    [parameter(Mandatory=$false)][string]$clientsecret=$env:ARM_CLIENT_SECRET,
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "Terraform")
) 
$Script:ErrorActionPreference = "Stop"

# Provide at least one argument
if (!($All -or $Resources -or $Summary -or $Workspaces)) {
    Write-Host "Please indicate what to do by using a command-line switch"
    Get-Help $MyInvocation.MyCommand.Definition
    exit
}

if ($All -or $Summary -or $Workspaces) {
    # Access Terraform (Azure) backend to get leases for each workspace
    Write-Host "Reading Terraform settings from ${tfdirectory}/.terraform/terraform.tfstate..."
    $tfConfig = $(Get-Content $tfdirectory/.terraform/terraform.tfstate | ConvertFrom-Json)
    if ($tfConfig.backend.type -ne "azurerm") {
        throw "This script only works with azurerm provider"
    }
    $backendStorageAccountName = $tfConfig.backend.config.storage_account_name
    $backendStorageContainerName = $tfConfig.backend.config.container_name
    $backendStateKey = $tfConfig.backend.config.key
    $backendStorageKey = $env:ARM_ACCESS_KEY
    $backendstorageContext = New-AzStorageContext -StorageAccountName $backendStorageAccountName -StorageAccountKey $backendStorageKey
    Write-Host "Retrieving blobs from https://${backendStorageAccountName}.blob.core.windows.net/${backendStorageContainerName}..."
    $tfStateBlobs = Get-AzStorageBlob -Context $backendstorageContext -Container $backendStorageContainerName 
    $leaseTable = @{}
    $tfStateBlobs | ForEach-Object {
        $storageWorkspaceName = $($_.Name -Replace "${backendStateKey}env:","" -Replace $backendStateKey,"default")
        $leaseTable.Add($storageWorkspaceName,$_.ICloudBlob.Properties.LeaseStatus)
        Add-Member -InputObject $_ -NotePropertyName "Workspace"   -NotePropertyValue $storageWorkspaceName
        Add-Member -InputObject $_ -NotePropertyName "LeaseStatus" -NotePropertyValue $_.ICloudBlob.Properties.LeaseStatus
    }
    if ($All -or $Workspaces) {
        $tfStateBlobs | Sort-Object -Property Workspace | Format-Table Workspace, LeaseStatus
    }
}

if ($All -or $Summary -or $Resources) {
    # Login required
    if (!(Get-AzTenant -TenantId $tenantid -ErrorAction SilentlyContinue)) {
        Write-Host "Reconnecting to Azure with SPN..."
        if(-not($clientid)) { Throw "You must supply a value for clientid" }
        if(-not($clientsecret)) { Throw "You must supply a value for clientsecret" }
        # Use Terraform ARM Backend config to authenticate to Azure
        $secureClientSecret = ConvertTo-SecureString $clientsecret -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ($clientid, $secureClientSecret)
        $null = Connect-AzAccount -Tenant $tenantid -Subscription $subscription -ServicePrincipal -Credential $credential
    }
    $null = Set-AzContext -Subscription $subscription -Tenant $tenantid
}

if ($All -or $Summary) {
    $resourceQuery = "Resources | where tags['application']=='Automated VDC' | summarize ResourceCount=count() by Environment=tostring(tags['environment']), Workspace=tostring(tags['workspace']), Suffix=tostring(tags['suffix']) | order by Workspace asc"
    Write-Host "Executing graph query:`n$resourceQuery"
    $graphResult = Search-AzGraph -Query $resourceQuery

    # Join tables
    $graphResult | ForEach-Object {
        Add-Member -InputObject $_ -NotePropertyName "Lease" -NotePropertyValue $leaseTable[$_.Workspace]
    }
    $graphResult | Format-Table
} 

if ($All -or $Resources) {
    $resourceQuery = "Resources | where tags['application']=='Automated VDC'"
    if ($Workspace) {
        $resourceQuery += " and tags['workspace']=='$Workspace'"         
    }
    if ($Environment) {
        $resourceQuery += " and tags['environment']=='$Environment'"         
    }
    $resourceQuery += " | project Name=name,ResourceGroup=resourceGroup | order by ResourceGroup asc, Name asc"

    Write-Host "Executing graph query:`n$resourceQuery"
    $result = Search-AzGraph -Query $resourceQuery -Subscription $subscription
    $result | Format-Table -Property Name, ResourceGroup 
    Write-Host "$($result.Count) item(s) found"
}