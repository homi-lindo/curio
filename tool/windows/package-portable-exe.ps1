[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$PortableZip = '',
    [string]$OutputRoot = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path

function Resolve-RequiredPath([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Label not found: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function ConvertTo-SafeName([string]$Value) {
    return ($Value -replace '[^a-zA-Z0-9._-]', '-')
}

if ([string]::IsNullOrWhiteSpace($PortableZip)) {
    $manifestPath = Resolve-RequiredPath (
        Join-Path $ProjectRoot 'build\portable\curio-windows-portable.latest.json'
    ) 'Portable manifest'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $PortableZip = $manifest.zipPath
}
$PortableZip = Resolve-RequiredPath $PortableZip 'Portable zip'

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectRoot 'build\portable-exe'
}
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$outputRootPath = (Resolve-Path -LiteralPath $OutputRoot).Path

$dotnet = Resolve-RequiredPath (Join-Path $env:ProgramFiles 'dotnet\dotnet.exe') 'dotnet.exe'
$zipItem = Get-Item -LiteralPath $PortableZip
$zipBaseName = [IO.Path]::GetFileNameWithoutExtension($zipItem.Name)
$exeBaseName = $zipBaseName -replace 'windows-portable', 'windows-portable-exe'
if ($exeBaseName -eq $zipBaseName) {
    $exeBaseName = "$zipBaseName-exe"
}
$exePath = Join-Path $outputRootPath "$exeBaseName.exe"
$portableId = ConvertTo-SafeName $zipBaseName
$zipSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $PortableZip).Hash.ToLowerInvariant()

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$staging = Join-Path $env:TEMP "curio-portable-exe-$stamp"
$publishDir = Join-Path $staging 'publish'
New-Item -ItemType Directory -Force -Path $staging | Out-Null

try {
    Copy-Item -LiteralPath $PortableZip -Destination (Join-Path $staging 'payload.zip')

    $project = @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net9.0</TargetFramework>
    <RuntimeIdentifier>win-x64</RuntimeIdentifier>
    <SelfContained>true</SelfContained>
    <PublishSingleFile>true</PublishSingleFile>
    <EnableCompressionInSingleFile>true</EnableCompressionInSingleFile>
    <IncludeNativeLibrariesForSelfExtract>true</IncludeNativeLibrariesForSelfExtract>
    <DebugType>none</DebugType>
    <AssemblyName>CurioPortableLauncher</AssemblyName>
  </PropertyGroup>
  <ItemGroup>
    <EmbeddedResource Include="payload.zip" LogicalName="payload.zip" />
  </ItemGroup>
</Project>
"@
    Set-Content -LiteralPath (Join-Path $staging 'CurioPortableLauncher.csproj') -Value $project -Encoding UTF8

    $program = @"
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;

const string AppId = @"$portableId";
const string PayloadSha256 = @"$zipSha256";

var target = Path.Combine(
    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
    "Curio",
    "portable",
    AppId);
var appExe = Path.Combine(target, "curio.exe");
var marker = Path.Combine(target, ".payload.sha256");

try
{
    Directory.CreateDirectory(target);
    var needsExtract = !File.Exists(appExe) ||
        !File.Exists(marker) ||
        !string.Equals(File.ReadAllText(marker).Trim(), PayloadSha256, StringComparison.OrdinalIgnoreCase);

    if (needsExtract)
    {
        using var payload = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip");
        if (payload is null)
        {
            throw new InvalidOperationException("Embedded Curio payload was not found.");
        }

        ZipFile.ExtractToDirectory(payload, target, overwriteFiles: true);
        File.WriteAllText(marker, PayloadSha256);
    }

    if (!File.Exists(appExe))
    {
        throw new FileNotFoundException("Curio executable was not extracted.", appExe);
    }

    Process.Start(new ProcessStartInfo(appExe)
    {
        WorkingDirectory = target,
        UseShellExecute = true,
    });
}
catch (Exception error)
{
    Directory.CreateDirectory(target);
    File.WriteAllText(Path.Combine(target, "launcher-error.log"), error.ToString());
    Environment.ExitCode = 1;
}
"@
    Set-Content -LiteralPath (Join-Path $staging 'Program.cs') -Value $program -Encoding UTF8

    & $dotnet publish (Join-Path $staging 'CurioPortableLauncher.csproj') `
        -c Release `
        -o $publishDir `
        --nologo `
        /p:ContinuousIntegrationBuild=true
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish failed with exit code $LASTEXITCODE"
    }

    $publishedExe = Resolve-RequiredPath (Join-Path $publishDir 'CurioPortableLauncher.exe') 'Published launcher'
    if (Test-Path -LiteralPath $exePath) {
        Remove-Item -LiteralPath $exePath -Force
    }
    Copy-Item -LiteralPath $publishedExe -Destination $exePath

    $exeSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $exePath).Hash.ToLowerInvariant()
    $manifest = [ordered]@{
        builtAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        sourceZip = $PortableZip
        sourceZipSha256 = $zipSha256
        exePath = $exePath
        exeSha256 = $exeSha256
        extractPath = "%LOCALAPPDATA%\Curio\portable\$portableId"
        launcher = 'Self-contained .NET single-file launcher'
    }
    $manifestPath = Join-Path $outputRootPath 'curio-windows-portable-exe.latest.json'
    $manifest | ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath $manifestPath -Encoding UTF8

    Write-Host "Portable exe: $exePath"
    Write-Host "SHA256: $exeSha256"
    Write-Host "Manifest: $manifestPath"
} finally {
    if (Test-Path -LiteralPath $staging) {
        Remove-Item -LiteralPath $staging -Recurse -Force
    }
}
