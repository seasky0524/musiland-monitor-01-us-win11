[CmdletBinding()]
param(
    [switch] $NoPause
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

    Start-Process powershell.exe -Verb RunAs -ArgumentList $argsList
    exit
}

$root = Split-Path -Parent $PSCommandPath
$logPath = Join-Path $root 'Install-MUSILAND-Monitor01US-Win11.log'

Start-Transcript -Path $logPath -Force | Out-Null

try {
    $preparedRoot = Join-Path $root 'prepared-driver'
    $preparedFirmwareInf = Join-Path $preparedRoot 'DriverFW\MlCyMonFW.inf'
    $preparedBusInf = Join-Path $preparedRoot 'DriverBus\MlCyMonBus.inf'
    $preparedAudioInf = Join-Path $preparedRoot 'Driver\MlCyMon.inf'
    $preparedPayload = Join-Path $preparedRoot 'payload-x64'

    $prepareScript = Join-Path $root 'Prepare-MUSILAND-Payload.ps1'
    $vendorInstaller = Join-Path $root 'MlCyMon_2.4.2.1_build20131204.exe'
    $preparedFiles = @($preparedFirmwareInf, $preparedBusInf, $preparedAudioInf, (Join-Path $preparedPayload 'MlCyMonApp.exe'))

    if (($preparedFiles | Where-Object { -not (Test-Path -LiteralPath $_) }) -and
        (Test-Path -LiteralPath $prepareScript) -and
        (Test-Path -LiteralPath $vendorInstaller)) {
        Write-Host 'Preparing driver/control-panel payload from the original vendor installer...'
        & $prepareScript -InstallerPath $vendorInstaller -OutputRoot $preparedRoot
    }

    if ((Test-Path -LiteralPath $preparedFirmwareInf) -and
        (Test-Path -LiteralPath $preparedBusInf) -and
        (Test-Path -LiteralPath $preparedAudioInf)) {
        $firmwareInf = $preparedFirmwareInf
        $busInf = $preparedBusInf
        $audioInf = $preparedAudioInf
    } else {
        $firmwareInf = Join-Path $root 'downloaded-firmware-driver\extracted\MUSILAND\WinAll\Monitor-USB\DriverFW\MlCyMonFW.inf'
        $busInf = Join-Path $root 'mlcymonbus.inf'
        $audioInf = Join-Path $root 'downloaded-audio-driver\extracted\MUSILAND\WinAll\Monitor-USB\Driver\MlCyMon.inf'
        $preparedPayload = Join-Path $root 'extracted-full-installer\payload-x64-extrac32'
    }

    foreach ($path in @($firmwareInf, $busInf, $audioInf)) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Missing required driver file: $path"
        }
    }

    function Invoke-PnpUtil {
        param([Parameter(Mandatory)] [string[]] $Arguments)

        Write-Host ''
        Write-Host "pnputil $($Arguments -join ' ')"
        & pnputil.exe @Arguments
        $code = $LASTEXITCODE

        # 259 means pnputil found the package already present/current.
        if ($code -ne 0 -and $code -ne 259) {
            throw "pnputil failed with exit code $code"
        }

        return $code
    }

    function Get-PresentDevice {
        param([Parameter(Mandatory)] [string] $InstanceIdPrefix)

        Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
            Where-Object { $_.InstanceId -like "$InstanceIdPrefix*" } |
            Select-Object -First 1
    }

    function Get-DevicePropertyData {
        param(
            [Parameter(Mandatory)] [string] $InstanceId,
            [Parameter(Mandatory)] [string] $KeyName
        )

        try {
            (Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName $KeyName -ErrorAction Stop).Data
        } catch {
            $null
        }
    }

    function Wait-ForDevice {
        param(
            [Parameter(Mandatory)] [string] $InstanceIdPrefix,
            [int] $Seconds = 30
        )

        for ($i = 0; $i -lt $Seconds; $i++) {
            $device = Get-PresentDevice -InstanceIdPrefix $InstanceIdPrefix
            if ($device) {
                return $device
            }
            Start-Sleep -Seconds 1
        }

        return $null
    }

    Write-Host '=== MUSILAND Monitor 01 US Windows 11 one-click installer ==='

    $firmwareMode = Get-PresentDevice -InstanceIdPrefix 'USB\VID_04B4&PID_5125'
    if ($firmwareMode) {
        Write-Host "Firmware-mode device found: $($firmwareMode.InstanceId)"
        Invoke-PnpUtil -Arguments @('/add-driver', $firmwareInf, '/install') | Out-Null
        Invoke-PnpUtil -Arguments @('/scan-devices') | Out-Null
    } else {
        Write-Host 'Firmware-mode PID_5125 device not present; skipping firmware driver install.'
    }

    $busDevice = Wait-ForDevice -InstanceIdPrefix 'USB\VID_04B4&PID_5135' -Seconds 35
    if (-not $busDevice) {
        Write-Host 'PID_5135 device not found yet. If the device was just plugged in, unplug/replug it and run this installer again.'
    } else {
        Write-Host "Bus-mode device found: $($busDevice.InstanceId)"
    }

    Invoke-PnpUtil -Arguments @('/add-driver', $busInf, '/install') | Out-Null
    Invoke-PnpUtil -Arguments @('/scan-devices') | Out-Null

    $audioDevice = Wait-ForDevice -InstanceIdPrefix 'MUAUDIO\VID_04B4&PID_5135' -Seconds 35
    if ($audioDevice) {
        $service = Get-DevicePropertyData -InstanceId $audioDevice.InstanceId -KeyName 'DEVPKEY_Device_Service'
        $problem = Get-DevicePropertyData -InstanceId $audioDevice.InstanceId -KeyName 'DEVPKEY_Device_ProblemCode'
        $driverInf = Get-DevicePropertyData -InstanceId $audioDevice.InstanceId -KeyName 'DEVPKEY_Device_DriverInfPath'

        Write-Host "Audio device found: $($audioDevice.InstanceId)"
        Write-Host "Current audio service: $service"
        Write-Host "Current audio problem code: $problem"
        Write-Host "Current audio INF: $driverInf"

        if ($service -eq 'MlMonUsbKs' -and $driverInf) {
            Write-Host "Removing incompatible audio package: $driverInf"
            Invoke-PnpUtil -Arguments @('/delete-driver', $driverInf, '/uninstall', '/force') | Out-Null
            Invoke-PnpUtil -Arguments @('/scan-devices') | Out-Null
        }
    } else {
        Write-Host 'MUAUDIO child device not found yet. Installing audio package anyway.'
    }

    Invoke-PnpUtil -Arguments @('/add-driver', $audioInf, '/install') | Out-Null
    Invoke-PnpUtil -Arguments @('/scan-devices') | Out-Null

    $controlPanelInstaller = Join-Path $root 'Install-MUSILAND-ControlPanel-Win11.ps1'
    if (Test-Path -LiteralPath $controlPanelInstaller) {
        Write-Host ''
        Write-Host 'Installing MUSILAND control panel and CPL daemon service...'
        & $controlPanelInstaller -NoPause -SourcePath $preparedPayload
    } else {
        Write-Warning "Control panel installer not found: $controlPanelInstaller"
    }

    Write-Host ''
    Write-Host 'Final MUSILAND device status:'
    Get-PnpDevice -PresentOnly |
        Where-Object {
            $_.InstanceId -like 'USB\VID_04B4*' -or
            $_.InstanceId -like 'MUAUDIO*' -or
            $_.FriendlyName -like '*MUSILAND*' -or
            $_.FriendlyName -like '*Monitor 01*'
        } |
        Select-Object Status, Class, FriendlyName, InstanceId |
        Format-Table -AutoSize

    Write-Host ''
    Write-Host 'Driver and control services:'
    Get-Service -Name MlCyMonFW, MlCyMonBus, MlCyMon, MlCyMonSvc -ErrorAction SilentlyContinue |
        Select-Object Name, Status, StartType, ServiceType |
        Format-Table -AutoSize

    Write-Host ''
    Write-Host "Log saved to: $logPath"
    Write-Host 'If there is still no sound, choose the Windows output device named Speakers (MUSILAND Monitor 01 US).'
    Write-Host 'Use the SPDIF endpoint only for the digital output.'
    Write-Host 'Done.'
} catch {
    Write-Error $_.Exception.Message
    throw
} finally {
    Stop-Transcript | Out-Null
    Pause-IfNeeded
}
