[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$Flutter = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path

if ([string]::IsNullOrWhiteSpace($Flutter)) {
    $Flutter = Join-Path $ProjectRoot '..\..\.tools\flutter\bin\flutter.bat'
}
$Flutter = (Resolve-Path -LiteralPath $Flutter).Path

$logsDir = Join-Path $ProjectRoot 'build\logs'
$logPath = Join-Path $logsDir 'appbundle-release.log'
$successPath = Join-Path $logsDir 'appbundle-release.success.json'
$aabPath = Join-Path $ProjectRoot 'build\app\outputs\bundle\release\app-release.aab'

New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
if (Test-Path -LiteralPath $successPath) {
    Remove-Item -LiteralPath $successPath -Force
}

Push-Location $ProjectRoot
try {
    Write-Host "Running Flutter release App Bundle build..."
    & $Flutter build appbundle --release --no-pub 2>&1 | Tee-Object -FilePath $logPath
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "flutter build appbundle failed with exit code $exitCode. See $logPath"
    }

    if (-not (Test-Path -LiteralPath $aabPath)) {
        throw "Flutter reported success, but app-release.aab was not found at $aabPath"
    }

    & jarsigner -verify -verbose -certs $aabPath *> $null
    $jarsignerExit = $LASTEXITCODE
    if ($jarsignerExit -ne 0) {
        throw "jarsigner verification failed for app-release.aab with exit code $jarsignerExit."
    }

    $artifact = Get-Item -LiteralPath $aabPath
    $hash = (Get-FileHash -LiteralPath $aabPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $marker = [ordered]@{
        builtAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        command = 'flutter build appbundle --release --no-pub'
        artifact = 'build\app\outputs\bundle\release\app-release.aab'
        sizeBytes = $artifact.Length
        sha256 = $hash
        jarsignerVerified = $true
    }

    $marker | ConvertTo-Json | Set-Content -LiteralPath $successPath -Encoding UTF8
    Write-Host "Built and verified $aabPath"
    Write-Host "SHA256: $hash"
} finally {
    Pop-Location
}
