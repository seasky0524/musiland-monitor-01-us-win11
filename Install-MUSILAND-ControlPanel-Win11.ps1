[CmdletBinding()]
param(
    [switch] $NoPause,
    [switch] $SkipLaunchApp,
    [string] $SourcePath
)

$ErrorActionPreference = 'Stop'

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Pause-IfNeeded {
    if (-not $NoPause) {
        Write-Host ''
        Read-Host 'Press Enter to close'
    }
}

if (-not (Test-Administrator)) {
    $argsList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($NoPause) {
        $argsList += '-NoPause'
    }
    if ($SkipLaunchApp) {
        $argsList += '-SkipLaunchApp'
    }
    if ($SourcePath) {
        $argsList += @('-SourcePath', "`"$SourcePath`"")
    }

    Start-Process powershell.exe -Verb RunAs -ArgumentList $argsList
    exit
}

$root = Split-Path -Parent $PSCommandPath
if (-not $SourcePath) {
    $sourceCandidates = @(
        (Join-Path $root 'prepared-driver\payload-x64'),
        (Join-Path $root 'extracted-full-installer\payload-x64-extrac32')
    )
    $SourcePath = $sourceCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if ($SourcePath) {
    $SourcePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SourcePath)
}

function Copy-PayloadFile {
    param(
        [Parameter(Mandatory)] [string] $SourceName,
        [Parameter(Mandatory)] [string] $DestinationDirectory,
        [string] $DestinationName
    )

    if (-not $DestinationName) {
        $DestinationName = $SourceName
    }

    $source = Join-Path $SourcePath $SourceName
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Missing payload file: $source"
    }

    New-Item -ItemType Directory -Force -Path $DestinationDirectory | Out-Null
    $destination = Join-Path $DestinationDirectory $DestinationName
    Copy-Item -LiteralPath $source -Destination $destination -Force
    return $destination
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory)] [string] $FilePath,
        [Parameter(Mandatory)] [string[]] $Arguments,
        [int[]] $AllowedExitCodes = @(0)
    )

    Write-Host "$FilePath $($Arguments -join ' ')"
    & $FilePath @Arguments
    $code = $LASTEXITCODE
    if ($AllowedExitCodes -notcontains $code) {
        throw "$FilePath failed with exit code $code"
    }
}

try {
    if (-not $SourcePath -or -not (Test-Path -LiteralPath $SourcePath)) {
        throw "Payload directory not found. Put MlCyMon_2.4.2.1_build20131204.exe next to the installer and run Install-MUSILAND-Monitor01US-Win11.cmd first."
    }

    Write-Host '=== MUSILAND Monitor Series(USB) control panel/service installer ==='
    Write-Host "Payload: $SourcePath"

    $appDir = Join-Path ${env:ProgramFiles(x86)} 'MUSILAND\Monitor Series(USB)'
    $platformDir = Join-Path $appDir 'platforms'
    $system32 = Join-Path $env:windir 'System32'
    $syswow64 = Join-Path $env:windir 'SysWOW64'
    $svcExe = Join-Path $syswow64 'MlCyMonSvc.exe'
    $appExe = Join-Path $appDir 'MlCyMonApp.exe'

    $appFiles = @(
        'MlCyMonApp.exe',
        'config.ini',
        'mlcymonapp_zh_CN.qm',
        'mlcymonapp_zh_TW.qm',
        'Qt5Core.dll',
        'Qt5Gui.dll',
        'Qt5Widgets.dll'
    )
    $appFiles += Get-ChildItem -LiteralPath $SourcePath -Filter 'qt_*.qm' -File | Select-Object -ExpandProperty Name

    foreach ($file in ($appFiles | Sort-Object -Unique)) {
        Copy-PayloadFile -SourceName $file -DestinationDirectory $appDir | Out-Null
    }

    Copy-PayloadFile -SourceName 'qminimal.dll' -DestinationDirectory $platformDir | Out-Null
    Copy-PayloadFile -SourceName 'qwindows.dll' -DestinationDirectory $platformDir | Out-Null

    $runtimeMap = @{
        'F_CENTRAL_msvcp110_x86.D371D00B_69EC_3F8E_A622_74710A89ADC1' = 'msvcp110.dll'
        'F_CENTRAL_msvcr110_x86.D371D00B_69EC_3F8E_A622_74710A89ADC1' = 'msvcr110.dll'
        'F_CENTRAL_vccorlib110_x86.D371D00B_69EC_3F8E_A622_74710A89ADC1' = 'vccorlib110.dll'
    }

    foreach ($entry in $runtimeMap.GetEnumerator()) {
        Copy-PayloadFile -SourceName $entry.Key -DestinationDirectory $appDir -DestinationName $entry.Value | Out-Null
        $systemRuntime = Join-Path $syswow64 $entry.Value
        if (-not (Test-Path -LiteralPath $systemRuntime)) {
            Copy-PayloadFile -SourceName $entry.Key -DestinationDirectory $syswow64 -DestinationName $entry.Value | Out-Null
        }
    }

    Copy-PayloadFile -SourceName 'MlCyMonSvc.exe' -DestinationDirectory $syswow64 | Out-Null
    Copy-PayloadFile -SourceName 'MlCyMonASIO.dll' -DestinationDirectory $system32 | Out-Null
    Copy-PayloadFile -SourceName 'MlCyMonASIO_x86.dll' -DestinationDirectory $syswow64 -DestinationName 'MlCyMonASIO.dll' | Out-Null
    Copy-PayloadFile -SourceName 'MlCoInst.dll' -DestinationDirectory $system32 | Out-Null

    $asioGuid = '{69628033-CBFE-4b26-903A-212B99D36373}'
    $asioName = 'MUSILAND Monitor Series(USB)'
    $asio64 = Join-Path $system32 'MlCyMonASIO.dll'
    $asio32 = Join-Path $syswow64 'MlCyMonASIO.dll'

    Invoke-Checked reg.exe @('add', 'HKCU\Software\MUSILAND\Monitor Series(USB)', '/v', 'installed', '/t', 'REG_DWORD', '/d', '1', '/f')
    Invoke-Checked reg.exe @('add', 'HKCU\Software\MUSILAND\Monitor Series(USB)', '/v', 'cpl', '/t', 'REG_DWORD', '/d', '1', '/f')

    Invoke-Checked reg.exe @('add', 'HKLM\SOFTWARE\ASIO\MUSILAND Monitor Series(USB)', '/ve', '/d', 'CMLCYM', '/f', '/reg:64')
    Invoke-Checked reg.exe @('add', 'HKLM\SOFTWARE\ASIO\MUSILAND Monitor Series(USB)', '/v', 'CLSID', '/d', $asioGuid, '/f', '/reg:64')
    Invoke-Checked reg.exe @('add', 'HKLM\SOFTWARE\ASIO\MUSILAND Monitor Series(USB)', '/v', 'Description', '/d', $asioName, '/f', '/reg:64')
    Invoke-Checked reg.exe @('add', 'HKLM\SOFTWARE\ASIO\MUSILAND Monitor Series(USB)', '/ve', '/d', 'CMLCYM', '/f', '/reg:32')
    Invoke-Checked reg.exe @('add', 'HKLM\SOFTWARE\ASIO\MUSILAND Monitor Series(USB)', '/v', 'CLSID', '/d', $asioGuid, '/f', '/reg:32')
    Invoke-Checked reg.exe @('add', 'HKLM\SOFTWARE\ASIO\MUSILAND Monitor Series(USB)', '/v', 'Description', '/d', $asioName, '/f', '/reg:32')

    Invoke-Checked reg.exe @('add', "HKLM\SOFTWARE\Classes\CLSID\$asioGuid", '/ve', '/d', $asioName, '/f', '/reg:64')
    Invoke-Checked reg.exe @('add', "HKLM\SOFTWARE\Classes\CLSID\$asioGuid\InprocServer32", '/ve', '/d', $asio64, '/f', '/reg:64')
    Invoke-Checked reg.exe @('add', "HKLM\SOFTWARE\Classes\CLSID\$asioGuid\InprocServer32", '/v', 'ThreadingModel', '/d', 'Apartment', '/f', '/reg:64')
    Invoke-Checked reg.exe @('add', "HKLM\SOFTWARE\Classes\CLSID\$asioGuid", '/ve', '/d', $asioName, '/f', '/reg:32')
    Invoke-Checked reg.exe @('add', "HKLM\SOFTWARE\Classes\CLSID\$asioGuid\InprocServer32", '/ve', '/d', $asio32, '/f', '/reg:32')
    Invoke-Checked reg.exe @('add', "HKLM\SOFTWARE\Classes\CLSID\$asioGuid\InprocServer32", '/v', 'ThreadingModel', '/d', 'Apartment', '/f', '/reg:32')

    Invoke-Checked reg.exe @('add', 'HKLM\SYSTEM\CurrentControlSet\services\eventlog\Application\MlCyMonSvc', '/v', 'EventMessageFile', '/t', 'REG_EXPAND_SZ', '/d', '%SystemRoot%\SysWOW64\MlCyMonSvc.exe', '/f')
    Invoke-Checked reg.exe @('add', 'HKLM\SYSTEM\CurrentControlSet\services\eventlog\Application\MlCyMonSvc', '/v', 'TypeSupported', '/t', 'REG_DWORD', '/d', '7', '/f')

    $existingService = Get-Service -Name MlCyMonSvc -ErrorAction SilentlyContinue
    if ($existingService) {
        if ($existingService.Status -ne 'Stopped') {
            Stop-Service -Name MlCyMonSvc -Force -ErrorAction SilentlyContinue
        }
        Invoke-Checked sc.exe @('config', 'MlCyMonSvc', 'binPath=', "`"$svcExe`"", 'type=', 'own', 'start=', 'auto', 'DisplayName=', 'MUSILAND Monitor Series(USB) CPL Daemon')
    } else {
        Invoke-Checked sc.exe @('create', 'MlCyMonSvc', 'binPath=', "`"$svcExe`"", 'type=', 'own', 'start=', 'auto', 'DisplayName=', 'MUSILAND Monitor Series(USB) CPL Daemon')
    }

    Invoke-Checked sc.exe @('description', 'MlCyMonSvc', 'MUSILAND Monitor Series(USB) Control Panel Daemon')
    Start-Service -Name MlCyMonSvc

    if (-not $SkipLaunchApp) {
        Start-Process -FilePath $appExe -WorkingDirectory $appDir
    }

    Write-Host ''
    Write-Host 'Control panel/service installation status:'
    Get-Service -Name MlCyMonSvc |
        Select-Object Name, DisplayName, Status, StartType |
        Format-Table -AutoSize

    Write-Host "Control panel: $appExe"
    Write-Host 'Done.'
} catch {
    Write-Error $_.Exception.Message
    throw
} finally {
    Pause-IfNeeded
}
