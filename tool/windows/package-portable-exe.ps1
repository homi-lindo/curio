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
    <TargetFramework>net9.0-windows</TargetFramework>
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
#nullable disable
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Runtime.InteropServices;

const string AppId = @"$portableId";
const string PayloadSha256 = @"$zipSha256";
const string AumId = "App.Lume.Personal";
const string ShortcutDisplayName = "Curio Portable";
const string StartupShortcutDisplayName = "Curio Portable Alarm";

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

    // Register Start Menu shortcut so toast notifications work in the portable build.
    // Runs on every launch so a newer portable launcher can repair older shortcuts.
    var startMenuPrograms = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "Microsoft", "Windows", "Start Menu", "Programs");
    var shortcutPath = Path.Combine(startMenuPrograms, ShortcutDisplayName + ".lnk");
    try
    {
        ShortcutHelper.CreateWithAumid(appExe, target, shortcutPath, AumId);

        // Keep the portable alarm process in the user's desktop session after
        // login. A Windows Service cannot reliably show toast UI or play audio
        // in the interactive session because services run in session 0.
        var startupFolder = Environment.GetFolderPath(Environment.SpecialFolder.Startup);
        var startupShortcutPath = Path.Combine(
            startupFolder,
            StartupShortcutDisplayName + ".lnk");
        ShortcutHelper.CreateWithAumid(appExe, target, startupShortcutPath, AumId);
    }
    catch (Exception shortcutError)
    {
        // Non-fatal: log but continue launching the app.
        File.AppendAllText(
            Path.Combine(target, "launcher-error.log"),
            "[shortcut] " + shortcutError + Environment.NewLine);
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

// ---------------------------------------------------------------------------
// Shortcut + AUMID helper — no external NuGet deps, .NET 9 / win-x64 only.
// ---------------------------------------------------------------------------
static class ShortcutHelper
{
    // PKEY_AppUserModel_ID: {9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}, pid 5
    private static readonly Guid PkeyAumidFmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");
    private const uint PkeyAumidPid = 5;

    public static void CreateWithAumid(string exePath, string workingDir, string shortcutPath, string aumid)
    {
        // Step 1: create .lnk via IShellLink and stamp the AUMID before
        // saving it. Stamping an already-saved .lnk through
        // SHGetPropertyStoreFromParsingName is not reliable for this property.
        var shellLinkType = Type.GetTypeFromCLSID(new Guid("00021401-0000-0000-C000-000000000046"));
        object shellLink = Activator.CreateInstance(shellLinkType);
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(shortcutPath));
            var link = (IShellLinkW)shellLink;
            link.SetPath(exePath);
            link.SetWorkingDirectory(workingDir);
            link.SetDescription("Curio Portable");

            var propertyStore = (IPropertyStore)shellLink;
            var key = new PROPERTYKEY { fmtid = PkeyAumidFmtid, pid = PkeyAumidPid };
            var pv = new PROPVARIANT();
            pv.vt = 31; // VT_LPWSTR
            pv.pwszVal = Marshal.StringToCoTaskMemUni(aumid);
            try
            {
                propertyStore.SetValue(ref key, ref pv);
                propertyStore.Commit();
            }
            finally
            {
                Marshal.FreeCoTaskMem(pv.pwszVal);
            }

            var persistFile = (IPersistFile)shellLink;
            persistFile.Save(shortcutPath, true);
        }
        finally
        {
            Marshal.FinalReleaseComObject(shellLink);
        }

        // Step 2: stamp AppUserModel.ID via IPropertyStore
        var iid = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
        int hr = NativeMethods.SHGetPropertyStoreFromParsingName(
            shortcutPath, IntPtr.Zero, 2 /* GPS_READWRITE */, ref iid, out IntPtr psPtr);
        if (hr != 0 || psPtr == IntPtr.Zero) return;

        try
        {
            var ps = (IPropertyStore)Marshal.GetObjectForIUnknown(psPtr);
            var key = new PROPERTYKEY { fmtid = PkeyAumidFmtid, pid = PkeyAumidPid };
            var pv = new PROPVARIANT();
            pv.vt = 31; // VT_LPWSTR
            pv.pwszVal = Marshal.StringToCoTaskMemUni(aumid);
            try
            {
                ps.SetValue(ref key, ref pv);
                ps.Commit();
            }
            finally
            {
                Marshal.FreeCoTaskMem(pv.pwszVal);
                Marshal.ReleaseComObject(ps);
            }
        }
        finally
        {
            Marshal.Release(psPtr);
        }
    }

    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IPropertyStore
    {
        void GetCount(out uint cProps);
        void GetAt(uint iProp, out PROPERTYKEY pkey);
        void GetValue(ref PROPERTYKEY key, out PROPVARIANT pv);
        void SetValue(ref PROPERTYKEY key, ref PROPVARIANT pv);
        void Commit();
    }

    [ComImport, Guid("000214F9-0000-0000-C000-000000000046"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellLinkW
    {
        void GetPath(
            [Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pszFile,
            int cchMaxPath,
            IntPtr pfd,
            uint fFlags);
        void GetIDList(out IntPtr ppidl);
        void SetIDList(IntPtr pidl);
        void GetDescription(
            [Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pszName,
            int cchMaxName);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string pszName);
        void GetWorkingDirectory(
            [Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pszDir,
            int cchMaxPath);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string pszDir);
        void GetArguments(
            [Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pszArgs,
            int cchMaxPath);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string pszArgs);
        void GetHotkey(out short pwHotkey);
        void SetHotkey(short wHotkey);
        void GetShowCmd(out int piShowCmd);
        void SetShowCmd(int iShowCmd);
        void GetIconLocation(
            [Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pszIconPath,
            int cchIconPath,
            out int piIcon);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string pszIconPath, int iIcon);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string pszPathRel, uint dwReserved);
        void Resolve(IntPtr hwnd, uint fFlags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string pszFile);
    }

    [ComImport, Guid("0000010B-0000-0000-C000-000000000046"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IPersistFile
    {
        void GetClassID(out Guid pClassID);
        int IsDirty();
        void Load([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, uint dwMode);
        void Save([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, [MarshalAs(UnmanagedType.Bool)] bool fRemember);
        void SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string pszFileName);
        void GetCurFile([MarshalAs(UnmanagedType.LPWStr)] out string ppszFileName);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PROPERTYKEY
    {
        public Guid fmtid;
        public uint pid;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct PROPVARIANT
    {
        [FieldOffset(0)] public ushort vt;
        [FieldOffset(8)] public IntPtr pwszVal;
    }

    private static class NativeMethods
    {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern int SHGetPropertyStoreFromParsingName(
            [MarshalAs(UnmanagedType.LPWStr)] string pszPath,
            IntPtr zeroWorks,
            int flags,
            ref Guid iid,
            out IntPtr propertyStore);
    }
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
