# Builds a Microsoft Store-ready MSIX (unsigned — the Store signs it, so there
# is no SmartScreen warning and no paid code-signing certificate is needed).
#
# Get these three values from Partner Center after reserving the app name
# (Product > Product identity), then pass them as parameters or environment
# variables:
#   CURIO_STORE_IDENTITY_NAME            -> Package/Identity/Name
#   CURIO_STORE_PUBLISHER                -> Package/Identity/Publisher (CN=...)
#   CURIO_STORE_PUBLISHER_DISPLAY_NAME   -> Publisher display name
#
# Usage:
#   pwsh -File tool\windows\package-msix-store.ps1 `
#     -IdentityName 1234Publisher.Curio `
#     -Publisher "CN=ABCD1234-..." `
#     -PublisherDisplayName "Your Publisher Name"
#
# Then upload the resulting .msix in Partner Center. Do NOT sign it locally.

[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$IdentityName = $env:CURIO_STORE_IDENTITY_NAME,
    [string]$Publisher = $env:CURIO_STORE_PUBLISHER,
    [string]$PublisherDisplayName = $env:CURIO_STORE_PUBLISHER_DISPLAY_NAME
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path

foreach ($pair in @(
        @{ Name = 'IdentityName'; Value = $IdentityName; Env = 'CURIO_STORE_IDENTITY_NAME' },
        @{ Name = 'Publisher'; Value = $Publisher; Env = 'CURIO_STORE_PUBLISHER' },
        @{ Name = 'PublisherDisplayName'; Value = $PublisherDisplayName; Env = 'CURIO_STORE_PUBLISHER_DISPLAY_NAME' }
    )) {
    if ([string]::IsNullOrWhiteSpace($pair.Value)) {
        throw "Missing $($pair.Name). Set -$($pair.Name) or `$env:$($pair.Env) from Partner Center > Product identity."
    }
}
if ($Publisher -notmatch '^CN=') {
    throw "Publisher must be the Partner Center value starting with 'CN=' (e.g. CN=ABCD1234-...)."
}

$dart = Join-Path (Resolve-Path (Join-Path $ProjectRoot '..\..\.tools\flutter\bin')).Path 'dart.bat'
if (-not (Test-Path -LiteralPath $dart)) {
    $dart = 'dart'
}

Push-Location $ProjectRoot
try {
    Write-Host "Building Store MSIX for identity '$IdentityName' ($Publisher)..."
    $createArgs = @(
        'run', 'msix:create',
        '--store',
        '--identity-name', $IdentityName,
        '--publisher', $Publisher,
        '--publisher-display-name', $PublisherDisplayName
    )

    # msix:create writes non-fatal notices to stderr; rely on the exit code.
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $dart @createArgs
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) {
        throw "msix:create --store failed with exit code $exitCode."
    }

    $packagePath = Join-Path $ProjectRoot 'build\windows\x64\runner\Release\lume.msix'
    if (-not (Test-Path -LiteralPath $packagePath)) {
        throw "Store MSIX not found at $packagePath."
    }
    Write-Host "Store MSIX ready (unsigned, upload to Partner Center): $packagePath"
} finally {
    Pop-Location
}
