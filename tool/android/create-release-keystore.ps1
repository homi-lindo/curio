[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$KeystorePath = '',
    [string]$KeyAlias = 'lume',
    [int]$ValidityDays = 10000,
    [string]$DistinguishedName = 'CN=Curio Personal,O=Curio,C=BR',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path

if ([string]::IsNullOrWhiteSpace($KeystorePath)) {
    $KeystorePath = Join-Path $ProjectRoot 'release-upload-key.jks'
}
$KeystorePath = [System.IO.Path]::GetFullPath($KeystorePath)
$keyPropertiesPath = Join-Path $ProjectRoot 'android\key.properties'

function Find-Keytool {
    $candidates = @()
    if ($env:JAVA_HOME) {
        $candidates += Join-Path $env:JAVA_HOME 'bin\keytool.exe'
    }
    $pathCandidate = Get-Command keytool.exe -ErrorAction SilentlyContinue
    if ($pathCandidate) {
        $candidates += $pathCandidate.Source
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    return $null
}

function ConvertTo-PlainText([securestring]$Value) {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Assert-CanCreate([string]$Path, [string]$Label) {
    if ((Test-Path -LiteralPath $Path) -and -not $Force) {
        throw "$Label already exists: $Path. Pass -Force to overwrite."
    }
}

function Get-RelativePath([string]$BasePath, [string]$TargetPath) {
    $base = [System.Uri]((Resolve-Path -LiteralPath $BasePath).Path.TrimEnd('\') + '\')
    $targetFullPath = [System.IO.Path]::GetFullPath($TargetPath)
    $target = [System.Uri]$targetFullPath
    return [System.Uri]::UnescapeDataString(
        $base.MakeRelativeUri($target).ToString().Replace('/', '\')
    )
}

$keytool = Find-Keytool
if (-not $keytool) {
    throw 'keytool.exe not found. Install a JDK or set JAVA_HOME before creating the Android upload key.'
}

Assert-CanCreate $KeystorePath 'Keystore'
Assert-CanCreate $keyPropertiesPath 'android/key.properties'

$storePasswordSecure = Read-Host -AsSecureString 'Android upload keystore password'
$keyPasswordSecure = Read-Host -AsSecureString 'Android upload key password'
$storePassword = ConvertTo-PlainText $storePasswordSecure
$keyPassword = ConvertTo-PlainText $keyPasswordSecure

try {
    if ([string]::IsNullOrWhiteSpace($storePassword) -or $storePassword.Length -lt 8) {
        throw 'Keystore password must have at least 8 characters.'
    }
    if ([string]::IsNullOrWhiteSpace($keyPassword) -or $keyPassword.Length -lt 8) {
        throw 'Key password must have at least 8 characters.'
    }

    $keystoreDirectory = Split-Path -Parent $KeystorePath
    if (-not (Test-Path -LiteralPath $keystoreDirectory)) {
        New-Item -ItemType Directory -Path $keystoreDirectory | Out-Null
    }

    if ((Test-Path -LiteralPath $KeystorePath) -and $Force) {
        Remove-Item -LiteralPath $KeystorePath -Force
    }
    if ((Test-Path -LiteralPath $keyPropertiesPath) -and $Force) {
        Remove-Item -LiteralPath $keyPropertiesPath -Force
    }

    $keytoolInput = @(
        $storePassword,
        $storePassword,
        $keyPassword,
        $keyPassword
    ) -join [Environment]::NewLine

    "$keytoolInput$([Environment]::NewLine)" | & $keytool -genkeypair `
        -v `
        -keystore $KeystorePath `
        -storetype JKS `
        -alias $KeyAlias `
        -keyalg RSA `
        -keysize 4096 `
        -validity $ValidityDays `
        -dname $DistinguishedName | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "keytool failed with exit code $LASTEXITCODE."
    }

    $relativeKeystore = Get-RelativePath (Join-Path $ProjectRoot 'android\app') $KeystorePath
    $content = @(
        "storeFile=$relativeKeystore",
        "storePassword=$storePassword",
        "keyAlias=$KeyAlias",
        "keyPassword=$keyPassword"
    ) -join "`n"
    Set-Content -LiteralPath $keyPropertiesPath -Value "$content`n" -Encoding ascii -NoNewline

    "$storePassword$([Environment]::NewLine)" | & $keytool -list -keystore $KeystorePath -alias $KeyAlias | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "keytool verification failed with exit code $LASTEXITCODE."
    }

    Write-Host "Android release signing configured:"
    Write-Host "  Keystore: $KeystorePath"
    Write-Host "  Properties: $keyPropertiesPath"
} finally {
    $storePassword = $null
    $keyPassword = $null
}
