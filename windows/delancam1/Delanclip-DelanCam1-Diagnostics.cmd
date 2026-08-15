@echo off
setlocal
title Delanclip DelanCam1 Diagnostics
set "DELAN_SCRIPT=%~f0"

echo ============================================================
echo        Delanclip DelanCam1 Diagnostics
echo ============================================================
echo.
echo Keep DelanCam1 connected while this tool runs.
echo.
echo This tool collects Windows device, driver and USB information only.
echo It does NOT change drivers, install software, open the camera stream,
echo collect photos, or send anything over the network.
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
$work = Join-Path $env:TEMP ("Delanclip-DelanCam1-Diagnostics-" + $stamp)
$zipPath = Join-Path $desktop ("Delanclip-DelanCam1-Diagnostics-" + $stamp + ".zip")

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

function Get-DevicePropertyData {
    param([string]$InstanceId, [string]$KeyName)
    try {
        return (Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName $KeyName -ErrorAction Stop).Data
    }
    catch {
        return $null
    }
}

function Get-DeviceParentChain {
    param([string]$InstanceId)
    $lines = New-Object System.Collections.Generic.List[string]
    $current = $InstanceId
    $seen = @{}

    for ($depth = 0; $depth -lt 10; $depth++) {
        if ([string]::IsNullOrWhiteSpace($current) -or $seen.ContainsKey($current)) { break }
        $seen[$current] = $true

        $device = $null
        try { $device = Get-PnpDevice -InstanceId $current -ErrorAction Stop } catch {}
        $location = Get-DevicePropertyData -InstanceId $current -KeyName 'DEVPKEY_Device_LocationPaths'
        $busDesc = Get-DevicePropertyData -InstanceId $current -KeyName 'DEVPKEY_Device_BusReportedDeviceDesc'

        $lines.Add("Depth: $depth")
        $lines.Add("InstanceId: $current")
        if ($device) {
            $lines.Add("Status: $($device.Status)")
            $lines.Add("Class: $($device.Class)")
            $lines.Add("FriendlyName: $($device.FriendlyName)")
        }
        if ($busDesc) { $lines.Add("BusReportedDeviceDesc: $busDesc") }
        if ($location) { $lines.Add("LocationPaths: $($location -join '; ')") }
        $lines.Add('')

        $parent = Get-DevicePropertyData -InstanceId $current -KeyName 'DEVPKEY_Device_Parent'
        if ([string]::IsNullOrWhiteSpace([string]$parent)) { break }
        $current = [string]$parent
    }

    return $lines
}

Run-Step 'README' {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    @"
Delanclip DelanCam1 Diagnostics
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
Administrator: $isAdmin

Purpose:
Collect Windows device, driver, PnP and USB-path information needed to diagnose DelanCam1 problems.

Collected:
- Windows version/build and computer model
- present camera devices
- DelanCam1 PnP properties and hardware IDs
- driver provider, version, date, INF and signature information
- Device Manager / ConfigManager status
- USB parent chain and location paths for DelanCam1
- recent Windows PnP events matching DelanCam1
- matching excerpts from the Windows SetupAPI device installation log
- a short diagnostic summary

Not collected:
- camera images or video
- personal documents
- browser history
- passwords
- emails
- photos
- unrelated personal files

The tool does not change drivers, install software or make network connections.
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

$script:allCameras = @()
$script:delanCams = @()
Run-Step 'Camera enumeration' {
    $script:allCameras = @(Get-PnpDevice -PresentOnly | Where-Object {
        ($_.Class -eq 'Camera') -or
        ($_.Class -eq 'Image') -or
        ($_.FriendlyName -match '(?i)DelanCam')
    })

    $script:delanCams = @($script:allCameras | Where-Object {
        $_.FriendlyName -match '(?i)^DelanCam1$|DelanCam1|DelanCam'
    })

    if ($script:allCameras.Count -eq 0) {
        'No present Camera or Image class devices were found.' | Set-Content -LiteralPath (Join-Path $work 'camera-devices.txt') -Encoding UTF8
    }
    else {
        $script:allCameras |
            Select-Object Status, Class, FriendlyName, InstanceId |
            Format-Table -AutoSize |
            Out-String -Width 500 |
            Set-Content -LiteralPath (Join-Path $work 'camera-devices.txt') -Encoding UTF8
    }
}

Run-Step 'DelanCam1 PnP properties' {
    $path = Join-Path $work 'delancam-properties.txt'
    if ($script:delanCams.Count -eq 0) {
        'No present device matching DelanCam1 was found.' | Set-Content -LiteralPath $path -Encoding UTF8
    }
    else {
        foreach ($device in $script:delanCams) {
            Add-Content -LiteralPath $path -Value ("===== " + $device.FriendlyName + " =====") -Encoding UTF8
            Add-Content -LiteralPath $path -Value ("InstanceId: " + $device.InstanceId) -Encoding UTF8
            Get-PnpDeviceProperty -InstanceId $device.InstanceId |
                Select-Object KeyName, Type, Data |
                Format-List |
                Out-String -Width 500 |
                Add-Content -LiteralPath $path -Encoding UTF8
        }
    }
}

$script:signedDrivers = @()
Run-Step 'DelanCam1 driver information' {
    $driverPath = Join-Path $work 'delancam-driver.txt'
    $allDrivers = @(Get-CimInstance Win32_PnPSignedDriver)
    $script:signedDrivers = @()

    if ($script:delanCams.Count -eq 0) {
        'No DelanCam1 device available for driver collection.' | Set-Content -LiteralPath $driverPath -Encoding UTF8
    }
    else {
        foreach ($device in $script:delanCams) {
            Add-Content -LiteralPath $driverPath -Value ("===== " + $device.FriendlyName + " =====") -Encoding UTF8
            $matches = @($allDrivers | Where-Object { $_.DeviceID -eq $device.InstanceId })
            $script:signedDrivers += $matches
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

$script:pnpEntities = @()
Run-Step 'DelanCam1 Device Manager status' {
    $path = Join-Path $work 'delancam-pnp.txt'
    $allEntities = @(Get-CimInstance Win32_PnPEntity)
    $ids = @($script:delanCams | ForEach-Object { $_.InstanceId })
    $script:pnpEntities = @($allEntities | Where-Object { $ids -contains $_.PNPDeviceID })

    if ($script:pnpEntities.Count -eq 0) {
        'No DelanCam1 PnP entity match found.' | Set-Content -LiteralPath $path -Encoding UTF8
    }
    else {
        $script:pnpEntities |
            Select-Object Name, Status, Manufacturer, PNPClass, Service, ClassGuid, ConfigManagerErrorCode, PNPDeviceID |
            Format-List |
            Out-String -Width 500 |
            Set-Content -LiteralPath $path -Encoding UTF8
    }
}

Run-Step 'DelanCam1 USB path' {
    $path = Join-Path $work 'usb-path.txt'
    if ($script:delanCams.Count -eq 0) {
        'No DelanCam1 device available for USB parent-chain collection.' | Set-Content -LiteralPath $path -Encoding UTF8
    }
    else {
        foreach ($device in $script:delanCams) {
            Add-Content -LiteralPath $path -Value ("===== " + $device.FriendlyName + " =====") -Encoding UTF8
            Get-DeviceParentChain -InstanceId $device.InstanceId |
                Add-Content -LiteralPath $path -Encoding UTF8
        }
    }
}

Run-Step 'Recent matching PnP events' {
    $path = Join-Path $work 'recent-device-events.txt'
    if ($script:delanCams.Count -eq 0) {
        'No DelanCam1 device available for event matching.' | Set-Content -LiteralPath $path -Encoding UTF8
    }
    else {
        $needles = New-Object System.Collections.Generic.List[string]
        $needles.Add('DelanCam1')
        foreach ($device in $script:delanCams) {
            $needles.Add($device.InstanceId)
            $parts = $device.InstanceId -split '\\'
            if ($parts.Count -ge 2) { $needles.Add(($parts[0] + '\\' + $parts[1])) }
        }
        $needles = @($needles | Select-Object -Unique)
        $start = (Get-Date).AddDays(-14)
        $events = @(Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$start} -ErrorAction Stop |
            Where-Object { $_.ProviderName -match '(?i)Kernel-PnP|UserPnp|DriverFrameworks' } |
            Where-Object {
                $message = [string]$_.Message
                $matched = $false
                foreach ($needle in $needles) {
                    if ($message.IndexOf($needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $matched = $true; break }
                }
                $matched
            })

        if ($events.Count -eq 0) {
            'No matching DelanCam1 PnP events were found in the last 14 days.' | Set-Content -LiteralPath $path -Encoding UTF8
        }
        else {
            $events |
                Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message |
                Format-List |
                Out-String -Width 500 |
                Set-Content -LiteralPath $path -Encoding UTF8
        }
    }
}

Run-Step 'Matching SetupAPI excerpts' {
    $path = Join-Path $work 'setupapi-delancam.txt'
    $setupApi = Join-Path $env:windir 'INF\setupapi.dev.log'
    if (-not (Test-Path -LiteralPath $setupApi)) {
        'setupapi.dev.log was not found.' | Set-Content -LiteralPath $path -Encoding UTF8
    }
    elseif ($script:delanCams.Count -eq 0) {
        'No DelanCam1 device available for targeted SetupAPI matching.' | Set-Content -LiteralPath $path -Encoding UTF8
    }
    else {
        $patterns = New-Object System.Collections.Generic.List[string]
        $patterns.Add('DelanCam1')
        foreach ($device in $script:delanCams) {
            $patterns.Add($device.InstanceId)
            $parts = $device.InstanceId -split '\\'
            if ($parts.Count -ge 2) { $patterns.Add(($parts[0] + '\\' + $parts[1])) }
        }
        $patterns = @($patterns | Select-Object -Unique)
        $matches = @(Select-String -Path $setupApi -Pattern $patterns -SimpleMatch -Context 8,16 -ErrorAction Stop)
        if ($matches.Count -eq 0) {
            'No matching DelanCam1 entries were found in setupapi.dev.log.' | Set-Content -LiteralPath $path -Encoding UTF8
        }
        else {
            $matches | Out-String -Width 500 | Set-Content -LiteralPath $path -Encoding UTF8
        }
    }
}

Run-Step 'Diagnostic summary' {
    $summary = New-Object System.Collections.Generic.List[string]
    $summary.Add('Delanclip DelanCam1 Diagnostics - Summary')
    $summary.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')")
    $summary.Add('')

    if ($script:delanCams.Count -eq 0) {
        $summary.Add('RESULT: DelanCam1 was not found by name among present camera devices.')
        if ($script:allCameras.Count -gt 0) {
            $summary.Add('Other present camera devices:')
            foreach ($camera in $script:allCameras) {
                $summary.Add("- $($camera.FriendlyName) | Status=$($camera.Status) | Class=$($camera.Class)")
            }
        }
    }
    else {
        $summary.Add("RESULT: Found $($script:delanCams.Count) DelanCam1 matching device(s).")
        foreach ($device in $script:delanCams) {
            $summary.Add('')
            $summary.Add("Device: $($device.FriendlyName)")
            $summary.Add("Status: $($device.Status)")
            $summary.Add("Class: $($device.Class)")
            $summary.Add("InstanceId: $($device.InstanceId)")

            $entity = @($script:pnpEntities | Where-Object { $_.PNPDeviceID -eq $device.InstanceId } | Select-Object -First 1)
            if ($entity.Count -gt 0) {
                $summary.Add("ConfigManagerErrorCode: $($entity[0].ConfigManagerErrorCode)")
                $summary.Add("Service: $($entity[0].Service)")
                if ([int]$entity[0].ConfigManagerErrorCode -ne 0) {
                    $summary.Add('REVIEW: Windows reports a non-zero Device Manager error code.')
                }
            }

            $driver = @($script:signedDrivers | Where-Object { $_.DeviceID -eq $device.InstanceId } | Select-Object -First 1)
            if ($driver.Count -gt 0) {
                $summary.Add("DriverProvider: $($driver[0].DriverProviderName)")
                $summary.Add("DriverVersion: $($driver[0].DriverVersion)")
                $summary.Add("DriverDate: $($driver[0].DriverDate)")
                $summary.Add("INF: $($driver[0].InfName)")
                $summary.Add("Signed: $($driver[0].IsSigned)")
                if ($driver[0].DriverProviderName -and $driver[0].DriverProviderName -notmatch '(?i)^Microsoft') {
                    $summary.Add('REVIEW: Driver provider is not Microsoft. DelanCam1 normally uses the native Windows camera driver.')
                }
            }
            else {
                $summary.Add('REVIEW: No signed-driver record was matched to this device.')
            }

            if ($device.Status -ne 'OK') {
                $summary.Add('REVIEW: PnP status is not OK.')
            }
        }
    }

    $summary.Add('')
    $summary.Add('This tool does not test the camera image stream. A camera can be detected correctly while still producing a corrupted image.')
    $summary | Set-Content -LiteralPath (Join-Path $work 'SUMMARY.txt') -Encoding UTF8
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
