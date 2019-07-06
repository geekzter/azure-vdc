param  
( 
   [parameter(Mandatory=$false)][string]$certdirectory=$(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "Certificates")
) 

if ($PSVersionTable.PSEdition -and ($PSVersionTable.PSEdition -eq "Core"))
{
    Write-Host "Not running on Windows PowerShell, Powershell Core can't create certificates :-(" -ForegroundColor Red
    Exit
}

###############################
# Create Certificates
###############################
$rootCertThumbprint = Get-ChildItem -Path "Cert:\CurrentUser\My" | Where-Object {$_.Subject -eq "CN=P2SRootCert"} | Select-Object -ExpandProperty Thumbprint

if ($rootCertThumbprint)
{
    # Root certificate already exists
    $rootCert = Get-ChildItem -Path "Cert:\CurrentUser\My\$rootCertThumbprint"
}
else 
{
    # Root certificate does not exist yet
    $rootCert = New-SelfSignedCertificate -Type Custom -KeySpec Signature `
    -Subject "CN=P2SRootCert" -KeyExportPolicy Exportable `
    -HashAlgorithm sha256 -KeyLength 2048 `
    -CertStoreLocation "Cert:\CurrentUser\My" -KeyUsageProperty Sign -KeyUsage CertSign
}

$childCertThumbprint = Get-ChildItem -Path "Cert:\CurrentUser\My" | Where-Object {$_.Subject -eq "CN=P2SChildCert"} | Select-Object -ExpandProperty Thumbprint

if ($childCertThumbprint)
{
    # Child certificate already exists
    $childCert = Get-ChildItem -Path "Cert:\CurrentUser\My\$childCertThumbprint"
}
else 
{
    # Child certificate does not exist yet
    $clientCert = New-SelfSignedCertificate -Type Custom -DnsName P2SChildCert -KeySpec Signature `
    -Subject "CN=P2SChildCert" -KeyExportPolicy Exportable `
    -HashAlgorithm sha256 -KeyLength 2048 `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -Signer $rootCert -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.2")
}

Get-ChildItem -Path "Cert:\CurrentUser\My" | Where-Object {$_.Subject -like "CN=P2S*"}

###############################
# Export Certificates
###############################
$certPassword = Read-Host -AsSecureString -Prompt "Provide password to protect exported certificates"

# Create directory if it does not exist yet
New-Item -ItemType Directory -Force -Path $certDirectory >$null

Export-Certificate -Cert $rootCert -FilePath $(Join-Path $certdirectory P2SRootCert.cer)
Export-PfxCertificate -Cert $childCert -FilePath $(Join-Path $certdirectory P2SChildCert.pfx) -ChainOption BuildChain -Password $certPassword
