[CmdletBinding()]
param(
    [string] $InstallerPath,
    [string] $OutputRoot,
    [switch] $Force
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSCommandPath
if (-not $InstallerPath) {
    $InstallerPath = Join-Path $root 'MlCyMon_2.4.2.1_build20131204.exe'
}
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $root 'prepared-driver'
}

$InstallerPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InstallerPath)
$OutputRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputRoot)

if (-not (Test-Path -LiteralPath $InstallerPath)) {
    throw "Original installer not found: $InstallerPath"
}

$exportMsiStream = Join-Path $root 'Export-MsiStream.ps1'
if (-not (Test-Path -LiteralPath $exportMsiStream)) {
    throw "Missing helper script: $exportMsiStream"
}

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;

public static class PeResourceExporter
{
    private const uint LOAD_LIBRARY_AS_DATAFILE = 0x00000002;

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr LoadLibraryEx(string lpFileName, IntPtr hFile, uint dwFlags);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode, EntryPoint = "FindResourceW")]
    private static extern IntPtr FindResource(IntPtr hModule, string lpName, IntPtr lpType);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint SizeofResource(IntPtr hModule, IntPtr hResInfo);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr LoadResource(IntPtr hModule, IntPtr hResInfo);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr LockResource(IntPtr hResData);

    [DllImport("kernel32.dll")]
    private static extern bool FreeLibrary(IntPtr hModule);

    public static int Export(string exePath, string resourceName, int resourceType, string outputPath)
    {
        IntPtr module = LoadLibraryEx(exePath, IntPtr.Zero, LOAD_LIBRARY_AS_DATAFILE);
        if (module == IntPtr.Zero)
        {
            ThrowLastWin32("LoadLibraryEx");
        }

        try
        {
            IntPtr resource = FindResource(module, resourceName, (IntPtr)resourceType);
            if (resource == IntPtr.Zero)
            {
                ThrowLastWin32("FindResource");
            }

            uint size = SizeofResource(module, resource);
            if (size == 0)
            {
                ThrowLastWin32("SizeofResource");
            }

            IntPtr loaded = LoadResource(module, resource);
            if (loaded == IntPtr.Zero)
            {
                ThrowLastWin32("LoadResource");
            }

            IntPtr pointer = LockResource(loaded);
            if (pointer == IntPtr.Zero)
            {
                ThrowLastWin32("LockResource");
            }

            byte[] bytes = new byte[size];
            Marshal.Copy(pointer, bytes, 0, (int)size);

            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(outputPath)));
            File.WriteAllBytes(outputPath, bytes);
            return (int)size;
        }
        finally
        {
            FreeLibrary(module);
        }
    }

    private static void ThrowLastWin32(string api)
    {
        int error = Marshal.GetLastWin32Error();
        throw new InvalidOperationException(api + " failed with Win32 error " + error);
    }
}
'@

function Copy-RenamedPayloadFile {
    param(
        [Parameter(Mandatory)] [string] $SourceDirectory,
        [Parameter(Mandatory)] [string] $SourceName,
        [Parameter(Mandatory)] [string] $DestinationDirectory,
        [Parameter(Mandatory)] [string] $DestinationName
    )

    $source = Join-Path $SourceDirectory $SourceName
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Missing extracted payload file: $source"
    }

    New-Item -ItemType Directory -Force -Path $DestinationDirectory | Out-Null
    Copy-Item -LiteralPath $source -Destination (Join-Path $DestinationDirectory $DestinationName) -Force
}

function Test-PreparedPayload {
    param([Parameter(Mandatory)] [string] $BasePath)

    $required = @(
        'DriverFW\MlCyMonFW.inf',
        'DriverFW\MlCyMonFW.sys',
        'DriverFW\MlCyMonFW.cat',
        'DriverFW\WdfCoInstaller01011.dll',
        'DriverBus\MlCyMonBus.inf',
        'DriverBus\MlCyMonBus.sys',
        'DriverBus\MlCyMonBus.cat',
        'DriverBus\WdfCoInstaller01011.dll',
        'Driver\MlCyMon.inf',
        'Driver\MlCyMon.sys',
        'Driver\MlCyMon.cat',
        'payload-x64\MlCyMonApp.exe',
        'payload-x64\MlCyMonSvc.exe',
        'payload-x64\Qt5Core.dll',
        'payload-x64\qwindows.dll'
    )

    foreach ($relative in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $BasePath $relative))) {
            return $false
        }
    }

    return $true
}

if ((Test-PreparedPayload -BasePath $OutputRoot) -and -not $Force) {
    Write-Host "Prepared payload already exists: $OutputRoot"
    return
}

$workDir = Join-Path $OutputRoot '_work'
$payloadDir = Join-Path $OutputRoot 'payload-x64'
$driverFwDir = Join-Path $OutputRoot 'DriverFW'
$driverBusDir = Join-Path $OutputRoot 'DriverBus'
$driverDir = Join-Path $OutputRoot 'Driver'

New-Item -ItemType Directory -Force -Path $workDir, $payloadDir, $driverFwDir, $driverBusDir, $driverDir | Out-Null

$msiPath = Join-Path $workDir 'MlCyMon_x64.msi'
$cabPath = Join-Path $workDir 'Setup_x64.cab'

Write-Host "Exporting x64 MSI resource from: $InstallerPath"
[PeResourceExporter]::Export($InstallerPath, 'X64', 40, $msiPath) | Out-Null

Write-Host 'Exporting Setup.cab from MSI stream...'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $exportMsiStream -MsiPath $msiPath -StreamName 'Setup.cab' -OutputPath $cabPath | Out-Null

Write-Host 'Extracting vendor payload with extrac32...'
& extrac32.exe /Y /E /L $payloadDir $cabPath | Out-Null

$expectedPayload = @(
    'MlCyMonApp.exe',
    'MlCyMonSvc.exe',
    'MlCyMon_win7.inf',
    'MlCyMon_win7.sys',
    'MlCyMon_win7.cat',
    'MlCyMonBus_win7.inf',
    'MlCyMonBus_win7.sys',
    'MlCyMonBus_win7.cat',
    'MlCyMonFW_win7.inf',
    'MlCyMonFW_win7.sys',
    'MlCyMonFW_win7.cat',
    'WdfCoInstaller01011Bus_win7.dll',
    'WdfCoInstaller01011FW_win7.dll',
    'Qt5Core.dll',
    'Qt5Gui.dll',
    'Qt5Widgets.dll',
    'qwindows.dll',
    'qminimal.dll'
)

foreach ($file in $expectedPayload) {
    if (-not (Test-Path -LiteralPath (Join-Path $payloadDir $file))) {
        throw "Payload extraction did not produce required file: $file"
    }
}

Copy-RenamedPayloadFile $payloadDir 'MlCyMonFW_win7.inf' $driverFwDir 'MlCyMonFW.inf'
Copy-RenamedPayloadFile $payloadDir 'MlCyMonFW_win7.sys' $driverFwDir 'MlCyMonFW.sys'
Copy-RenamedPayloadFile $payloadDir 'MlCyMonFW_win7.cat' $driverFwDir 'MlCyMonFW.cat'
Copy-RenamedPayloadFile $payloadDir 'WdfCoInstaller01011FW_win7.dll' $driverFwDir 'WdfCoInstaller01011.dll'

Copy-RenamedPayloadFile $payloadDir 'MlCyMonBus_win7.inf' $driverBusDir 'MlCyMonBus.inf'
Copy-RenamedPayloadFile $payloadDir 'MlCyMonBus_win7.sys' $driverBusDir 'MlCyMonBus.sys'
Copy-RenamedPayloadFile $payloadDir 'MlCyMonBus_win7.cat' $driverBusDir 'MlCyMonBus.cat'
Copy-RenamedPayloadFile $payloadDir 'WdfCoInstaller01011Bus_win7.dll' $driverBusDir 'WdfCoInstaller01011.dll'

Copy-RenamedPayloadFile $payloadDir 'MlCyMon_win7.inf' $driverDir 'MlCyMon.inf'
Copy-RenamedPayloadFile $payloadDir 'MlCyMon_win7.sys' $driverDir 'MlCyMon.sys'
Copy-RenamedPayloadFile $payloadDir 'MlCyMon_win7.cat' $driverDir 'MlCyMon.cat'

if (-not (Test-PreparedPayload -BasePath $OutputRoot)) {
    throw "Prepared payload validation failed: $OutputRoot"
}

Write-Host ''
Write-Host "Prepared driver/control-panel payload: $OutputRoot"
