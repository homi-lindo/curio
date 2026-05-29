[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$Flutter = '',
    [string]$GoogleAndroidClientId = $env:CURIO_GOOGLE_ANDROID_CLIENT_ID,
    [string]$MicrosoftClientId = $env:CURIO_MICROSOFT_CLIENT_ID,
    [string]$MicrosoftTenant = $env:CURIO_MICROSOFT_TENANT
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

function Add-DartDefine([System.Collections.Generic.List[string]]$Args, [string]$Name, [string]$Value) {
    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        $Args.Add("--dart-define=$Name=$Value")
    }
}

Push-Location $ProjectRoot
try {
    Write-Host "Running Flutter release App Bundle build..."
    $buildArgs = [System.Collections.Generic.List[string]]::new()
    @('build', 'appbundle', '--release', '--no-pub') | ForEach-Object { $buildArgs.Add($_) }
    Add-DartDefine -Args $buildArgs -Name 'CURIO_GOOGLE_ANDROID_CLIENT_ID' -Value $GoogleAndroidClientId
    Add-DartDefine -Args $buildArgs -Name 'CURIO_MICROSOFT_CLIENT_ID' -Value $MicrosoftClientId
    Add-DartDefine -Args $buildArgs -Name 'CURIO_MICROSOFT_TENANT' -Value $MicrosoftTenant

    # Flutter writes non-fatal warnings (e.g. Kotlin Gradle plugin notices) to
    # stderr; with ErrorActionPreference=Stop those would abort the script
    # before we can inspect the real exit code. Relax it around the native call
    # and fail only on a non-zero exit code.
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Flutter @buildArgs 2>&1 | Tee-Object -FilePath $logPath
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
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
        command = "flutter $($buildArgs -join ' ')"
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
