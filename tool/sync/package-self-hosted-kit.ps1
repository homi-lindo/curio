[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$OutputRoot = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectRoot 'build\self-hosted'
}
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$OutputRoot = (Resolve-Path -LiteralPath $OutputRoot).Path

$versionLine = Get-Content -LiteralPath (Join-Path $ProjectRoot 'pubspec.yaml') |
    Where-Object { $_ -match '^version:\s*(.+)$' } |
    Select-Object -First 1
$version = if ($versionLine) { ($versionLine -replace '^version:\s*', '').Trim() } else { 'dev' }
$safeVersion = $version -replace '[^a-zA-Z0-9._-]', '-'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$kitName = "curio-sync-self-hosted-$safeVersion-$stamp"
$stage = Join-Path $OutputRoot $kitName

if (Test-Path -LiteralPath $stage) {
    Remove-Item -LiteralPath $stage -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stage | Out-Null

$copyItems = @(
    'compose.yaml',
    'Dockerfile.sync',
    '.dockerignore',
    '.env.example',
    'server',
    'packages\lume_core'
)

foreach ($item in $copyItems) {
    $source = Join-Path $ProjectRoot $item
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Required kit item not found: $item"
    }
    Copy-Item -LiteralPath $source -Destination $stage -Recurse -Force
}

Copy-Item -LiteralPath (Join-Path $ProjectRoot 'docs\self-hosted-sync.md') `
    -Destination (Join-Path $stage 'README.md') -Force

$manifest = [ordered]@{
    name = 'Curio self-hosted sync kit'
    version = $version
    builtAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    entrypoint = 'compose.yaml'
}
$manifest | ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath (Join-Path $stage 'manifest.json') -Encoding UTF8

$zipPath = Join-Path $OutputRoot "$kitName.zip"
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zipPath)
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath).Hash.ToLowerInvariant()

$latest = [ordered]@{
    builtAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    version = $version
    packageDir = $stage
    zipPath = $zipPath
    zipSha256 = $hash
}
$latest | ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath (Join-Path $OutputRoot 'curio-sync-self-hosted.latest.json') -Encoding UTF8

Write-Host "Self-hosted kit: $stage"
Write-Host "Self-hosted zip: $zipPath"
Write-Host "SHA256: $hash"
