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

    # Copy notification helper scripts alongside curio.exe
    $toolWindowsDir = $PSScriptRoot
    $registerScript = Join-Path $toolWindowsDir 'Register-CurioShortcut.ps1'
    if (Test-Path -LiteralPath $registerScript) {
        Copy-Item -LiteralPath $registerScript -Destination $packageDir
    } else {
        Write-Warning "Register-CurioShortcut.ps1 not found at: $registerScript"
    }

    # Generate Install-CurioPortable.ps1 inside the package
    $installScript = @'
#Requires -Version 5.1
<#
.SYNOPSIS
    One-time setup: registers the Curio Portable Start Menu shortcut so that
    Windows toast notifications work without an MSIX package.

    Run once after unpacking: right-click this file and choose
    "Run with PowerShell", or open PowerShell here and run:
        .\Install-CurioPortable.ps1

    To uninstall (remove the shortcut):
        .\Install-CurioPortable.ps1 -Remove
#>
[CmdletBinding(SupportsShouldProcess)]
param([switch]$Remove)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$exePath = Join-Path $scriptDir 'curio.exe'
$registerScript = Join-Path $scriptDir 'Register-CurioShortcut.ps1'

if (-not (Test-Path -LiteralPath $registerScript)) {
    Write-Error "Register-CurioShortcut.ps1 not found next to this script. Cannot continue."
    exit 1
}

if ($Remove) {
    & $registerScript -ExePath $exePath -Remove
} else {
    & $registerScript -ExePath $exePath
}
'@
    Set-Content -LiteralPath (Join-Path $packageDir 'Install-CurioPortable.ps1') -Value $installScript -Encoding UTF8

    $readme = @"
Curio portable build

Open curio.exe to run the app without installing an MSIX package.

Notes:
- This build is for interface and functional smoke testing.
- It intentionally excludes the MSIX package and does not register the app in Windows.
- Use the signed MSIX + WACK flow for final Store certification checks.

Enabling Windows toast notifications (one-time setup)
------------------------------------------------------
Windows requires a registered Start Menu shortcut with a matching AppUserModel.ID
for toast notifications to appear. The portable build does not auto-register, so
notifications are suppressed until you run the one-time setup:

  1. Open PowerShell in this folder and run:
         .\Install-CurioPortable.ps1

     Or right-click Install-CurioPortable.ps1 and choose "Run with PowerShell".

  2. You should see a confirmation that the shortcut was created.
     After this, notifications will fire normally.

To uninstall (remove the Start Menu shortcut):
    .\Install-CurioPortable.ps1 -Remove
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
