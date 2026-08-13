@echo off
setlocal
title Delanclip PS3 Eye Diagnostics
set "DELAN_SCRIPT=%~f0"

echo ============================================================
echo        Delanclip PS3 Eye Diagnostics
echo ============================================================
echo.
echo Keep the PS3 Eye camera connected while this tool runs.
echo.
echo This tool collects Windows device and driver information only.
echo It does NOT collect personal documents, browser data, passwords,
echo emails, photos or other personal files.
echo.
echo The diagnostic ZIP will be created on your Desktop.
echo.
pause

echo.
echo Collecting diagnostics. Please wait...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$raw = Get-Content -LiteralPath $env:DELAN_SCRIPT -Raw; $marker = '### DELANCLIP_' + 'POWERSHELL ###'; $idx = $raw.LastIndexOf($marker); if ($idx -lt 0) { throw 'Embedded PowerShell section not found.' }; $code = $raw.Substring($idx + $marker.Length); Invoke-Expression $code"

set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" (
    echo Diagnostics did not complete successfully.
    echo Please take a screenshot of this window and send it to Delanclip Support.
) else (
    echo Diagnostics finished successfully.
    echo The ZIP file has been saved to your Desktop.
    echo Please attach that ZIP file to your reply to Delanclip Support.
)
echo.
pause
exit /b %RC%

### DELANCLIP_POWERSHELL ###
$ErrorActionPreference = 'Stop'

$desktop = [Environment]::GetFolderPath('Desktop')
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$work = Join-Path $env:TEMP ("Delanclip-PS3Eye-Diagnostics-" + $stamp)
$zipPath = Join-Path $desktop ("Delanclip-PS3Eye-Diagnostics-" + $stamp + ".zip")

New-Item -ItemType Directory -Force -Path $work | Out-Null
$errorsFile = Join-Path $work 'errors.txt'
"No collection errors recorded." | Set-Content -LiteralPath $errorsFile -Encoding UTF8

function Record-Error {
    param([string]$Step, [object]$Err)
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Step : $($Err.Exception.Message)"
    Add-Content -LiteralPath $errorsFile -Value $line -Encoding UTF8
}

function Run-Step {
    param([string]$Name, [scriptblock]$Action)
    try {
        & $Action
    }
    catch {
        Record-Error -Step $Name -Err $_
    }
}

Run-Step 'README' {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    @"
Delanclip PS3 Eye Diagnostics
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
Administrator: $isAdmin

Purpose:
Collect Windows device and driver information needed to diagnose PS3 Eye camera problems.

Collected:
- Windows version/build
- matching camera/PnP devices
- device properties and hardware IDs
- installed driver information
- PnPUtil device/driver output
- Windows SetupAPI device installation log

Not collected:
- personal documents
- browser history
- passwords
- emails
- photos
- unrelated personal files
"@ | Set-Content -LiteralPath (Join-Path $work 'README.txt') -Encoding UTF8
}

Run-Step 'Windows information' {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    [PSCustomObject]@{
        Caption = $os.Caption
        Version = $os.Version
        BuildNumber = $os.BuildNumber
        OSArchitecture = $os.OSArchitecture
        LastBootUpTime = $os.LastBootUpTime
        Manufacturer = $cs.Manufacturer
        Model = $cs.Model
    } | Format-List | Out-String -Width 300 | Set-Content -LiteralPath (Join-Path $work 'windows.txt') -Encoding UTF8
}

$script:devices = @()
Run-Step 'PnP device enumeration' {
    $script:devices = @(Get-PnpDevice -PresentOnly | Where-Object {
        ($_.Class -eq 'Camera') -or
        ($_.Class -eq 'Image') -or
        ($_.FriendlyName -match '(?i)PS3|Eye|USB Camera')
    })

    if ($script:devices.Count -eq 0) {
        'No matching present camera devices were found.' | Set-Content -LiteralPath (Join-Path $work 'camera-devices.txt') -Encoding UTF8
    }
    else {
        $script:devices |
            Select-Object Status, Class, FriendlyName, InstanceId |
            Format-Table -AutoSize |
            Out-String -Width 500 |
            Set-Content -LiteralPath (Join-Path $work 'camera-devices.txt') -Encoding UTF8
    }
}

Run-Step 'PnP device properties' {
    $propsPath = Join-Path $work 'camera-properties.txt'
    if ($script:devices.Count -eq 0) {
        'No matching devices available for property collection.' | Set-Content -LiteralPath $propsPath -Encoding UTF8
    }
    else {
        foreach ($device in $script:devices) {
            Add-Content -LiteralPath $propsPath -Value ("===== " + $device.FriendlyName + " =====") -Encoding UTF8
            Add-Content -LiteralPath $propsPath -Value ("InstanceId: " + $device.InstanceId) -Encoding UTF8
            Get-PnpDeviceProperty -InstanceId $device.InstanceId |
                Select-Object KeyName, Type, Data |
                Format-List |
                Out-String -Width 500 |
                Add-Content -LiteralPath $propsPath -Encoding UTF8
        }
    }
}

Run-Step 'Signed driver information' {
    $driverPath = Join-Path $work 'camera-drivers.txt'
    $allDrivers = @(Get-CimInstance Win32_PnPSignedDriver)

    if ($script:devices.Count -eq 0) {
        'No matching devices available for driver collection.' | Set-Content -LiteralPath $driverPath -Encoding UTF8
    }
    else {
        foreach ($device in $script:devices) {
            Add-Content -LiteralPath $driverPath -Value ("===== " + $device.FriendlyName + " =====") -Encoding UTF8
            $matches = @($allDrivers | Where-Object { $_.DeviceID -eq $device.InstanceId })
            if ($matches.Count -eq 0) {
                'No Win32_PnPSignedDriver match found.' | Add-Content -LiteralPath $driverPath -Encoding UTF8
            }
            else {
                $matches |
                    Select-Object DeviceName, DeviceClass, Manufacturer, DriverProviderName, DriverVersion, DriverDate, InfName, IsSigned, Signer, DeviceID |
                    Format-List |
                    Out-String -Width 500 |
                    Add-Content -LiteralPath $driverPath -Encoding UTF8
            }
        }
    }
}

Run-Step 'PnP entity information' {
    Get-CimInstance Win32_PnPEntity |
        Where-Object {
            ($_.PNPClass -eq 'Camera') -or
            ($_.PNPClass -eq 'Image') -or
            ($_.Name -match '(?i)PS3|Eye|USB Camera')
        } |
        Select-Object Name, Status, Manufacturer, PNPClass, Service, ClassGuid, ConfigManagerErrorCode, PNPDeviceID |
        Format-List |
        Out-String -Width 500 |
        Set-Content -LiteralPath (Join-Path $work 'camera-pnp-entities.txt') -Encoding UTF8
}

Run-Step 'PnPUtil connected devices' {
    $pnp = Join-Path $env:windir 'System32\pnputil.exe'
    $out = & $pnp /enum-devices /connected /deviceids /drivers 2>&1
    $out | Out-String -Width 500 | Set-Content -LiteralPath (Join-Path $work 'connected-devices.txt') -Encoding UTF8
    "PnPUtil exit code: $LASTEXITCODE" | Add-Content -LiteralPath (Join-Path $work 'connected-devices.txt') -Encoding UTF8
}

Run-Step 'PnPUtil driver store' {
    $pnp = Join-Path $env:windir 'System32\pnputil.exe'
    $out = & $pnp /enum-drivers 2>&1
    $out | Out-String -Width 500 | Set-Content -LiteralPath (Join-Path $work 'driver-store.txt') -Encoding UTF8
    "PnPUtil exit code: $LASTEXITCODE" | Add-Content -LiteralPath (Join-Path $work 'driver-store.txt') -Encoding UTF8
}

Run-Step 'SetupAPI device installation log' {
    $setupApi = Join-Path $env:windir 'INF\setupapi.dev.log'
    if (Test-Path -LiteralPath $setupApi) {
        Copy-Item -LiteralPath $setupApi -Destination (Join-Path $work 'setupapi.dev.log') -Force
    }
    else {
        'setupapi.dev.log was not found.' | Set-Content -LiteralPath (Join-Path $work 'setupapi-log-status.txt') -Encoding UTF8
    }
}

Run-Step 'Recent device installation events' {
    $start = (Get-Date).AddDays(-14)
    Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$start} -ErrorAction Stop |
        Where-Object { $_.ProviderName -match '(?i)Kernel-PnP|UserPnp|DriverFrameworks' } |
        Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message |
        Format-List |
        Out-String -Width 500 |
        Set-Content -LiteralPath (Join-Path $work 'recent-device-events.txt') -Encoding UTF8
}

Run-Step 'Compress diagnostic package' {
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }
    Compress-Archive -Path (Join-Path $work '*') -DestinationPath $zipPath -CompressionLevel Optimal -Force
}

if (-not (Test-Path -LiteralPath $zipPath)) {
    Write-Host 'ERROR: Diagnostic ZIP was not created.' -ForegroundColor Red
    exit 1
}

try {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
catch {}

Write-Host ''
Write-Host 'Diagnostic package created:' -ForegroundColor Green
Write-Host $zipPath -ForegroundColor Cyan
Write-Host ''

try {
    Start-Process explorer.exe -ArgumentList "/select,`"$zipPath`""
}
catch {}

exit 0
