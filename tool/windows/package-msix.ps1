[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$PackageName = 'lume.msix',
    [string]$CertificateThumbprint = $env:LUME_MSIX_CERTIFICATE_THUMBPRINT,
    [string]$CertificatePath = $env:LUME_MSIX_CERTIFICATE_PATH,
    [string]$CertificatePassword = $env:LUME_MSIX_CERTIFICATE_PASSWORD
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

function Find-WindowsKitTool([string]$ToolName) {
    $kitRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    if (Test-Path -LiteralPath $kitRoot) {
        $candidate = Get-ChildItem -LiteralPath $kitRoot -Directory |
            Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName "x64\$ToolName" } |
            Where-Object { Test-Path -LiteralPath $_ } |
            Select-Object -First 1
        if ($candidate) {
            return $candidate
        }
    }

    return $null
}

function Assert-ChildPath([string]$Parent, [string]$Child) {
    $parentPath = (Resolve-Path -LiteralPath $Parent).Path
    $childPath = if (Test-Path -LiteralPath $Child) {
        (Resolve-Path -LiteralPath $Child).Path
    } else {
        [System.IO.Path]::GetFullPath($Child)
    }

    if (-not $childPath.StartsWith($parentPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to operate outside $parentPath`: $childPath"
    }
}

function Expand-GzipFile([string]$Source, [string]$Destination) {
    $inputStream = [System.IO.File]::OpenRead($Source)
    try {
        $gzipStream = [System.IO.Compression.GZipStream]::new(
            $inputStream,
            [System.IO.Compression.CompressionMode]::Decompress
        )
        try {
            $outputStream = [System.IO.File]::Create($Destination)
            try {
                $gzipStream.CopyTo($outputStream)
            } finally {
                $outputStream.Dispose()
            }
        } finally {
            $gzipStream.Dispose()
        }
    } finally {
        $inputStream.Dispose()
    }
}

Push-Location $ProjectRoot
try {
    $dart = Join-Path (Resolve-Path (Join-Path $ProjectRoot '..\..\.tools\flutter\bin')).Path 'dart.bat'
    if (-not (Test-Path -LiteralPath $dart)) {
        $dart = 'dart'
    }

    $packageConfigPath = Resolve-RequiredPath (Join-Path $ProjectRoot '.dart_tool\package_config.json') '.dart_tool/package_config.json'
    $packageConfig = Get-Content -LiteralPath $packageConfigPath -Raw |
        ConvertFrom-Json
    $msixPackage = $packageConfig.packages | Where-Object { $_.name -eq 'msix' } | Select-Object -First 1
    if (-not $msixPackage) {
        throw 'msix package not found in .dart_tool/package_config.json'
    }

    $msixRoot = ([System.Uri]$msixPackage.rootUri).LocalPath.TrimEnd('\', '/')
    $makeAppx = Find-WindowsKitTool 'makeappx.exe'
    $signTool = Find-WindowsKitTool 'signtool.exe'

    if (-not $makeAppx) {
        $makeAppx = Join-Path $msixRoot 'lib\assets\MSIX-Toolkit\Redist.x64\MakeAppx.exe'
    }
    if (-not $signTool) {
        $signTool = Join-Path $msixRoot 'lib\assets\MSIX-Toolkit\Redist.x64\signtool.exe'
    }

    $makeAppx = Resolve-RequiredPath $makeAppx 'makeappx.exe'
    $signTool = Resolve-RequiredPath $signTool 'signtool.exe'
    if ([string]::IsNullOrWhiteSpace($CertificateThumbprint) -and [string]::IsNullOrWhiteSpace($CertificatePath)) {
        $CertificatePath = Join-Path $msixRoot 'lib\assets\test_certificate.pfx'
    }

    $signArgs = @(
        'sign',
        '/fd',
        'SHA256',
        '/td',
        'SHA256',
        '/tr',
        'http://timestamp.digicert.com'
    )

    if (-not [string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
        $signArgs += @('/sha1', $CertificateThumbprint)
    } else {
        $certificate = Resolve-RequiredPath $CertificatePath 'MSIX signing certificate'
        if ([string]::IsNullOrWhiteSpace($CertificatePassword)) {
            throw 'MSIX certificate password not configured. Set LUME_MSIX_CERTIFICATE_PASSWORD or pass -CertificatePassword.'
        }
        $signArgs += @('/f', $certificate, '/p', $CertificatePassword)
    }

    & $dart run msix:create
    if ($LASTEXITCODE -ne 0) {
        throw "msix:create failed with exit code $LASTEXITCODE"
    }

    $packagePath = Join-Path $ProjectRoot "build\windows\x64\runner\Release\$PackageName"
    $packagePath = Resolve-RequiredPath $packagePath 'MSIX package'

    $buildRoot = Resolve-RequiredPath (Join-Path $ProjectRoot 'build\windows') 'Windows build directory'
    $unpackPath = Join-Path $buildRoot 'msix-package-work'
    Assert-ChildPath $buildRoot $unpackPath
    if (Test-Path -LiteralPath $unpackPath) {
        Remove-Item -LiteralPath $unpackPath -Recurse -Force
    }

    & $makeAppx unpack /p $packagePath /d $unpackPath /o | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "makeappx unpack failed with exit code $LASTEXITCODE"
    }

    @(
        'AppxSignature.p7x',
        'AppxBlockMap.xml',
        'AppxMetadata\CodeIntegrity.cat'
    ) | ForEach-Object {
        $candidate = Join-Path $unpackPath $_
        if (Test-Path -LiteralPath $candidate) {
            Remove-Item -LiteralPath $candidate -Force
        }
    }

    Add-Type -AssemblyName System.Drawing
    $badgeSizes = [ordered]@{
        'scale-100' = 24
        'scale-125' = 30
        'scale-150' = 36
        'scale-200' = 48
        'scale-400' = 96
    }

    $imageDirectory = Join-Path $unpackPath 'Images'
    foreach ($entry in $badgeSizes.GetEnumerator()) {
        $target = Join-Path $imageDirectory "BadgeLogo.$($entry.Key).png"
        $bitmap = New-Object System.Drawing.Bitmap $entry.Value, $entry.Value, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $bitmap.Save($target, [System.Drawing.Imaging.ImageFormat]::Png)
        } finally {
            $bitmap.Dispose()
        }
    }

    $noticesZ = Join-Path $unpackPath 'data\flutter_assets\NOTICES.Z'
    $notices = Join-Path $unpackPath 'data\flutter_assets\NOTICES'
    if (Test-Path -LiteralPath $noticesZ) {
        Expand-GzipFile -Source $noticesZ -Destination $notices
        Remove-Item -LiteralPath $noticesZ -Force
    }

    Remove-Item -LiteralPath $packagePath -Force
    & $makeAppx pack /d $unpackPath /p $packagePath /o | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "makeappx pack failed with exit code $LASTEXITCODE"
    }

    $signArgs += $packagePath
    & $signTool @signArgs | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "signtool sign failed with exit code $LASTEXITCODE"
    }

    & $signTool verify /pa $packagePath | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "signtool verify failed with exit code $LASTEXITCODE"
    }

    Write-Host "MSIX ready: $packagePath"
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
} finally {
    Pop-Location
}
