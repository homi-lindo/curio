[CmdletBinding()]
param(
    [string]$ProjectRoot = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path

function Resolve-Keytool {
    $candidate = Join-Path $env:ProgramFiles 'Microsoft\jdk-21.0.10.7-hotspot\bin\keytool.exe'
    if (Test-Path -LiteralPath $candidate) {
        return (Resolve-Path -LiteralPath $candidate).Path
    }

    $command = Get-Command keytool -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    throw 'keytool não encontrado. Instale JDK ou adicione keytool ao PATH.'
}

function Read-Properties([string]$Path) {
    $props = @{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return $props
    }

    Get-Content -LiteralPath $Path | ForEach-Object {
        if ($_ -match '^\s*([^#=]+)\s*=\s*(.*)\s*$') {
            $props[$matches[1].Trim()] = $matches[2].Trim()
        }
    }
    return $props
}

function Resolve-MaybeRelativePath([string]$BasePath, [string]$Path) {
    if ([IO.Path]::IsPathRooted($Path)) {
        return $Path
    }
    $resolved = Join-Path $BasePath $Path
    if (Test-Path -LiteralPath $resolved) {
        return $resolved
    }

    $fallback = Join-Path $ProjectRoot ([IO.Path]::GetFileName($Path))
    if (Test-Path -LiteralPath $fallback) {
        return $fallback
    }

    return $resolved
}

function Get-CertificateInfo(
    [string]$Keytool,
    [string]$Keystore,
    [string]$Alias,
    [string]$StorePass,
    [string]$Label
) {
    if (-not (Test-Path -LiteralPath $Keystore)) {
        return [ordered]@{
            label = $Label
            available = $false
            reason = "keystore não encontrado: $Keystore"
        }
    }

    $listing = & $Keytool -list -v -keystore $Keystore -alias $Alias -storepass $StorePass 2>$null
    if ($LASTEXITCODE -ne 0) {
        return [ordered]@{
            label = $Label
            available = $false
            reason = 'não foi possível ler o certificado'
        }
    }

    $sha1 = ($listing |
        Select-String -Pattern '^\s*SHA1:\s*(.+)$' |
        Select-Object -First 1).Matches.Groups[1].Value.Trim()
    $sha256 = ($listing |
        Select-String -Pattern '^\s*SHA256:\s*(.+)$' |
        Select-Object -First 1).Matches.Groups[1].Value.Trim()

    $tmp = New-TemporaryFile
    Remove-Item -LiteralPath $tmp -Force
    try {
        & $Keytool -exportcert -keystore $Keystore -alias $Alias -storepass $StorePass -file $tmp 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw 'keytool -exportcert falhou'
        }
        $bytes = [IO.File]::ReadAllBytes($tmp)
        $microsoftSignatureHash = [Convert]::ToBase64String(
            [Security.Cryptography.SHA1]::HashData($bytes)
        )
    } finally {
        if (Test-Path -LiteralPath $tmp) {
            Remove-Item -LiteralPath $tmp -Force
        }
    }

    return [ordered]@{
        label = $Label
        available = $true
        alias = $Alias
        sha1 = $sha1
        sha256 = $sha256
        microsoftSignatureHash = $microsoftSignatureHash
    }
}

$keytool = Resolve-Keytool
$androidDir = Join-Path $ProjectRoot 'android'
$keyPropertiesPath = Join-Path $androidDir 'key.properties'
$keyProperties = Read-Properties $keyPropertiesPath

$certificates = @()

$debugKeystore = Join-Path $env:USERPROFILE '.android\debug.keystore'
$certificates += Get-CertificateInfo `
    -Keytool $keytool `
    -Keystore $debugKeystore `
    -Alias 'androiddebugkey' `
    -StorePass 'android' `
    -Label 'debug'

if ($keyProperties.ContainsKey('storeFile') -and
    $keyProperties.ContainsKey('storePassword') -and
    $keyProperties.ContainsKey('keyAlias')) {
    $releaseKeystore = Resolve-MaybeRelativePath $androidDir $keyProperties['storeFile']
    $certificates += Get-CertificateInfo `
        -Keytool $keytool `
        -Keystore $releaseKeystore `
        -Alias $keyProperties['keyAlias'] `
        -StorePass $keyProperties['storePassword'] `
        -Label 'release-upload'
} else {
    $certificates += [ordered]@{
        label = 'release-upload'
        available = $false
        reason = 'android/key.properties sem storeFile/storePassword/keyAlias completos'
    }
}

[ordered]@{
    appName = 'Curió'
    androidPackageName = 'app.lume.personal'
    windowsAppUserModelId = 'App.Lume.Personal'
    googleAndroidPackageName = 'app.lume.personal'
    certificates = $certificates
    playStoreNote = 'Para builds distribuídas pela Play Store, use também o SHA-1 do App signing certificate no Play Console.'
} | ConvertTo-Json -Depth 6
