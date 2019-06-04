#!/usr/bin/env pwsh

param  
( 
    [parameter(Mandatory=$false,HelpMessage="The Terraform workspace to use")][string] $Workspace = "default",
    [parameter(Mandatory=$false)][string]$tfdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "Terraform"),
    [parameter(Mandatory=$false)][int]$trace=0
) 
if(-not($Workspace))    { Throw "You must supply a value for Workspace" }

try {
    Push-Location $tfdirectory

    terraform workspace select $Workspace.ToLower()
    terraform workspace list

    Write-Host "# Add below content to hosts file on P2S VPN Client and uncomment to access these PaaS services HTTPS Service Endpoints through a VPN tunnel"
    $iagIPAddress = $(terraform output iag_private_ip)
    terraform output -json app_storage_fqdns | ConvertFrom-Json | Select-Object -ExpandProperty "value" | ForEach-Object {
        Write-Host "# $iagIPAddress " $_
    }
    Write-Host "# $iagIPAddress " $(terraform output app_eventhub_namespace_fqdn)
    
}
finally 
{
    Pop-Location
}