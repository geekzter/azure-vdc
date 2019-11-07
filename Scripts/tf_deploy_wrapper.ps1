#!/usr/bin/env pwsh

<# 
.SYNOPSIS 
    Deploys Azure resources using Terraform
 
.DESCRIPTION 
    Wrapper for tf_deploy.ps1, so control over output streams can be excercised

.EXAMPLE
    ./tf_deploy_wrapper.ps1 -plan
#> 

$command = $MyInvocation.line -replace "_wrapper", ""

Invoke-Expression "& ${command}" 2>./error.log 3>./warning.log 4>./verbose.log 5>./debug.log #6>./information.log

foreach ($output in ("error","warning","verbose","debug","information")) {
    $logFile = "./${output}.log"
    if (Test-Path $logFile) {
        if ((Get-Item $logFile).length -gt 0kb) {
            Write-Host "${output}:" -ForegroundColor DarkRed
            Get-Content $logFile
        }
    }
}