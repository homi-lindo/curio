#Requires -Version 5.1
<#
.SYNOPSIS
    Creates (or removes) a Start Menu shortcut for Curio Portable with the correct
    AppUserModel.ID so that Windows toast notifications work without MSIX.

.PARAMETER ExePath
    Full path to curio.exe in the portable installation directory.

.PARAMETER AppId
    Windows AppUserModel.ID to stamp on the shortcut.
    Defaults to 'App.Lume.Personal'.

.PARAMETER DisplayName
    Display name used for the Start Menu shortcut filename.
    Defaults to 'Curio Portable'.

.PARAMETER Remove
    When specified, deletes the shortcut instead of creating it.

.EXAMPLE
    .\Register-CurioShortcut.ps1 -ExePath 'C:\Users\me\AppData\Local\Curio\portable\curio-...\curio.exe'

.EXAMPLE
    .\Register-CurioShortcut.ps1 -ExePath 'C:\...\curio.exe' -Remove
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$ExePath,

    [string]$AppId = 'App.Lume.Personal',

    [string]$DisplayName = 'Curio Portable',

    [switch]$Remove
)

$ErrorActionPreference = 'Stop'

$startMenuPrograms = [Environment]::GetFolderPath('ApplicationData') |
    Join-Path -ChildPath 'Microsoft\Windows\Start Menu\Programs'
$shortcutPath = Join-Path $startMenuPrograms "$DisplayName.lnk"

if ($Remove) {
    if (Test-Path -LiteralPath $shortcutPath) {
        if ($PSCmdlet.ShouldProcess($shortcutPath, 'Remove shortcut')) {
            Remove-Item -LiteralPath $shortcutPath -Force
            Write-Host "Removed shortcut: $shortcutPath"
        }
    } else {
        Write-Host "Shortcut not found, nothing to remove: $shortcutPath"
    }
    return
}

if (-not (Test-Path -LiteralPath $ExePath)) {
    throw "curio.exe not found at: $ExePath"
}

$ExePath = (Resolve-Path -LiteralPath $ExePath).Path
$workingDir = Split-Path -Parent $ExePath

# Step 1: create the .lnk via WScript.Shell COM
if ($PSCmdlet.ShouldProcess($shortcutPath, 'Create shortcut')) {
    $wsh = New-Object -ComObject WScript.Shell
    $lnk = $wsh.CreateShortcut($shortcutPath)
    $lnk.TargetPath = $ExePath
    $lnk.WorkingDirectory = $workingDir
    $lnk.Description = $DisplayName
    $lnk.Save()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($lnk) | Out-Null
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh) | Out-Null
}

# Step 2: stamp AppUserModel.ID via IPropertyStore (SHGetPropertyStoreFromParsingName)
# This is what Windows requires to associate toast notifications with the shortcut.
Add-Type -Namespace CurioShortcut -Name Native -MemberDefinition @'
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern int SHGetPropertyStoreFromParsingName(
        [MarshalAs(UnmanagedType.LPWStr)] string pszPath,
        IntPtr zeroWorks,
        int flags,
        ref Guid iid,
        out IntPtr propertyStore);

    [DllImport("ole32.dll")]
    public static extern int PropVariantClear(IntPtr pvar);
'@ -ErrorAction SilentlyContinue

# PKEY_AppUserModel_ID: {9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}, pid 5
$PKEY_AUMID_fmtid = [Guid]::new('9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3')
$PKEY_AUMID_pid = 5

# IPropertyStore GUID
$IID_IPropertyStore = [Guid]::new('886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99')
$GPS_READWRITE = 2

$psPtr = [IntPtr]::Zero
$iid = $IID_IPropertyStore
$hr = [CurioShortcut.Native]::SHGetPropertyStoreFromParsingName(
    $shortcutPath,
    [IntPtr]::Zero,
    $GPS_READWRITE,
    [ref] $iid,
    [ref] $psPtr)

if ($hr -ne 0 -or $psPtr -eq [IntPtr]::Zero) {
    Write-Warning "SHGetPropertyStoreFromParsingName failed (hr=0x$('{0:X8}' -f $hr)). Shortcut created but AUMID was not stamped."
    return
}

try {
    # Marshal the IPropertyStore COM pointer and call SetValue + Commit via reflection
    $propStore = [System.Runtime.InteropServices.Marshal]::GetObjectForIUnknown($psPtr)

    # Build a PROPVARIANT for a VT_BSTR / VT_LPWSTR string value
    # The cleanest way in pure PS is to use the Windows.Storage.ApplicationData approach
    # or the Shell COM IPropertyStore.SetValue. We use the typed Store pattern:
    $propStoreType = $propStore.GetType()

    # Use IPropertyStore via late binding — works because shell32 implements it as a COM object
    # that PowerShell can late-bind to if it supports IDispatch.
    # If late binding is unavailable, fall back to the known reliable approach of writing
    # a tiny inline C# shim.
    $setValueMethod = $propStoreType.GetMethod('SetValue')
    if ($null -ne $setValueMethod) {
        # Reflection path (IDispatch-based COM wrappers)
        $key = New-Object PSObject -Property @{ fmtid = $PKEY_AUMID_fmtid; pid = $PKEY_AUMID_pid }
        $setValueMethod.Invoke($propStore, @($key, $AppId))
        $propStoreType.GetMethod('Commit')?.Invoke($propStore, @())
    } else {
        # Fallback: stamp AUMID via a small Add-Type C# shim
        Add-Type -Namespace CurioShortcut -Name PropStoreHelper -MemberDefinition @"
            using System;
            using System.Runtime.InteropServices;
            using System.Runtime.InteropServices.ComTypes;

            [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
            public interface IPropertyStore {
                void GetCount(out uint cProps);
                void GetAt(uint iProp, out PROPERTYKEY pkey);
                void GetValue(ref PROPERTYKEY key, out PropVariant pv);
                void SetValue(ref PROPERTYKEY key, ref PropVariant pv);
                void Commit();
            }

            [StructLayout(LayoutKind.Sequential)]
            public struct PROPERTYKEY {
                public Guid fmtid;
                public uint pid;
            }

            [StructLayout(LayoutKind.Explicit)]
            public struct PropVariant {
                [FieldOffset(0)] public ushort vt;
                [FieldOffset(8)] public IntPtr pwszVal;
            }

            public static class AumidStamper {
                private static readonly Guid PKEY_AUMID_fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");
                private const uint PKEY_AUMID_pid = 5;
                private const ushort VT_LPWSTR = 31;

                public static void Stamp(IntPtr pStore, string appId) {
                    var ps = (IPropertyStore)Marshal.GetObjectForIUnknown(pStore);
                    var key = new PROPERTYKEY { fmtid = PKEY_AUMID_fmtid, pid = PKEY_AUMID_pid };
                    var pv  = new PropVariant { vt = VT_LPWSTR, pwszVal = Marshal.StringToCoTaskMemUni(appId) };
                    try {
                        ps.SetValue(ref key, ref pv);
                        ps.Commit();
                    } finally {
                        Marshal.FreeCoTaskMem(pv.pwszVal);
                    }
                }
            }
"@ -ErrorAction SilentlyContinue

        if ([CurioShortcut.AumidStamper]) {
            [CurioShortcut.AumidStamper]::Stamp($psPtr, $AppId)
        }
    }

    Write-Host "Shortcut created and AppUserModel.ID stamped: $shortcutPath"
    Write-Host "  Target : $ExePath"
    Write-Host "  AUMID  : $AppId"
} finally {
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($propStore) | Out-Null
}
