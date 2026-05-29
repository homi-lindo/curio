# Generates a self-signed TLS certificate for the Curió self-hosted sync server
# and prints the pairing details (fingerprint + ready-to-paste pairing code).
#
# Devices trust this certificate by pinning its fingerprint, so no public CA or
# reverse proxy is needed. Run once; reuse the generated cert.pem/key.pem.
#
# Usage:
#   pwsh -File tool\sync\gen-cert.ps1 -PublicHost 192.168.0.10 -Token <token> [-Port 8787] [-OutDir .lume-sync]

param(
  [Parameter(Mandatory = $true)][string]$PublicHost,
  [string]$Token = '',
  [int]$Port = 8787,
  [string]$OutDir = '.lume-sync'
)

$ErrorActionPreference = 'Stop'

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$certPath = Join-Path $OutDir 'cert.pem'
$keyPath = Join-Path $OutDir 'key.pem'

function Format-Pem([string]$header, [byte[]]$bytes) {
  $b64 = [Convert]::ToBase64String($bytes)
  $lines = [System.Collections.Generic.List[string]]::new()
  for ($i = 0; $i -lt $b64.Length; $i += 64) {
    $lines.Add($b64.Substring($i, [Math]::Min(64, $b64.Length - $i)))
  }
  return "-----BEGIN $header-----`n" + ($lines -join "`n") + "`n-----END $header-----`n"
}

$rsa = [System.Security.Cryptography.RSA]::Create(2048)
$req = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
  "CN=$PublicHost", $rsa,
  [System.Security.Cryptography.HashAlgorithmName]::SHA256,
  [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
$now = [DateTimeOffset]::UtcNow
$cert = $req.CreateSelfSigned($now.AddDays(-1), $now.AddYears(10))

Set-Content -Path $certPath -NoNewline -Value (Format-Pem 'CERTIFICATE' $cert.RawData)
Set-Content -Path $keyPath -NoNewline -Value (Format-Pem 'PRIVATE KEY' $rsa.ExportPkcs8PrivateKey())

$sha = [System.Security.Cryptography.SHA256]::Create()
$fingerprint = ([BitConverter]::ToString($sha.ComputeHash($cert.RawData)) -replace '-', '').ToLower()

Write-Host "Certificate: $certPath"
Write-Host "Private key: $keyPath"
Write-Host "Certificate SHA-256: $fingerprint"

if ($Token -ne '') {
  $json = "{`"u`":`"https://${PublicHost}:${Port}`",`"t`":`"$Token`",`"f`":`"$fingerprint`"}"
  $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($json))
  $b64url = $b64.Replace('+', '-').Replace('/', '_')
  Write-Host "Pairing code (cole no app): curio-pair.v1.$b64url"
}

Write-Host ''
Write-Host "Inicie o servidor com:"
Write-Host "  --tls-cert $certPath --tls-key $keyPath --public-host $PublicHost"
