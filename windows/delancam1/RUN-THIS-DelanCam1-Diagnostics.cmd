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
echo Close other apps that may use the camera first, such as Windows Camera,
echo OBS, Teams, Discord or OpenTrack, so the stream test can open DelanCam1
echo without another app already holding it.
echo.
echo This tool collects Windows camera, driver, USB, privacy,
echo security-product and running-application information. It also briefly
echo opens DelanCam1 to test its video stream, but does NOT save any image
echo or video data from the camera.
echo It does NOT change drivers, install software, upload anything, or make
echo network connections.
echo.
echo The report ZIP will be created on your Desktop with a name starting:
echo SEND-TO-DELANCLIP-DelanCam1-Report-
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
    echo The SEND-TO-DELANCLIP report ZIP has been saved to your Desktop.
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
$zipPath = Join-Path $desktop ("SEND-TO-DELANCLIP-DelanCam1-Report-" + $stamp + ".zip")

New-Item -ItemType Directory -Force -Path $work | Out-Null
$errorsFile = Join-Path $work 'errors.txt'
"No collection errors recorded." | Set-Content -LiteralPath $errorsFile -Encoding UTF8

function Record-Error {
    param([string]$Step, [object]$Err)
    $existing = Get-Content -LiteralPath $errorsFile -ErrorAction SilentlyContinue
    if ($existing.Count -eq 1 -and $existing[0] -eq 'No collection errors recorded.') {
        Clear-Content -LiteralPath $errorsFile
    }
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Step : $($Err.Exception.Message)"
    Add-Content -LiteralPath $errorsFile -Value $line -Encoding UTF8
}

function Run-Step {
    param([string]$Name, [scriptblock]$Action)
    try { & $Action }
    catch { Record-Error -Step $Name -Err $_ }
}

function Get-DevicePropertyData {
    param([string]$InstanceId, [string]$KeyName)
    try {
        return (Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName $KeyName -ErrorAction Stop).Data
    }
    catch { return $null }
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

function Redact-CameraRegistryPath {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }
    $redacted = $Text
    $redacted = $redacted -replace '(?i)C:#Users#[^#]+#', '%USERPROFILE%#'
    $redacted = $redacted -replace [regex]::Escape($env:USERNAME), '%USERNAME%'
    return $redacted
}

function Convert-FileTimeSafe {
    param([object]$Value)
    try {
        $n = [int64]$Value
        if ($n -le 0) { return '' }
        return [DateTime]::FromFileTimeUtc($n).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss zzz')
    }
    catch { return '' }
}

Run-Step 'README' {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    @"
Delanclip DelanCam1 Diagnostics
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
Administrator: $isAdmin

Purpose:
Collect Windows evidence that can explain DelanCam1 detection, driver, USB, privacy, security-software and application conflicts.

Collected:
- Windows version/build and computer model
- present camera devices and their hardware IDs
- DelanCam1 PnP properties, driver, Device Manager status and USB path
- present devices that Windows reports with an error code
- registered antivirus/security products and selected Microsoft Defender status
- Windows camera privacy consent and camera-access policy values
- names and process IDs of running applications
- a filtered list of processes that may use cameras, tracking or virtual-camera functions
- camera-related Windows services
- recent Windows camera-access registry history with user profile names redacted
- recent camera-related Windows event logs and matching application errors
- recent matching PnP events and SetupAPI excerpts
- a short native stream test: opens DelanCam1 with Windows camera APIs,
  requests the 640x480 @ 60 FPS format head tracking uses when available,
  measures whether frames arrive, how fast, and whether the stream stalls,
  and checksums frames in memory (plus basic brightness statistics) to tell
  a frozen stream from a genuinely dark scene, without saving any frame
  image or video data
- active power scheme and USB power-policy output when available
- a short diagnostic summary

Not collected:
- camera images or video
- command lines of running processes
- browser history
- passwords
- emails
- personal documents, photos or their contents
- Microsoft Defender threat history or antivirus scan contents

The tool does not change drivers, stop applications, alter privacy settings, install software or make network connections.
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

    $rows = foreach ($device in $script:allCameras) {
        $hardwareIds = Get-DevicePropertyData -InstanceId $device.InstanceId -KeyName 'DEVPKEY_Device_HardwareIds'
        $busDesc = Get-DevicePropertyData -InstanceId $device.InstanceId -KeyName 'DEVPKEY_Device_BusReportedDeviceDesc'
        [PSCustomObject]@{
            Status = $device.Status
            Class = $device.Class
            FriendlyName = $device.FriendlyName
            BusReportedDeviceDesc = $busDesc
            HardwareIds = ($hardwareIds -join '; ')
            InstanceId = $device.InstanceId
        }
    }

    if (@($rows).Count -eq 0) {
        'No present Camera or Image class devices were found.' | Set-Content -LiteralPath (Join-Path $work 'camera-devices.txt') -Encoding UTF8
    }
    else {
        $rows | Format-List | Out-String -Width 500 | Set-Content -LiteralPath (Join-Path $work 'camera-devices.txt') -Encoding UTF8
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

$script:streamTestPerformed = $false
$script:streamTestOpened = $false
$script:streamTestFramesReceived = 0
$script:streamTestAcquisitions = 0
$script:streamTestMeasuredFps = 0
$script:streamTestZeroLengthFrames = 0
$script:streamTestTimestampErrors = 0
$script:streamTestStreamStalls = 0
$script:streamTestGapPattern = 'steady'
$script:streamTestHashedFrames = 0
$script:streamTestDistinctFrames = 0
$script:streamTestIdenticalPairs = 0
$script:streamTestSampleMax = 0
$script:streamTestPixelFormat = ''
$script:streamTestApiError = $null
Run-Step 'DelanCam1 stream test' {
    $path = Join-Path $work 'stream-test.txt'
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('Delanclip DelanCam1 Stream Test')
    $lines.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')")
    $lines.Add('')
    $lines.Add('This test opens DelanCam1 with built-in Windows camera APIs and reads live')
    $lines.Add('frames for a few seconds. It records only counts, sizes and timestamps.')
    $lines.Add('No frame image or video data is written to disk at any point.')
    $lines.Add('')

    $script:streamTestPerformed = $true
    $vidPidPattern = '(?i)VID_0120.*PID_1234'
    $captureSeconds = 5

    function Wait-WinRtOperation {
        param($WinRtTask, [type]$ResultType, [int]$TimeoutMs = 5000)
        $methods = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
            $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
        }
        if (-not $methods) { throw 'Could not locate WindowsRuntimeSystemExtensions.AsTask(IAsyncOperation<T>) on this system.' }
        $asTaskGeneric = $methods[0].MakeGenericMethod($ResultType)
        $netTask = $asTaskGeneric.Invoke($null, @($WinRtTask))
        if (-not $netTask.Wait($TimeoutMs)) { throw "Timed out after ${TimeoutMs}ms waiting for a Windows Runtime operation." }
        return $netTask.Result
    }

    function Wait-WinRtAction {
        param($WinRtAction, [int]$TimeoutMs = 5000)
        $methods = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
            $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction'
        }
        if (-not $methods) { throw 'Could not locate WindowsRuntimeSystemExtensions.AsTask(IAsyncAction) on this system.' }
        $netTask = $methods[0].Invoke($null, @($WinRtAction))
        if (-not $netTask.Wait($TimeoutMs)) { throw "Timed out after ${TimeoutMs}ms waiting for a Windows Runtime operation." }
    }

    $frameReader = $null
    $mediaCapture = $null

    try {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction Stop

        [Windows.Devices.Enumeration.DeviceInformation,Windows.Devices.Enumeration,ContentType=WindowsRuntime] | Out-Null
        [Windows.Devices.Enumeration.DeviceClass,Windows.Devices.Enumeration,ContentType=WindowsRuntime] | Out-Null
        [Windows.Devices.Enumeration.DeviceInformationCollection,Windows.Devices.Enumeration,ContentType=WindowsRuntime] | Out-Null
        [Windows.Media.Capture.Frames.MediaFrameSourceGroup,Windows.Media.Capture.Frames,ContentType=WindowsRuntime] | Out-Null
        [Windows.Media.Capture.Frames.MediaFrameSourceKind,Windows.Media.Capture.Frames,ContentType=WindowsRuntime] | Out-Null
        [Windows.Media.Capture.Frames.MediaFrameReader,Windows.Media.Capture.Frames,ContentType=WindowsRuntime] | Out-Null
        [Windows.Media.Capture.Frames.MediaFrameReaderStartStatus,Windows.Media.Capture.Frames,ContentType=WindowsRuntime] | Out-Null
        [Windows.Media.Capture.MediaCapture,Windows.Media.Capture,ContentType=WindowsRuntime] | Out-Null
        [Windows.Media.Capture.MediaCaptureInitializationSettings,Windows.Media.Capture,ContentType=WindowsRuntime] | Out-Null
        [Windows.Media.Capture.MediaCaptureSharingMode,Windows.Media.Capture,ContentType=WindowsRuntime] | Out-Null
        [Windows.Media.Capture.MediaCaptureMemoryPreference,Windows.Media.Capture,ContentType=WindowsRuntime] | Out-Null
        [Windows.Media.Capture.StreamingCaptureMode,Windows.Media.Capture,ContentType=WindowsRuntime] | Out-Null
        [Windows.Storage.Streams.Buffer,Windows.Storage.Streams,ContentType=WindowsRuntime] | Out-Null

        $devices = Wait-WinRtOperation ([Windows.Devices.Enumeration.DeviceInformation]::FindAllAsync([Windows.Devices.Enumeration.DeviceClass]::VideoCapture)) ([Windows.Devices.Enumeration.DeviceInformationCollection]) 5000

        $targetDevice = $devices | Where-Object { $_.Id -match $vidPidPattern } | Select-Object -First 1
        $targetReason = 'matched known VID/PID (VID_0120&PID_1234)'
        if (-not $targetDevice) {
            $targetDevice = $devices | Where-Object { $_.Name -match '(?i)DelanCam' } | Select-Object -First 1
            $targetReason = 'matched by device name (VID/PID did not match the known-good value)'
        }

        if (-not $targetDevice) {
            $lines.Add('Device opened: NO')
            $lines.Add('Reason: No Windows Runtime video-capture device matched the known DelanCam1 VID/PID or name.')
            $lines.Add('API errors: none (device not present, stream test not attempted)')
            $lines | Set-Content -LiteralPath $path -Encoding UTF8
            return
        }

        $lines.Add("Target device: $($targetDevice.Name)")
        $lines.Add("Target device Id: $($targetDevice.Id)")
        $lines.Add("Target selection: $targetReason")
        $lines.Add('')

        $group = Wait-WinRtOperation ([Windows.Media.Capture.Frames.MediaFrameSourceGroup]::FromIdAsync($targetDevice.Id)) ([Windows.Media.Capture.Frames.MediaFrameSourceGroup]) 5000
        if (-not $group) { throw "No MediaFrameSourceGroup was found for device Id $($targetDevice.Id)." }

        $mediaCapture = New-Object Windows.Media.Capture.MediaCapture
        $settings = New-Object Windows.Media.Capture.MediaCaptureInitializationSettings
        $settings.SourceGroup = $group
        $settings.SharingMode = [Windows.Media.Capture.MediaCaptureSharingMode]::ExclusiveControl
        $settings.MemoryPreference = [Windows.Media.Capture.MediaCaptureMemoryPreference]::Cpu
        $settings.StreamingCaptureMode = [Windows.Media.Capture.StreamingCaptureMode]::Video
        Wait-WinRtAction ($mediaCapture.InitializeAsync($settings)) 8000

        $sourceInfos = @($group.SourceInfos)
        $lines.Add("Frame sources exposed by MediaFrameSourceGroup: $($sourceInfos.Count)")
        foreach ($info in $sourceInfos) {
            $lines.Add("  - SourceKind: $($info.SourceKind), Id: $($info.Id)")
        }

        $chosenInfo = $sourceInfos | Where-Object { $_.SourceKind -eq [Windows.Media.Capture.Frames.MediaFrameSourceKind]::Color } | Select-Object -First 1
        $frameSourceSelection = 'Color'
        if (-not $chosenInfo -and $sourceInfos.Count -gt 0) {
            $chosenInfo = $sourceInfos[0]
            $frameSourceSelection = "fallback: $($chosenInfo.SourceKind) (no Color-kind source was exposed)"
        }
        if (-not $chosenInfo) { throw 'MediaFrameSourceGroup exposed no source infos for this device.' }

        $framePairs = @($mediaCapture.FrameSources)
        $frameSource = $null
        foreach ($pair in $framePairs) {
            if ([string]$pair.Key -eq [string]$chosenInfo.Id) { $frameSource = $pair.Value; break }
        }
        if (-not $frameSource -and $framePairs.Count -gt 0) { $frameSource = $framePairs[0].Value }
        if (-not $frameSource) { throw "MediaCapture did not expose a usable frame source (entries: $($framePairs.Count))." }
        $lines.Add("Selected frame source: $frameSourceSelection")
        $lines.Add('')

        $lines.Add('Available media types (native formats reported by the device):')
        foreach ($fmt in $frameSource.SupportedFormats) {
            $vfmt = $fmt.VideoFormat
            $fr = $fmt.FrameRate
            $fps = 0
            if ($fr -and $fr.Denominator -ne 0) { $fps = [math]::Round($fr.Numerator / $fr.Denominator, 2) }
            $lines.Add("  - $($fmt.Subtype) $($vfmt.Width)x$($vfmt.Height) @ ${fps}fps")
        }
        $lines.Add('')

        $requestedFormat = $null
        foreach ($subtypePref in @('MJPG','NV12','YUY2')) {
            foreach ($fmt in $frameSource.SupportedFormats) {
                $vf = $fmt.VideoFormat
                $fr = $fmt.FrameRate
                $fmtFps = 0
                if ($fr -and $fr.Denominator -ne 0) { $fmtFps = $fr.Numerator / $fr.Denominator }
                if ($vf.Width -eq 640 -and $vf.Height -eq 480 -and [math]::Round($fmtFps) -eq 60 -and $fmt.Subtype -eq $subtypePref) {
                    $requestedFormat = $fmt
                    break
                }
            }
            if ($requestedFormat) { break }
        }
        if ($requestedFormat) {
            try {
                Wait-WinRtAction ($frameSource.SetFormatAsync($requestedFormat)) 5000
                $lines.Add("Requested format: $($requestedFormat.Subtype) 640x480 @ 60fps (the settings OpenTrack uses) - set successfully")
            }
            catch {
                $lines.Add("Requested format: $($requestedFormat.Subtype) 640x480 @ 60fps could not be set ($($_.Exception.Message)); continuing with the device default format")
            }
        }
        else {
            $lines.Add('Requested format: 640x480 @ 60fps is not in the supported format list; continuing with the device default format')
        }
        $lines.Add('')

        $current = $frameSource.CurrentFormat
        $curVideo = $current.VideoFormat
        $curFr = $current.FrameRate
        $curFps = 0
        if ($curFr -and $curFr.Denominator -ne 0) { $curFps = [math]::Round($curFr.Numerator / $curFr.Denominator, 2) }
        $expectedIntervalMs = 33.3
        if ($curFps -gt 0) { $expectedIntervalMs = 1000.0 / $curFps }

        $stats = @{
            FramesArrived = 0
            Acquisitions = 0
            ZeroLengthFrames = 0
            TimestampErrors = 0
            MissingTimestamps = 0
            StreamStalls = 0
            HandlerErrors = 0
            LastHandlerError = ''
            FirstTimestampMs = -1.0
            LastTimestampMs = -1.0
            MaxGapMs = 0.0
            GapsMs = (New-Object System.Collections.Generic.List[double])
            HashedFrames = 0
            IdenticalFramePairs = 0
            LastFrameHash = ''
            UniqueHashes = (New-Object 'System.Collections.Generic.HashSet[string]')
            ContentAnalysisErrors = 0
            LastContentError = ''
            SampledFrames = 0
            SampleByteMin = 255
            SampleByteMax = 0
            SampleByteMeanSum = 0.0
            UvMeanSum = 0.0
            UvSamples = 0
            PixelFormatName = ''
            MinFrameBytes = -1
            MaxFrameBytes = 0
            ExpectedIntervalMs = $expectedIntervalMs
        }

        $frameReader = Wait-WinRtOperation ($mediaCapture.CreateFrameReaderAsync($frameSource)) ([Windows.Media.Capture.Frames.MediaFrameReader]) 8000

        $startStatus = Wait-WinRtOperation ($frameReader.StartAsync()) ([Windows.Media.Capture.Frames.MediaFrameReaderStartStatus]) 8000
        if ($startStatus.ToString() -ne 'Success') {
            throw "MediaFrameReader.StartAsync did not report success (status: $startStatus)."
        }

        $md5 = [System.Security.Cryptography.MD5]::Create()
        $contentBuffer = $null
        $contentBufferSize = 0

        # Windows PowerShell cannot subscribe to Windows Runtime events, so the
        # FrameArrived event is unusable here. Poll TryAcquireLatestFrame in a
        # tight loop instead and treat a changed SystemRelativeTime as a new frame.
        $deadline = [DateTime]::UtcNow.AddSeconds($captureSeconds)
        while ([DateTime]::UtcNow -lt $deadline) {
            $frame = $null
            try {
                $frame = $frameReader.TryAcquireLatestFrame()
                if ($null -ne $frame) {
                    $stats.Acquisitions++
                    $tsRaw = $frame.SystemRelativeTime
                    $tsMs = $null
                    if ($tsRaw -is [TimeSpan]) { $tsMs = $tsRaw.TotalMilliseconds }
                    elseif ($null -ne $tsRaw) {
                        try { $tsMs = ([TimeSpan]$tsRaw.Value).TotalMilliseconds }
                        catch { try { $tsMs = ([TimeSpan]$tsRaw).TotalMilliseconds } catch {} }
                    }
                    if ($null -ne $tsMs) {
                        if ($tsMs -ne $stats.LastTimestampMs) {
                            $stats.FramesArrived++
                            if ($stats.LastTimestampMs -ge 0) {
                                $delta = $tsMs - $stats.LastTimestampMs
                                if ($delta -le 0) { $stats.TimestampErrors++ }
                                elseif ($stats.ExpectedIntervalMs -gt 0 -and $delta -gt ($stats.ExpectedIntervalMs * 4)) { $stats.StreamStalls++ }
                                if ($delta -gt $stats.MaxGapMs) { $stats.MaxGapMs = $delta }
                                if ($delta -gt 0) { $stats.GapsMs.Add($delta) }
                            }
                            if ($stats.FirstTimestampMs -lt 0) { $stats.FirstTimestampMs = $tsMs }
                            $stats.LastTimestampMs = $tsMs

                            $width = 0
                            $height = 0
                            $bytesPerPixel = 0
                            $vmf = $frame.VideoMediaFrame
                            if ($vmf -and $vmf.SoftwareBitmap) {
                                $sb = $vmf.SoftwareBitmap
                                $width = $sb.PixelWidth
                                $height = $sb.PixelHeight
                                switch ($sb.BitmapPixelFormat.ToString()) {
                                    'Yuy2'   { $bytesPerPixel = 2 }
                                    'Nv12'   { $bytesPerPixel = 1.5 }
                                    'Bgra8'  { $bytesPerPixel = 4 }
                                    'Rgba8'  { $bytesPerPixel = 4 }
                                    'Rgba16' { $bytesPerPixel = 8 }
                                    'Gray8'  { $bytesPerPixel = 1 }
                                    'Gray16' { $bytesPerPixel = 2 }
                                    default  { $bytesPerPixel = 0 }
                                }
                            }
                            if ($width -le 0 -or $height -le 0) { $stats.ZeroLengthFrames++ }
                            $sizeBytes = [long]($width * $height * $bytesPerPixel)
                            if ($stats.MinFrameBytes -eq -1 -or $sizeBytes -lt $stats.MinFrameBytes) { $stats.MinFrameBytes = $sizeBytes }
                            if ($sizeBytes -gt $stats.MaxFrameBytes) { $stats.MaxFrameBytes = $sizeBytes }

                            if ($vmf -and $vmf.SoftwareBitmap -and $width -gt 0 -and $height -gt 0) {
                                try {
                                    $needed = [uint32]($width * $height * 4 + 4096)
                                    if ($null -eq $contentBuffer -or $contentBufferSize -lt $needed) {
                                        $contentBuffer = New-Object Windows.Storage.Streams.Buffer $needed
                                        $contentBufferSize = $needed
                                    }
                                    $sb.CopyToBuffer($contentBuffer)
                                    $frameBytes = [System.Runtime.InteropServices.WindowsRuntime.WindowsRuntimeBufferExtensions]::ToArray($contentBuffer)
                                    if ($frameBytes.Length -ge ($width * $height)) {
                                        $frameHash = [BitConverter]::ToString($md5.ComputeHash($frameBytes))
                                        $stats.HashedFrames++
                                        if ($stats.LastFrameHash -eq $frameHash) { $stats.IdenticalFramePairs++ }
                                        $stats.LastFrameHash = $frameHash
                                        [void]$stats.UniqueHashes.Add($frameHash)

                                        if ($stats.HashedFrames -eq 1 -or ($stats.HashedFrames % 25) -eq 0) {
                                            $stats.PixelFormatName = $sb.BitmapPixelFormat.ToString()
                                            $sampleLen = [Math]::Min(32768, $frameBytes.Length)
                                            $byteSample = [int[]]($frameBytes[0..($sampleLen - 1)])
                                            $sMin = [System.Linq.Enumerable]::Min($byteSample)
                                            $sMax = [System.Linq.Enumerable]::Max($byteSample)
                                            if ($sMin -lt $stats.SampleByteMin) { $stats.SampleByteMin = $sMin }
                                            if ($sMax -gt $stats.SampleByteMax) { $stats.SampleByteMax = $sMax }
                                            $stats.SampleByteMeanSum += [System.Linq.Enumerable]::Average($byteSample)
                                            $stats.SampledFrames++
                                            if ($stats.PixelFormatName -eq 'Nv12') {
                                                $uvStart = $width * $height
                                                if ($frameBytes.Length -ge ($uvStart + 1024)) {
                                                    $uvLen = [Math]::Min(32768, $frameBytes.Length - $uvStart)
                                                    $uvSample = [int[]]($frameBytes[$uvStart..($uvStart + $uvLen - 1)])
                                                    $stats.UvMeanSum += [System.Linq.Enumerable]::Average($uvSample)
                                                    $stats.UvSamples++
                                                }
                                            }
                                        }
                                    }
                                    else {
                                        $stats.ContentAnalysisErrors++
                                        $stats.LastContentError = "CopyToBuffer returned only $($frameBytes.Length) bytes for a ${width}x${height} frame."
                                    }
                                }
                                catch {
                                    $stats.ContentAnalysisErrors++
                                    $stats.LastContentError = $_.Exception.Message
                                }
                            }
                        }
                    }
                    else {
                        $stats.MissingTimestamps++
                    }
                }
            }
            catch {
                $stats.HandlerErrors++
                $stats.LastHandlerError = $_.Exception.Message
            }
            finally {
                if ($null -ne $frame) { try { $frame.Dispose() } catch {} }
            }
            Start-Sleep -Milliseconds 2
        }

        try { Wait-WinRtAction ($frameReader.StopAsync()) 5000 } catch {}

        $measuredFps = 0
        if ($stats.FramesArrived -ge 2 -and $stats.LastTimestampMs -gt $stats.FirstTimestampMs) {
            $elapsedSeconds = ($stats.LastTimestampMs - $stats.FirstTimestampMs) / 1000.0
            if ($elapsedSeconds -gt 0) { $measuredFps = [math]::Round(($stats.FramesArrived - 1) / $elapsedSeconds, 2) }
        }

        $medianGapMs = 0
        if ($stats.GapsMs.Count -gt 0) {
            $sortedGaps = @($stats.GapsMs | Sort-Object)
            $medianGapMs = [math]::Round([double]$sortedGaps[[int][math]::Floor($sortedGaps.Count / 2)], 1)
        }
        $gapPattern = 'steady'
        if ($stats.StreamStalls -gt 0) {
            if ($medianGapMs -gt 0 -and $stats.MaxGapMs -le (1.6 * $medianGapMs)) { $gapPattern = 'uniform-slow' }
            else { $gapPattern = 'irregular' }
        }

        $script:streamTestOpened = $true
        $script:streamTestFramesReceived = $stats.FramesArrived
        $script:streamTestAcquisitions = $stats.Acquisitions
        $script:streamTestMeasuredFps = $measuredFps
        $script:streamTestZeroLengthFrames = $stats.ZeroLengthFrames
        $script:streamTestTimestampErrors = $stats.TimestampErrors
        $script:streamTestStreamStalls = $stats.StreamStalls
        $script:streamTestGapPattern = $gapPattern
        $script:streamTestHashedFrames = $stats.HashedFrames
        $script:streamTestDistinctFrames = $stats.UniqueHashes.Count
        $script:streamTestIdenticalPairs = $stats.IdenticalFramePairs
        $script:streamTestSampleMax = $stats.SampleByteMax
        $script:streamTestPixelFormat = $stats.PixelFormatName

        $lines.Add('Device opened: YES')
        $lines.Add("Selected format: $($current.Subtype) (the camera's current format for this test)")
        $lines.Add("Resolution: $($curVideo.Width)x$($curVideo.Height)")
        $lines.Add("Reported FPS: $curFps")
        $lines.Add("Capture window: ${captureSeconds}s")
        $lines.Add("Frames received: $($stats.FramesArrived)")
        $lines.Add("Frame acquisitions (including repeats of the same frame): $($stats.Acquisitions)")
        $lines.Add("Measured FPS: $measuredFps")
        $lines.Add("Zero-length frames: $($stats.ZeroLengthFrames)")
        $lines.Add("Timestamp errors: $($stats.TimestampErrors)")
        $lines.Add("Frames without a usable timestamp: $($stats.MissingTimestamps)")
        $lines.Add("Stream stalls (gap > 4x expected frame interval): $($stats.StreamStalls)")
        $lines.Add("Largest frame-to-frame gap: $([math]::Round($stats.MaxGapMs, 1)) ms")
        $lines.Add("Median frame-to-frame gap: $medianGapMs ms")
        if ($gapPattern -eq 'uniform-slow') {
            $lines.Add('Note: frame spacing is uniform rather than bursty. A uniformly slow frame rate is typical of')
            $lines.Add('auto-exposure lengthening exposure time when the scene appears dark to the camera, and is not')
            $lines.Add('by itself evidence of a USB or hardware fault.')
        }
        if ($stats.MinFrameBytes -ge 0) {
            $lines.Add("Frame size range (approximate, from pixel format): $($stats.MinFrameBytes) - $($stats.MaxFrameBytes) bytes")
        }
        if ($stats.HashedFrames -gt 0) {
            $lines.Add("Frames checksummed in memory: $($stats.HashedFrames)")
            $lines.Add("Distinct frame contents: $($stats.UniqueHashes.Count)")
            $lines.Add("Consecutive byte-identical frames: $($stats.IdenticalFramePairs)")
            if ($stats.SampledFrames -gt 0) {
                $sampleMean = [math]::Round($stats.SampleByteMeanSum / $stats.SampledFrames, 1)
                $lines.Add("Frame-start byte sample ($($stats.PixelFormatName)): min $($stats.SampleByteMin), max $($stats.SampleByteMax), mean $sampleMean across $($stats.SampledFrames) sampled frame(s)")
                if ($stats.UvSamples -gt 0) {
                    $uvMean = [math]::Round($stats.UvMeanSum / $stats.UvSamples, 1)
                    $lines.Add("Chroma-plane sample mean: $uvMean (neutral grey chroma is 128)")
                }
            }
        }
        elseif ($stats.FramesArrived -gt 0) {
            $lines.Add('Frame content could not be checksummed for any frame.')
        }
        if ($stats.ContentAnalysisErrors -gt 0) {
            $lines.Add("Content-analysis errors: $($stats.ContentAnalysisErrors) (last: $($stats.LastContentError))")
        }
        if ($stats.HandlerErrors -gt 0) {
            $lines.Add("Frame-handling errors: $($stats.HandlerErrors) (last: $($stats.LastHandlerError))")
        }
        if ($stats.FramesArrived -eq 0 -and $stats.Acquisitions -gt 0) {
            $lines.Add('API errors: none (frames were acquired, but none carried a usable timestamp, so rate metrics could not be measured)')
        }
        elseif ($stats.FramesArrived -eq 0) {
            $lines.Add('API errors: none (device opened and stream started, but no frames arrived in the capture window)')
        }
        else {
            $lines.Add('API errors: none')
        }
        $lines.Add('')
        $lines.Add('Frame-content analysis is limited to detecting frozen/identical frames via in-memory checksums.')
        $lines.Add('A clean result above shows the capture API delivered changing frames at the expected rate; it does')
        $lines.Add('not prove the picture itself looks correct.')
    }
    catch {
        $realEx = $_.Exception
        while ($realEx.InnerException) { $realEx = $realEx.InnerException }
        $hresultText = ''
        try { $hresultText = ' (HRESULT: 0x{0:X8})' -f $realEx.HResult } catch {}
        $script:streamTestOpened = $false
        $script:streamTestApiError = $realEx.Message
        $lines.Add('Device opened: NO')
        $lines.Add("API errors: $($realEx.Message)$hresultText")
        Record-Error -Step 'DelanCam1 stream test' -Err $_
    }
    finally {
        if ($frameReader) { try { $frameReader.Dispose() } catch {} }
        if ($mediaCapture) { try { $mediaCapture.Dispose() } catch {} }
    }

    $lines | Set-Content -LiteralPath $path -Encoding UTF8
}

$script:problemDevices = @()
Run-Step 'Problem devices' {
    $path = Join-Path $work 'problem-devices.txt'
    $script:problemDevices = @(Get-CimInstance Win32_PnPEntity | Where-Object {
        $_.ConfigManagerErrorCode -ne 0
    })
    if ($script:problemDevices.Count -eq 0) {
        'Windows reports no present PnP devices with a non-zero ConfigManagerErrorCode.' | Set-Content -LiteralPath $path -Encoding UTF8
    }
    else {
        $script:problemDevices |
            Select-Object Name, Status, PNPClass, Manufacturer, ConfigManagerErrorCode, PNPDeviceID |
            Format-List |
            Out-String -Width 500 |
            Set-Content -LiteralPath $path -Encoding UTF8
    }
}

$script:securityProducts = @()
Run-Step 'Registered antivirus products' {
    $path = Join-Path $work 'security-products.txt'
    try {
        $script:securityProducts = @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop)
    }
    catch {
        $script:securityProducts = @()
        Record-Error -Step 'SecurityCenter2 antivirus products' -Err $_
    }

    if ($script:securityProducts.Count -eq 0) {
        'No antivirus product records were returned by Windows Security Center.' | Set-Content -LiteralPath $path -Encoding UTF8
    }
    else {
        $script:securityProducts |
            Select-Object displayName, productState |
            Format-Table -AutoSize |
            Out-String -Width 300 |
            Set-Content -LiteralPath $path -Encoding UTF8
    }
}

$script:defender = $null
Run-Step 'Microsoft Defender status' {
    $path = Join-Path $work 'defender-status.txt'
    if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
        $script:defender = Get-MpComputerStatus
        $script:defender |
            Select-Object AMServiceEnabled, AntivirusEnabled, AntispywareEnabled, BehaviorMonitorEnabled, IoavProtectionEnabled, IsTamperProtected, NISEnabled, OnAccessProtectionEnabled, RealTimeProtectionEnabled, AntivirusSignatureLastUpdated, AntivirusSignatureVersion |
            Format-List |
            Out-String -Width 300 |
            Set-Content -LiteralPath $path -Encoding UTF8
    }
    else {
        'Get-MpComputerStatus is not available on this Windows installation.' | Set-Content -LiteralPath $path -Encoding UTF8
    }
}

$script:cameraPolicy = $null
Run-Step 'Camera access policy' {
    $path = Join-Path $work 'camera-policy.txt'
    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'
    if (Test-Path -LiteralPath $policyPath) {
        $p = Get-ItemProperty -LiteralPath $policyPath
        $script:cameraPolicy = $p
        [PSCustomObject]@{
            LetAppsAccessCamera = $p.LetAppsAccessCamera
            LetAppsAccessCamera_ForceAllowTheseApps = $p.LetAppsAccessCamera_ForceAllowTheseApps
            LetAppsAccessCamera_ForceDenyTheseApps = $p.LetAppsAccessCamera_ForceDenyTheseApps
            LetAppsAccessCamera_UserInControlOfTheseApps = $p.LetAppsAccessCamera_UserInControlOfTheseApps
        } | Format-List | Out-String -Width 500 | Set-Content -LiteralPath $path -Encoding UTF8
    }
    else {
        'No Windows AppPrivacy camera policy key is present.' | Set-Content -LiteralPath $path -Encoding UTF8
    }
}

$script:cameraConsentRoots = @()
$script:possibleActiveCameraRecords = @()
Run-Step 'Camera privacy and access history' {
    $privacyPath = Join-Path $work 'camera-privacy.txt'
    $historyPath = Join-Path $work 'camera-access-history.txt'
    $roots = @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam'
    )

    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) {
            Add-Content -LiteralPath $privacyPath -Value "$root : not present" -Encoding UTF8
            continue
        }

        $rootItem = Get-ItemProperty -LiteralPath $root
        $entry = [PSCustomObject]@{ Path = $root; Value = $rootItem.Value }
        $script:cameraConsentRoots += $entry
        Add-Content -LiteralPath $privacyPath -Value "Path: $root" -Encoding UTF8
        Add-Content -LiteralPath $privacyPath -Value "Value: $($rootItem.Value)" -Encoding UTF8
        Add-Content -LiteralPath $privacyPath -Value '' -Encoding UTF8

        Get-ChildItem -LiteralPath $root -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            $props = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
            if ($null -eq $props) { return }
            $startValue = $props.LastUsedTimeStart
            $stopValue = $props.LastUsedTimeStop
            if ($null -eq $props.Value -and $null -eq $startValue -and $null -eq $stopValue) { return }

            $displayPath = Redact-CameraRegistryPath -Text $_.Name
            $startText = Convert-FileTimeSafe -Value $startValue
            $stopText = Convert-FileTimeSafe -Value $stopValue
            Add-Content -LiteralPath $historyPath -Value "Path: $displayPath" -Encoding UTF8
            if ($null -ne $props.Value) { Add-Content -LiteralPath $historyPath -Value "Value: $($props.Value)" -Encoding UTF8 }
            if ($null -ne $startValue) { Add-Content -LiteralPath $historyPath -Value "LastUsedTimeStart: $startValue | $startText" -Encoding UTF8 }
            if ($null -ne $stopValue) { Add-Content -LiteralPath $historyPath -Value "LastUsedTimeStop: $stopValue | $stopText" -Encoding UTF8 }
            Add-Content -LiteralPath $historyPath -Value '' -Encoding UTF8

            try {
                $startNum = [int64]$startValue
                $stopNum = [int64]$stopValue
                if ($startNum -gt 0 -and ($stopNum -eq 0 -or $stopNum -lt $startNum)) {
                    $script:possibleActiveCameraRecords += $displayPath
                }
            }
            catch {}
        }
    }

    if (-not (Test-Path -LiteralPath $historyPath)) {
        'No per-application camera access-history records were found.' | Set-Content -LiteralPath $historyPath -Encoding UTF8
    }
}

$script:allProcesses = @()
$script:potentialCameraProcesses = @()
Run-Step 'Running processes' {
    $allPath = Join-Path $work 'running-processes.txt'
    $filteredPath = Join-Path $work 'potential-camera-apps.txt'
    $script:allProcesses = @(Get-Process | Sort-Object ProcessName, Id | ForEach-Object {
        [PSCustomObject]@{ ProcessName = $_.ProcessName; Id = $_.Id }
    })
    $script:allProcesses |
        Format-Table -AutoSize |
        Out-String -Width 300 |
        Set-Content -LiteralPath $allPath -Encoding UTF8

    $pattern = '(?i)(opentrack|facetrack|aitrack|tobii|obs|camera|webcam|capture|zoom|teams|skype|discord|manycam|logi|logitech|razer|broadcast|nvidia|snapcamera|vcam|virtualcam|droidcam|ivcam|camo|xsplit|streamlabs|webex|slack)'
    $script:potentialCameraProcesses = @($script:allProcesses | Where-Object { $_.ProcessName -match $pattern })
    if ($script:potentialCameraProcesses.Count -eq 0) {
        'No running process names matched the camera/tracking/virtual-camera review list.' | Set-Content -LiteralPath $filteredPath -Encoding UTF8
    }
    else {
        $script:potentialCameraProcesses |
            Format-Table -AutoSize |
            Out-String -Width 300 |
            Set-Content -LiteralPath $filteredPath -Encoding UTF8
    }
}

Run-Step 'Camera-related services' {
    $path = Join-Path $work 'camera-services.txt'
    $services = @(Get-CimInstance Win32_Service | Where-Object {
        $_.Name -match '(?i)(camera|frameserver|webcam|capture)' -or
        $_.DisplayName -match '(?i)(camera|frame server|webcam|capture)'
    })
    if ($services.Count -eq 0) {
        'No camera-related Windows services matched the review filter.' | Set-Content -LiteralPath $path -Encoding UTF8
    }
    else {
        $services |
            Select-Object Name, DisplayName, State, StartMode |
            Format-Table -AutoSize |
            Out-String -Width 400 |
            Set-Content -LiteralPath $path -Encoding UTF8
    }
}

$script:cameraEventCount = 0
Run-Step 'Camera event logs' {
    $path = Join-Path $work 'camera-event-logs.txt'
    $start = (Get-Date).AddDays(-7)
    $logs = @(Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | Where-Object {
        $_.LogName -match '(?i)(camera|frameserver)' -and $_.IsEnabled
    })

    if ($logs.Count -eq 0) {
        'No enabled Windows event logs with Camera or FrameServer in the log name were found.' | Set-Content -LiteralPath $path -Encoding UTF8
    }
    else {
        foreach ($log in $logs) {
            Add-Content -LiteralPath $path -Value "===== $($log.LogName) =====" -Encoding UTF8
            try {
                $events = @(Get-WinEvent -FilterHashtable @{LogName=$log.LogName; StartTime=$start} -ErrorAction Stop | Select-Object -First 100)
                $script:cameraEventCount += $events.Count
                if ($events.Count -eq 0) {
                    Add-Content -LiteralPath $path -Value 'No events in the previous 7 days.' -Encoding UTF8
                }
                else {
                    $events |
                        Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message |
                        Format-List |
                        Out-String -Width 500 |
                        Add-Content -LiteralPath $path -Encoding UTF8
                }
            }
            catch { Record-Error -Step ("Camera event log " + $log.LogName) -Err $_ }
            Add-Content -LiteralPath $path -Value '' -Encoding UTF8
        }
    }
}

$script:applicationCameraErrors = @()
Run-Step 'Application camera errors' {
    $path = Join-Path $work 'application-camera-errors.txt'
    $start = (Get-Date).AddDays(-7)
    $script:applicationCameraErrors = @(Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$start} -ErrorAction Stop |
        Where-Object {
            $_.LevelDisplayName -match '(?i)Error|Warning' -and
            ([string]$_.Message -match '(?i)(DelanCam|usbvideo|camera|opentrack|frameserver|webcam)')
        } | Select-Object -First 200)

    if ($script:applicationCameraErrors.Count -eq 0) {
        'No matching camera/OpenTrack application warnings or errors were found in the previous 7 days.' | Set-Content -LiteralPath $path -Encoding UTF8
    }
    else {
        $script:applicationCameraErrors |
            Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message |
            Format-List |
            Out-String -Width 500 |
            Set-Content -LiteralPath $path -Encoding UTF8
    }
}

Run-Step 'USB power policy' {
    $path = Join-Path $work 'power-usb.txt'
    $powercfg = Join-Path $env:windir 'System32\powercfg.exe'
    "===== Active power scheme =====" | Set-Content -LiteralPath $path -Encoding UTF8
    (& $powercfg /getactivescheme 2>&1) | Out-String -Width 500 | Add-Content -LiteralPath $path -Encoding UTF8
    "" | Add-Content -LiteralPath $path -Encoding UTF8
    "===== USB power settings =====" | Add-Content -LiteralPath $path -Encoding UTF8
    (& $powercfg /query SCHEME_CURRENT SUB_USB 2>&1) | Out-String -Width 500 | Add-Content -LiteralPath $path -Encoding UTF8
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

Run-Step 'Driver-store conflict hints' {
    $path = Join-Path $work 'driver-conflict-hints.txt'
    $allDrivers = @(Get-CimInstance Win32_PnPSignedDriver)
    $hints = @($allDrivers | Where-Object {
        $_.DriverProviderName -match '(?i)(libusb|zadig|winusb)' -or
        $_.DeviceName -match '(?i)(libusb|zadig|winusb|APP Mode)'
    })
    if ($hints.Count -eq 0) {
        'No present signed-driver records matched libusb, Zadig, WinUSB or APP Mode review terms.' | Set-Content -LiteralPath $path -Encoding UTF8
    }
    else {
        $hints |
            Select-Object DeviceName, DeviceClass, Manufacturer, DriverProviderName, DriverVersion, InfName, DeviceID |
            Format-List |
            Out-String -Width 500 |
            Set-Content -LiteralPath $path -Encoding UTF8
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
            $summary.Add('Other present camera devices are listed in camera-devices.txt with hardware IDs.')
        }
    }
    else {
        $summary.Add("RESULT: Found $($script:delanCams.Count) DelanCam1 matching device(s).")
        foreach ($device in $script:delanCams) {
            $summary.Add('')
            $summary.Add("Device: $($device.FriendlyName)")
            $summary.Add("Status: $($device.Status)")
            $summary.Add("InstanceId: $($device.InstanceId)")

            $entity = @($script:pnpEntities | Where-Object { $_.PNPDeviceID -eq $device.InstanceId } | Select-Object -First 1)
            if ($entity.Count -gt 0) {
                $summary.Add("ConfigManagerErrorCode: $($entity[0].ConfigManagerErrorCode)")
                $summary.Add("Service: $($entity[0].Service)")
                if ([int]$entity[0].ConfigManagerErrorCode -ne 0) {
                    $summary.Add('REVIEW: Windows reports a non-zero Device Manager error code for DelanCam1.')
                }
            }

            $driver = @($script:signedDrivers | Where-Object { $_.DeviceID -eq $device.InstanceId } | Select-Object -First 1)
            if ($driver.Count -gt 0) {
                $summary.Add("DriverProvider: $($driver[0].DriverProviderName)")
                $summary.Add("DriverVersion: $($driver[0].DriverVersion)")
                $summary.Add("INF: $($driver[0].InfName)")
                if ($driver[0].DriverProviderName -and $driver[0].DriverProviderName -notmatch '(?i)^Microsoft') {
                    $summary.Add('REVIEW: DelanCam1 is bound to a non-Microsoft driver provider.')
                }
                if ($driver[0].DriverProviderName -match '(?i)(libusb|zadig|winusb)' -or $driver[0].DeviceName -match '(?i)(libusb|zadig|winusb|APP Mode)') {
                    $summary.Add('REVIEW HIGH: Driver information contains a known third-party USB-driver conflict term.')
                }
            }
            else {
                $summary.Add('REVIEW: No signed-driver record was matched to DelanCam1.')
            }
        }
    }

    $summary.Add('')
    $summary.Add('STREAM TEST')
    if (-not $script:streamTestPerformed) {
        $summary.Add('Stream test was not attempted. See stream-test.txt.')
    }
    elseif (-not $script:streamTestOpened) {
        $summary.Add("REVIEW: DelanCam1 could not be opened for the stream test: $script:streamTestApiError")
        $summary.Add('This points to camera privacy/policy, another application holding the camera, or a driver problem, not necessarily a hardware fault. See stream-test.txt for the exact error.')
    }
    else {
        $summary.Add("Frames received: $script:streamTestFramesReceived in the capture window. Measured FPS: $script:streamTestMeasuredFps.")
        if ($script:streamTestFramesReceived -eq 0 -and $script:streamTestAcquisitions -gt 0) {
            $summary.Add('REVIEW: DelanCam1 delivered frames, but none carried a usable timestamp, so frame-rate metrics could not be measured. See stream-test.txt.')
        }
        elseif ($script:streamTestFramesReceived -eq 0) {
            $summary.Add('REVIEW HIGH: DelanCam1 opened but delivered zero frames. This points to USB, driver or hardware, not the application layer.')
        }
        elseif ($script:streamTestStreamStalls -gt 0 -and $script:streamTestGapPattern -eq 'uniform-slow') {
            $summary.Add('INFO: Frames arrived slower than the nominal FPS but with uniform spacing - consistent with auto-exposure in a scene that appears dark to this IR tracking camera, not with a transport fault. See stream-test.txt.')
        }
        elseif ($script:streamTestStreamStalls -gt 0) {
            $summary.Add("REVIEW: The stream stalled $script:streamTestStreamStalls time(s) during the test with irregular frame spacing. This points to USB, driver or hardware rather than the application layer.")
        }
        elseif ($script:streamTestZeroLengthFrames -gt 0) {
            $summary.Add("REVIEW: $script:streamTestZeroLengthFrames received frame(s) reported zero width or height.")
        }
        else {
            $summary.Add('The capture API delivered frames at a steady rate with no stalls. If the client still sees a corrupted image, this points above the raw camera stream, such as application, codec or rendering, rather than DelanCam1 itself.')
        }
        if ($script:streamTestHashedFrames -ge 5 -and $script:streamTestDistinctFrames -eq 1) {
            if ($script:streamTestPixelFormat -eq 'Nv12' -and $script:streamTestSampleMax -le 40) {
                $summary.Add('INFO: All captured frames were byte-identical and essentially black. An IR tracking camera looking at a scene with nothing bright in it can legitimately produce an unchanging black image, so this alone is not treated as a fault. Pointing any light or IR source at the camera and re-running gives a definitive frozen-vs-dark answer.')
            }
            else {
                $summary.Add('REVIEW HIGH: Every captured frame was byte-identical while containing non-black detail. The stream appears frozen even though frames keep arriving - this points to sensor, hardware or driver, not the application layer.')
            }
        }
        elseif ($script:streamTestIdenticalPairs -gt 0) {
            $summary.Add("REVIEW: $script:streamTestIdenticalPairs consecutive frame pair(s) had byte-identical content. A live sensor almost never produces identical frames - review together with the other stream metrics.")
        }
        $summary.Add('Content analysis flags frozen/identical frames but cannot judge whether a varying image looks correct. See stream-test.txt for full detail.')
    }

    $summary.Add('')
    $summary.Add('CAMERA ACCESS / PRIVACY')
    if ($script:cameraPolicy -and $script:cameraPolicy.LetAppsAccessCamera -eq 2) {
        $summary.Add('REVIEW HIGH: Windows policy is configured to force-deny camera access to apps.')
    }
    foreach ($root in $script:cameraConsentRoots) {
        if ([string]$root.Value -match '(?i)^Deny$') {
            $summary.Add("REVIEW HIGH: Camera consent value is Deny at $($root.Path)")
        }
    }
    if ($script:possibleActiveCameraRecords.Count -gt 0) {
        $summary.Add('REVIEW: Windows camera-access history contains records that may indicate camera use without a recorded stop.')
        foreach ($item in ($script:possibleActiveCameraRecords | Select-Object -Unique | Select-Object -First 10)) {
            $summary.Add("- $item")
        }
    }

    $summary.Add('')
    $summary.Add('SECURITY SOFTWARE')
    if ($script:securityProducts.Count -gt 0) {
        $summary.Add('Windows Security Center registered products: ' + (($script:securityProducts | ForEach-Object { $_.displayName }) -join ', '))
    }
    else {
        $summary.Add('Windows Security Center returned no registered antivirus product records.')
    }
    if ($script:defender) {
        $summary.Add("Defender RealTimeProtectionEnabled: $($script:defender.RealTimeProtectionEnabled)")
        if ($script:defender.RealTimeProtectionEnabled -eq $false) {
            $summary.Add('REVIEW: Microsoft Defender real-time protection reports disabled. Review installed security software and policy.')
        }
    }

    $summary.Add('')
    $summary.Add('RUNNING APPLICATIONS')
    if ($script:potentialCameraProcesses.Count -gt 0) {
        $names = @($script:potentialCameraProcesses | Select-Object -ExpandProperty ProcessName -Unique)
        $summary.Add('REVIEW: Running processes matched the camera/tracking/virtual-camera review list: ' + ($names -join ', '))
        $summary.Add('This is not proof of a conflict. Check potential-camera-apps.txt and camera-access-history.txt.')
    }
    else {
        $summary.Add('No running process names matched the camera/tracking/virtual-camera review list.')
    }

    $summary.Add('')
    $summary.Add('SYSTEM / HARDWARE')
    if ($script:problemDevices.Count -gt 0) {
        $summary.Add("REVIEW: Windows reports $($script:problemDevices.Count) PnP device(s) with non-zero error codes. See problem-devices.txt.")
    }
    else {
        $summary.Add('Windows reports no PnP devices with non-zero error codes.')
    }
    if ($script:applicationCameraErrors.Count -gt 0) {
        $summary.Add("REVIEW: Found $($script:applicationCameraErrors.Count) recent Application log warning/error event(s) matching camera/OpenTrack terms.")
    }
    if ($script:cameraEventCount -gt 0) {
        $summary.Add("INFO: Collected $script:cameraEventCount event(s) from enabled camera-related Windows event logs.")
    }

    $summary.Add('')
    $summary.Add('LIMITATION')
    $summary.Add('This version opens DelanCam1, measures whether its video stream delivers frames at a steady rate, and checksums frames in memory to detect a frozen stream (see STREAM TEST above and stream-test.txt).')
    $summary.Add('Content analysis cannot judge whether a varying image is visually correct.')
    $summary | Set-Content -LiteralPath (Join-Path $work 'SUMMARY.txt') -Encoding UTF8
}

Run-Step 'Compress diagnostic package' {
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    Compress-Archive -Path (Join-Path $work '*') -DestinationPath $zipPath -CompressionLevel Optimal -Force
}

if (-not (Test-Path -LiteralPath $zipPath)) {
    Write-Host 'ERROR: Diagnostic ZIP was not created.' -ForegroundColor Red
    exit 1
}

try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue } catch {}

Write-Host ''
Write-Host 'Diagnostic package created:' -ForegroundColor Green
Write-Host $zipPath -ForegroundColor Cyan
Write-Host ''

try { Start-Process explorer.exe -ArgumentList "/select,`"$zipPath`"" } catch {}

exit 0