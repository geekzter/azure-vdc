#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    Sets Terraform defaults
 
.DESCRIPTION 
    Some features that require PowerShell can run from PowerShell, override defaults from variables.tf
    This uses environment variables as they have lowest order of precedence:
    https://www.terraform.io/docs/configuration/variables.html#variable-definition-precedence
#> 
#Requires -Version 7


# This enables grant_database_access.ps1
$env:TF_VAR_grant_database_access  ??= "true"

# This enables punch_hole.ps1 to make sure sufficient access exists to run 'terraform apply' (from a different outbound public IP)
$env:TF_VAR_restrict_public_access ??= "true"
