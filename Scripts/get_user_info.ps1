#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    Retrieves user info from Azure Active Directory
 
.DESCRIPTION 
    Returns JSON formated user object, that can be consumer in a Terraform external datasource
#> 

$user = az account show --query "user" | ConvertFrom-Json
if ($user.type -ieq "user") {
    $objectId = $(az ad signed-in-user show --query "dobjectId" -o tsv)
}
$result = @{
    displayName = $user.name
    objectId = $objectId
    objectType = $user.type
} | ConvertTo-Json
return $result