#!/usr/bin/env pwsh

<# 
.SYNOPSIS 
    Registers a subscription for the Managed Bastion Service preview
 
.DESCRIPTION 
    Registers a subscription for the Managed Bastion Service preview

.EXAMPLE
    ./register_managed_bastion.ps1 -subscription ffffffff-ffff-ffff-ffff-ffffffffffff

#> 

param (    
    [parameter(Mandatory=$false)][string]$subscription=$env:ARM_SUBSCRIPTION_ID
) 
if(-not($subscription)) { Throw "You must supply a value for subscription" }

if (!(Get-AzContext)) {
    Connect-AzAccount
}
Set-AzContext -Subscription $subscription

# Register for Managed Bastion Preview
Register-AzProviderFeature -FeatureName AllowBastionHost -ProviderNamespace Microsoft.Network
Register-AzResourceProvider -ProviderNamespace Microsoft.Network
Get-AzProviderFeature -ProviderNamespace Microsoft.Network
