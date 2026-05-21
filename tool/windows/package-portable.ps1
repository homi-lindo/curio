[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$OutputRoot = '',
    [switch]$SkipBuild,
    [switch]$NoZip
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Resolve-RequiredPath([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Label not found: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Get-PubspecVersion([string]$Path) {
    $versionLine = Get-Content -LiteralPath $Path |
        Where-Object { $_ -match '^version:\s*(.+)$' } |
        Select-Object -First 1
    if (-not $versionLine) {
        return 'dev'
    }
    return ($versionLine -replace '^version:\s*', '').Trim()
}

function ConvertTo-SafeName([string]$Value) {
    return ($Value -replace '[^a-zA-Z0-9._-]', '-')
}

Push-Location $ProjectRoot
try {
    $flutter = Join-Path (Resolve-Path (Join-Path $ProjectRoot '..\..\.tools\flutter\bin')).Path 'flutter.bat'
    if (-not (Test-Path -LiteralPath $flutter)) {
        $flutter = 'flutter'
    }

    if (-not $SkipBuild) {
        & $flutter build windows --release --no-pub
        if ($LASTEXITCODE -ne 0) {
            throw "flutter build windows failed with exit code $LASTEXITCODE"
        }
    }

    $releaseDir = Resolve-RequiredPath (
        Join-Path $ProjectRoot 'build\windows\x64\runner\Release'
    ) 'Windows release directory'
    Resolve-RequiredPath (Join-Path $releaseDir 'curio.exe') 'curio.exe' | Out-Null

    if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
        $OutputRoot = Join-Path $ProjectRoot 'build\portable'
    }
    New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
    $outputRootPath = (Resolve-Path -LiteralPath $OutputRoot).Path

    $version = Get-PubspecVersion (Resolve-RequiredPath (Join-Path $ProjectRoot 'pubspec.yaml') 'pubspec.yaml')
    $safeVersion = ConvertTo-SafeName $version
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $packageName = "curio-windows-portable-$safeVersion-$stamp"
    $packageDir = Join-Path $outputRootPath $packageName
    New-Item -ItemType Directory -Path $packageDir | Out-Null

    Get-ChildItem -LiteralPath $releaseDir -Force |
        Where-Object { $_.Extension -ne '.msix' } |
        ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $packageDir -Recurse
        }

    $readme = @"
Curió portable build

Open curio.exe to test the app without installing an MSIX package.

Notes:
- This build is for interface and functional smoke testing.
- It intentionally excludes the MSIX package and does not register the app in Windows.
- Windows desktop notifications can behave differently without MSIX registration.
- Use the signed MSIX + WACK flow for final Store certification checks.
"@
    Set-Content -LiteralPath (Join-Path $packageDir 'README-portable.txt') -Value $readme -Encoding UTF8

    $zipPath = $null
    $zipSha256 = $null
    if (-not $NoZip) {
        $zipPath = Join-Path $outputRootPath "$packageName.zip"
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($packageDir, $zipPath)
        $zipSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath).Hash.ToLowerInvariant()
    }

    $manifest = [ordered]@{
        builtAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        version = $version
        packageDir = $packageDir
        zipPath = $zipPath
        zipSha256 = $zipSha256
        sourceReleaseDir = $releaseDir
        excludes = @('*.msix')
    }
    $manifestPath = Join-Path $outputRootPath 'curio-windows-portable.latest.json'
    $manifest | ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath $manifestPath -Encoding UTF8

    Write-Host "Portable package: $packageDir"
    if ($zipPath) {
        Write-Host "Portable zip: $zipPath"
        Write-Host "SHA256: $zipSha256"
    }
    Write-Host "Manifest: $manifestPath"
} finally {
    Pop-Location
}
