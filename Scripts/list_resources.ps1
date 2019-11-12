#!/usr/bin/env pwsh

param (    
    [parameter(Mandatory=$false,HelpMessage="The environment tag to filter use")][string] $Environment,
    [parameter(Mandatory=$false,HelpMessage="The workspace tag to filter use")][string] $Workspace,
    [parameter(Mandatory=$false)][switch]$Resources=$false,
    [parameter(Mandatory=$false)][switch]$Summary=$false,
    [parameter(Mandatory=$false)][switch]$Workspaces=$false,
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "Terraform")
) 

# Provide at least one argument
if (!($Resources -or $Summary -or $Workspaces)) {
    Write-Host "Please indicate what to do by using a command-line switch"
    Get-Help $MyInvocation.MyCommand.Definition
    exit
}

if ($Summary -or $Workspaces) {
    # Access Terraform (Azure) backend to get leases for each workspace
    $tfConfig = $(Get-Content $tfdirectory/.terraform/terraform.tfstate | ConvertFrom-Json)
    $backendStorageAccountName = $tfConfig.backend.config.storage_account_name
    $backendStorageContainerName = $tfConfig.backend.config.container_name
    $backendStateKey = $tfConfig.backend.config.key
    $backendStorageKey = $env:ARM_ACCESS_KEY
    $backendstorageContext = New-AzStorageContext -StorageAccountName $backendStorageAccountName -StorageAccountKey $backendStorageKey
    $tfStateBlobs = Get-AzStorageBlob -Context $backendstorageContext -Container $backendStorageContainerName 
    $leaseTable = @{}
    $tfStateBlobs | ForEach-Object {
        $storageWorkspaceName = $($_.Name -Replace "${backendStateKey}env:","" -Replace $backendStateKey,"default")
        $leaseTable.Add($storageWorkspaceName,$_.ICloudBlob.Properties.LeaseStatus)
        Add-Member -InputObject $_ -NotePropertyName "Workspace"   -NotePropertyValue $storageWorkspaceName
        Add-Member -InputObject $_ -NotePropertyName "LeaseStatus" -NotePropertyValue $_.ICloudBlob.Properties.LeaseStatus
    }
    if ($Workspaces) {
        $tfStateBlobs | Sort-Object -Property Workspace | Format-Table Workspace, LeaseStatus
    }
}

if ($Summary) {
    $resourceQuery = "Resources | where tags['application']=='Automated VDC' | summarize ResourceCount=count() by Environment=tostring(tags['environment']), Workspace=tostring(tags['workspace']) | order by Workspace asc"
    Write-Host "`nQuery: `"$resourceQuery`""
    $graphResult = Search-AzGraph -Query $resourceQuery

    # Join tables
    $graphResult | ForEach-Object {
        Add-Member -InputObject $_ -NotePropertyName "Lease" -NotePropertyValue $leaseTable[$_.Workspace]
    }
    $graphResult | Format-Table
} 

if ($Resources) {
    $resourceQuery = "Resources | where tags['application']=='Automated VDC'"
    if ($Workspace) {
        $resourceQuery += " and tags['workspace']=='$Workspace'"         
    }
    if ($Environment) {
        $resourceQuery += " and tags['environment']=='$Environment'"         
    }
    $resourceQuery += " | project Name=name,ResourceGroup=resourceGroup | order by ResourceGroup asc, Name asc"

    Write-Host "`nQuery: `"$resourceQuery`""
    $result = Search-AzGraph -Query $resourceQuery -Subscription $subscription
    $result | Format-Table -Property Name, ResourceGroup 
    Write-Host "$($result.Count) item(s) found"
}