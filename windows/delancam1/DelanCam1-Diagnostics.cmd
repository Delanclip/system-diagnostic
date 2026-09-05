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
echo security-product, installed-program and running-application
echo information, plus the Windows video-decoder registrations that camera
echo software depends on. It also briefly opens DelanCam1 to test its video
echo stream, but does NOT save any image or video data from the camera.
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
- a per-format probe (MJPG, NV12 and YUY2 at 640x480, 2 seconds each) that
  tells a camera delivering nothing from a Windows decoder problem that
  affects only MJPEG; again only frame counts are kept
- registered Media Foundation video decoders (names, identifiers, file
  paths) and the Windows hardware-decoder switch
- DirectShow registrations: core components, software/virtual cameras,
  filters with missing files or third-party locations, the preferred MJPG
  decoder, DoNotUse and VFW codec entries (names, identifiers, file paths)
- names, versions, publishers and install dates of installed programs
  (system-wide), because codec packs, virtual cameras and cleaner tools
  are common causes of camera failures
- time since the last restart, Fast Startup and pending-reboot state
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
$script:streamTestStoppedEarly = $false
$script:streamTestMinorHiccup = $false
$script:streamTestFirstFrameDelayMs = -1
$script:streamTestMaxGapMs = 0
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
        $loopStartWall = [DateTime]::UtcNow
        $firstFrameWall = $null
        $lastFrameWall = $null

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
                            if ($null -eq $firstFrameWall) { $firstFrameWall = [DateTime]::UtcNow }
                            $lastFrameWall = [DateTime]::UtcNow
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

        $loopEndWall = [DateTime]::UtcNow
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

        $firstFrameDelayMs = -1
        $tailSilenceMs = -1
        if ($null -ne $firstFrameWall) { $firstFrameDelayMs = [math]::Round(($firstFrameWall - $loopStartWall).TotalMilliseconds, 0) }
        if ($null -ne $lastFrameWall) { $tailSilenceMs = [math]::Round(($loopEndWall - $lastFrameWall).TotalMilliseconds, 0) }
        $streamStopped = $false
        if ($stats.FramesArrived -gt 0 -and $tailSilenceMs -gt [math]::Max(1000, ($stats.ExpectedIntervalMs * 10))) { $streamStopped = $true }
        $minorHiccup = $false
        if ($stats.StreamStalls -gt 0 -and $stats.StreamStalls -le 2 -and $stats.MaxGapMs -le 150 -and (-not $streamStopped) -and ($curFps -le 0 -or $measuredFps -ge (0.8 * $curFps))) { $minorHiccup = $true }

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
        $script:streamTestStoppedEarly = $streamStopped
        $script:streamTestMinorHiccup = $minorHiccup
        $script:streamTestFirstFrameDelayMs = $firstFrameDelayMs
        $script:streamTestMaxGapMs = [math]::Round($stats.MaxGapMs, 0)

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
        if ($firstFrameDelayMs -ge 0) { $lines.Add("First frame arrived: $firstFrameDelayMs ms after capture start") }
        if ($tailSilenceMs -ge 0) { $lines.Add("Silence after the last frame: $tailSilenceMs ms of the capture window") }
        if ($streamStopped) {
            $lines.Add('Note: the stream stopped delivering frames well before the end of the capture window. Security')
            $lines.Add('software with webcam-protection features can cut a camera stream mid-use; USB or driver faults')
            $lines.Add('can too. Compare with the installed security products in this report.')
        }
        if ($gapPattern -eq 'uniform-slow') {
            $lines.Add('Note: frame spacing is uniform rather than bursty. A uniformly slow frame rate is typical of')
            $lines.Add('auto-exposure lengthening exposure time when the scene appears dark to the camera, and is not')
            $lines.Add('by itself evidence of a USB or hardware fault.')
        }
        if ($minorHiccup) {
            $lines.Add('Note: the recorded stall(s) are brief and the overall frame rate is healthy. This is treated as')
            $lines.Add('normal system-load jitter, not a transport fault.')
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

$script:formatProbePerformed = $false
$script:formatProbeError = $null
$script:formatProbeMjpgFrames = 0
$script:formatProbeRawFrames = 0
$script:formatProbeRows = 0
Run-Step 'DelanCam1 format probe' {
    $path = Join-Path $work 'format-probe.txt'
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('Delanclip DelanCam1 Format Probe')
    $lines.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')")
    $lines.Add('')
    $lines.Add('Opens DelanCam1 once per format through the same Windows camera API as the stream test and')
    $lines.Add('counts the frames that arrive in a short window. It tells a camera that delivers nothing at all')
    $lines.Add('apart from a Windows decoder problem that affects only MJPEG. Nothing is saved from the frames;')
    $lines.Add('only counts are kept.')
    $lines.Add('')

    if ($script:delanCams.Count -eq 0) {
        $lines.Add('Skipped: DelanCam1 is not present.')
        $lines | Set-Content -LiteralPath $path -Encoding UTF8
        return
    }
    if (-not $script:streamTestOpened) {
        $lines.Add('Skipped: the stream test could not open DelanCam1, so a per-format probe would fail the same way.')
        $lines | Set-Content -LiteralPath $path -Encoding UTF8
        return
    }

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

    function Get-ProbeLabel {
        param($Format)
        $vf = $Format.VideoFormat
        $fr = $Format.FrameRate
        $fps = 0
        if ($fr -and $fr.Denominator -ne 0) { $fps = [math]::Round($fr.Numerator / $fr.Denominator, 2) }
        return ('{0} {1}x{2}@{3}' -f $Format.Subtype, $vf.Width, $vf.Height, $fps)
    }

    function Get-ProbeSource {
        param($MediaCapture, $Group)
        $sourceInfos = @($Group.SourceInfos)
        $chosenInfo = $sourceInfos | Where-Object { $_.SourceKind -eq [Windows.Media.Capture.Frames.MediaFrameSourceKind]::Color } | Select-Object -First 1
        if (-not $chosenInfo -and $sourceInfos.Count -gt 0) { $chosenInfo = $sourceInfos[0] }
        if (-not $chosenInfo) { throw 'MediaFrameSourceGroup exposed no source infos for this device.' }
        $framePairs = @($MediaCapture.FrameSources)
        $source = $null
        foreach ($pair in $framePairs) {
            if ([string]$pair.Key -eq [string]$chosenInfo.Id) { $source = $pair.Value; break }
        }
        if (-not $source -and $framePairs.Count -gt 0) { $source = $framePairs[0].Value }
        if (-not $source) { throw 'MediaCapture did not expose a usable frame source.' }
        return $source
    }

    function New-ProbeCapture {
        param($Group)
        $mc = New-Object Windows.Media.Capture.MediaCapture
        $settings = New-Object Windows.Media.Capture.MediaCaptureInitializationSettings
        $settings.SourceGroup = $Group
        $settings.SharingMode = [Windows.Media.Capture.MediaCaptureSharingMode]::ExclusiveControl
        $settings.MemoryPreference = [Windows.Media.Capture.MediaCaptureMemoryPreference]::Cpu
        $settings.StreamingCaptureMode = [Windows.Media.Capture.StreamingCaptureMode]::Video
        Wait-WinRtAction ($mc.InitializeAsync($settings)) 8000
        return $mc
    }

    $probeSeconds = 2
    $wanted = @('MJPG 640x480@60', 'NV12 640x480@60', 'MJPG 640x480@30', 'NV12 640x480@30', 'YUY2 640x480@30')
    $vidPidPattern = '(?i)VID_0120.*PID_1234'

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

        $devices = Wait-WinRtOperation ([Windows.Devices.Enumeration.DeviceInformation]::FindAllAsync([Windows.Devices.Enumeration.DeviceClass]::VideoCapture)) ([Windows.Devices.Enumeration.DeviceInformationCollection]) 5000
        $target = $devices | Where-Object { $_.Id -match $vidPidPattern } | Select-Object -First 1
        if (-not $target) { $target = $devices | Where-Object { $_.Name -match '(?i)DelanCam' } | Select-Object -First 1 }
        if (-not $target) { throw 'DelanCam1 is not visible to Windows Runtime camera enumeration.' }
        $group = Wait-WinRtOperation ([Windows.Media.Capture.Frames.MediaFrameSourceGroup]::FromIdAsync($target.Id)) ([Windows.Media.Capture.Frames.MediaFrameSourceGroup]) 5000
        if (-not $group) { throw 'No MediaFrameSourceGroup was found for DelanCam1.' }

        $listCapture = New-ProbeCapture $group
        $listSource = Get-ProbeSource $listCapture $group
        $supported = @($listSource.SupportedFormats)
        try { $listCapture.Dispose() } catch {}
        $listCapture = $null
        $script:formatProbePerformed = $true

        $lines.Add("Formats offered by the device: $($supported.Count). Capture window per probed format: ${probeSeconds}s.")
        $lines.Add('')
        $lines.Add(('{0,-18} {1,-18} {2,-8} {3,-8} {4,6} {5,8}  {6}' -f 'Requested', 'Negotiated', 'SetFmt', 'Start', 'Frames', 'FirstMs', 'Error'))
        $lines.Add(('-' * 96))

        foreach ($want in $wanted) {
            $fmt = $supported | Where-Object { (Get-ProbeLabel $_) -eq $want } | Select-Object -First 1
            if (-not $fmt) {
                $lines.Add(('{0,-18} {1}' -f $want, 'not offered by this device'))
                continue
            }
            $row = @{ Negotiated = ''; SetFmt = ''; Start = ''; Frames = 0; FirstMs = ''; Error = '' }
            $mc = $null
            $reader = $null
            try {
                $mc = New-ProbeCapture $group
                $src = Get-ProbeSource $mc $group
                try { Wait-WinRtAction ($src.SetFormatAsync($fmt)) 5000; $row.SetFmt = 'ok' }
                catch { $row.SetFmt = 'FAILED'; $row.Error = $_.Exception.Message }
                $row.Negotiated = Get-ProbeLabel $src.CurrentFormat
                $reader = Wait-WinRtOperation ($mc.CreateFrameReaderAsync($src)) ([Windows.Media.Capture.Frames.MediaFrameReader]) 8000
                $startStatus = Wait-WinRtOperation ($reader.StartAsync()) ([Windows.Media.Capture.Frames.MediaFrameReaderStartStatus]) 8000
                $row.Start = $startStatus.ToString()
                if ($startStatus.ToString() -eq 'Success') {
                    $lastTs = -1.0
                    $t0 = [DateTime]::UtcNow
                    $deadline = $t0.AddSeconds($probeSeconds)
                    while ([DateTime]::UtcNow -lt $deadline) {
                        $frame = $null
                        try {
                            $frame = $reader.TryAcquireLatestFrame()
                            if ($null -ne $frame) {
                                $tsRaw = $frame.SystemRelativeTime
                                $tsMs = $null
                                if ($tsRaw -is [TimeSpan]) { $tsMs = $tsRaw.TotalMilliseconds }
                                elseif ($null -ne $tsRaw) {
                                    try { $tsMs = ([TimeSpan]$tsRaw.Value).TotalMilliseconds }
                                    catch { try { $tsMs = ([TimeSpan]$tsRaw).TotalMilliseconds } catch {} }
                                }
                                $isNew = $false
                                if ($null -ne $tsMs) { if ($tsMs -ne $lastTs) { $isNew = $true; $lastTs = $tsMs } }
                                else { $isNew = $true }
                                if ($isNew) {
                                    $row.Frames++
                                    if ($row.FirstMs -eq '') { $row.FirstMs = [int]([DateTime]::UtcNow - $t0).TotalMilliseconds }
                                }
                            }
                        }
                        catch { if ($row.Error -eq '') { $row.Error = $_.Exception.Message } }
                        finally { if ($null -ne $frame) { try { $frame.Dispose() } catch {} } }
                        Start-Sleep -Milliseconds 2
                    }
                }
            }
            catch { if ($row.Error -eq '') { $row.Error = $_.Exception.Message } }
            finally {
                if ($reader) { try { Wait-WinRtAction ($reader.StopAsync()) 5000 } catch {}; try { $reader.Dispose() } catch {} }
                if ($mc) { try { $mc.Dispose() } catch {} }
            }
            $lines.Add(('{0,-18} {1,-18} {2,-8} {3,-8} {4,6} {5,8}  {6}' -f $want, $row.Negotiated, $row.SetFmt, $row.Start, $row.Frames, $row.FirstMs, $row.Error))
            $script:formatProbeRows++
            if ($want -like 'MJPG*') { $script:formatProbeMjpgFrames += $row.Frames } else { $script:formatProbeRawFrames += $row.Frames }
            Start-Sleep -Milliseconds 300
        }

        $lines.Add('')
        $lines.Add("MJPG frames total: $script:formatProbeMjpgFrames   NV12/YUY2 frames total: $script:formatProbeRawFrames")
        if ($script:formatProbeMjpgFrames -eq 0 -and $script:formatProbeRawFrames -gt 0) {
            $lines.Add('Reading: the camera streams normally in raw formats but every MJPEG request yields nothing. That is a')
            $lines.Add('Windows-side MJPEG decoding problem (see media-foundation.txt), not a camera or USB fault. Apps that')
            $lines.Add('pick raw formats (Windows Camera) keep working; apps that ask for MJPEG (OpenTrack, AITrack) get nothing.')
        }
        elseif ($script:formatProbeMjpgFrames -eq 0 -and $script:formatProbeRawFrames -eq 0) {
            $lines.Add('Reading: no format delivered frames. This points to USB, cable, driver or hardware, or to another')
            $lines.Add('application holding the camera.')
        }
        else {
            $lines.Add('Reading: frames arrived in MJPEG and raw formats. The Media Foundation path to this camera is healthy.')
        }
    }
    catch {
        $realEx = $_.Exception
        while ($realEx.InnerException) { $realEx = $realEx.InnerException }
        $script:formatProbeError = $realEx.Message
        $lines.Add("Probe error: $($realEx.Message)")
        Record-Error -Step 'DelanCam1 format probe' -Err $_
    }

    $lines | Set-Content -LiteralPath $path -Encoding UTF8
}

$script:mftHardwareDecoders = $null
$script:mftVendorMjpeg = @()
$script:mftMissingDll = @()
Run-Step 'Media Foundation decoders' {
    $path = Join-Path $work 'media-foundation.txt'
    $lines = New-Object System.Collections.Generic.List[string]
    $hwItem = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows Media Foundation\HardwareMFT' -ErrorAction SilentlyContinue
    $enableDecoders = $null
    if ($hwItem -and $null -ne $hwItem.EnableDecoders) { $enableDecoders = [int]$hwItem.EnableDecoders }
    $script:mftHardwareDecoders = $enableDecoders
    $decodersText = 'not set (default: enabled)'
    if ($null -ne $enableDecoders) { $decodersText = [string]$enableDecoders }
    $encodersText = 'not set (default: enabled)'
    if ($hwItem -and $null -ne $hwItem.EnableEncoders) { $encodersText = [string]$hwItem.EnableEncoders }
    $lines.Add("HardwareMFT EnableDecoders: $decodersText")
    $lines.Add("HardwareMFT EnableEncoders: $encodersText")
    $frameServer = Get-Service -Name FrameServer -ErrorAction SilentlyContinue
    $frameServerText = 'not found'
    if ($frameServer) { $frameServerText = [string]$frameServer.Status }
    $lines.Add("Windows Camera Frame Server service: $frameServerText")
    $lines.Add('')
    $lines.Add('Registered Media Foundation video decoders (category VIDEO_DECODER), 64-bit and 32-bit views.')
    $lines.Add('"vendor" means the DLL belongs to a driver package or a non-Microsoft vendor; when hardware decoders are')
    $lines.Add('enabled such decoders take precedence over the Microsoft ones. Only names, identifiers and file paths are listed.')
    $lines.Add('')

    $views = @(
        @{ Name = '64-bit'; Root = 'HKLM:\SOFTWARE\Classes' },
        @{ Name = '32-bit'; Root = 'HKLM:\SOFTWARE\Classes\WOW6432Node' }
    )
    foreach ($view in $views) {
        $catPath = Join-Path $view.Root 'MediaFoundation\Transforms\Categories\d6c02d4b-6833-45b4-971a-05a4b04bab91'
        if (-not (Test-Path -LiteralPath $catPath)) { $catPath = Join-Path $view.Root 'MediaFoundation\Transforms\Categories\{d6c02d4b-6833-45b4-971a-05a4b04bab91}' }
        $members = @(Get-ChildItem -LiteralPath $catPath -ErrorAction SilentlyContinue)
        $lines.Add("===== $($view.Name) view: $($members.Count) video decoder(s) =====")
        foreach ($member in $members) {
            $id = $member.PSChildName.Trim('{}')
            $name = (Get-ItemProperty -LiteralPath (Join-Path $view.Root ("MediaFoundation\Transforms\" + $id)) -ErrorAction SilentlyContinue).'(default)'
            if (-not $name) { $name = (Get-ItemProperty -LiteralPath (Join-Path $view.Root ("MediaFoundation\Transforms\{" + $id + "}")) -ErrorAction SilentlyContinue).'(default)' }
            if (-not $name) { $name = '(unnamed)' }
            $dll = (Get-ItemProperty -LiteralPath (Join-Path $view.Root ("CLSID\{" + $id + "}\InprocServer32")) -ErrorAction SilentlyContinue).'(default)'
            $state = ''
            if (-not $dll) { $state = 'no InprocServer32' }
            else {
                $dllClean = [Environment]::ExpandEnvironmentVariables(([string]$dll).Trim().Trim('"'))
                if (-not (Test-Path -LiteralPath $dllClean)) { $state = 'DLL MISSING' }
                elseif ($dllClean -match '(?i)\\DriverStore\\FileRepository\\' -or $dllClean -notmatch '(?i)^[a-z]:\\Windows\\(System32|SysWOW64)\\[^\\]+$' -or $name -match '(?i)intel|nvidia|amd |radeon|qualcomm|snapdragon|mediatek') { $state = 'vendor' }
                else { $state = 'Windows' }
            }
            $lines.Add(('{0,-45} {1,-16} {2}  {3}' -f $name, $state, ('{' + $id + '}'), $dll))
            if ($state -eq 'DLL MISSING') { $script:mftMissingDll += "$name ($($view.Name))" }
            if ($state -eq 'vendor' -and $name -match '(?i)jpeg|jpg') { $script:mftVendorMjpeg += "$name ($($view.Name))" }
        }
        $lines.Add('')
    }
    $lines | Set-Content -LiteralPath $path -Encoding UTF8
}

$script:dshowMissingCore = @()
$script:dshowVirtualCameras = @()
$script:dshowDeadFilters = @()
$script:dshowVendorFilters = @()
$script:dshowPreferredMjpgIssue = $null
$script:dshowDoNotUse = @()
$script:vfwMissing64 = @()
$script:vfwMissing32 = @()
Run-Step 'DirectShow registrations' {
    $path = Join-Path $work 'directshow.txt'
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('DirectShow registrations relevant to camera capture, 64-bit and 32-bit views. OpenTrack and AITrack build')
    $lines.Add('their camera graph on these. Only names, identifiers and file paths are listed.')
    $lines.Add('')

    function Get-DsInproc {
        param($Root, $Clsid)
        return (Get-ItemProperty -LiteralPath (Join-Path $Root ("CLSID\" + $Clsid + "\InprocServer32")) -ErrorAction SilentlyContinue).'(default)'
    }
    function Get-DsFileState {
        param($Dll)
        if (-not $Dll) { return 'no InprocServer32' }
        $clean = [Environment]::ExpandEnvironmentVariables(([string]$Dll).Trim().Trim('"'))
        if (-not (Test-Path -LiteralPath $clean)) { return 'DLL MISSING' }
        if ($clean -match '(?i)^[a-z]:\\Windows\\') { return 'Windows' }
        return 'third-party location'
    }

    $views = @(
        @{ Name = '64-bit'; Classes = 'HKLM:\SOFTWARE\Classes'; Software = 'HKLM:\SOFTWARE' },
        @{ Name = '32-bit'; Classes = 'HKLM:\SOFTWARE\Classes\WOW6432Node'; Software = 'HKLM:\SOFTWARE\WOW6432Node' }
    )
    $core = @(
        @{ N = 'KS proxy (ksproxy.ax)'; C = '{17CCA71B-ECD7-11D0-B908-00A0C9223196}' },
        @{ N = 'SampleGrabber (qedit.dll)'; C = '{C1F400A0-3F08-11d3-9F0B-006008039E37}' },
        @{ N = 'FilterGraph (quartz.dll)'; C = '{e436ebb3-524f-11ce-9f53-0020af0ba770}' },
        @{ N = 'MJPEG Decompressor (quartz.dll)'; C = '{301056D0-6DFF-11d2-9EEB-006008039E37}' },
        @{ N = 'AVI Decompressor (quartz.dll)'; C = '{CF49D4E0-1115-11CE-B03A-0020AF0BA770}' },
        @{ N = 'Color Space Converter (quartz.dll)'; C = '{1643E180-90F5-11CE-97D5-00AA0055595A}' },
        @{ N = 'CaptureGraphBuilder2 (qcap.dll)'; C = '{BF87B6E1-8C27-11d0-B3F0-00AA003761C5}' },
        @{ N = 'Smart Tee (qcap.dll)'; C = '{CC58E280-8AA1-11d1-B3F1-00AA003761C5}' },
        @{ N = 'SystemDeviceEnum (devenum.dll)'; C = '{62BE5D10-60EB-11d0-BD3B-00A0C911CE86}' }
    )
    $expectedVfw = @{ 'vidc.cvid' = 'iccvid.dll'; 'vidc.i420' = 'iyuv_32.dll'; 'vidc.iyuv' = 'iyuv_32.dll'; 'vidc.mrle' = 'msrle32.dll'; 'vidc.msvc' = 'msvidc32.dll'; 'vidc.uyvy' = 'msyuv.dll'; 'vidc.yuy2' = 'msyuv.dll'; 'vidc.yvu9' = 'tsbyuv.dll'; 'vidc.yvyu' = 'msyuv.dll' }
    $ignoreDead = '(?i)^(Line 21 Decoder|Overlay Mixer|Overlay Mixer2|VBI Surface Allocator)$'

    foreach ($view in $views) {
        $lines.Add("################ $($view.Name) view ################")
        $lines.Add('')
        $lines.Add('--- Core components ---')
        foreach ($c in $core) {
            $dll = Get-DsInproc $view.Classes $c.C
            $state = Get-DsFileState $dll
            $treatAs = (Get-ItemProperty -LiteralPath (Join-Path $view.Classes ("CLSID\" + $c.C + "\TreatAs")) -ErrorAction SilentlyContinue).'(default)'
            $treatText = ''
            if ($treatAs) { $treatText = "  TreatAs=$treatAs" }
            $lines.Add(('{0,-38} {1,-45} {2}{3}' -f $c.N, $dll, $state, $treatText))
            if (-not $dll -or $state -eq 'DLL MISSING') { $script:dshowMissingCore += "$($c.N) [$($view.Name)]" }
            if ($treatAs) { $script:dshowMissingCore += "$($c.N) redirected by TreatAs to $treatAs [$($view.Name)]" }
        }
        $lines.Add('')
        $lines.Add('--- Software/virtual cameras registered as video input devices (real USB cameras are never listed here) ---')
        $ghosts = @(Get-ChildItem -LiteralPath (Join-Path $view.Classes 'CLSID\{860BB310-5D01-11d0-BD3B-00A0C911CE86}\Instance') -ErrorAction SilentlyContinue)
        if ($ghosts.Count -eq 0) { $lines.Add('(none)') }
        foreach ($g in $ghosts) {
            $p = Get-ItemProperty -LiteralPath $g.PSPath -ErrorAction SilentlyContinue
            $clsid = $g.PSChildName
            if ($p.CLSID) { $clsid = [string]$p.CLSID }
            $dll = Get-DsInproc $view.Classes $clsid
            $state = Get-DsFileState $dll
            $lines.Add(('{0,-40} {1,-40} {2}  {3}' -f $p.FriendlyName, $clsid, $dll, $state))
            $script:dshowVirtualCameras += "$($p.FriendlyName) [$($view.Name), $state]"
        }
        $lines.Add('')
        $lines.Add('--- DirectShow filters whose DLL is missing or lives outside the Windows folder ---')
        $filters = @(Get-ChildItem -LiteralPath (Join-Path $view.Classes 'CLSID\{083863F1-70DE-11d0-BD40-00A0C911CE86}\Instance') -ErrorAction SilentlyContinue)
        $lines.Add("Registered filters: $($filters.Count)")
        $flagged = 0
        foreach ($f in $filters) {
            $p = Get-ItemProperty -LiteralPath $f.PSPath -ErrorAction SilentlyContinue
            $clsid = $f.PSChildName
            if ($p.CLSID) { $clsid = [string]$p.CLSID }
            $dll = Get-DsInproc $view.Classes $clsid
            $state = Get-DsFileState $dll
            if ($state -eq 'Windows') { continue }
            $flagged++
            $lines.Add(('{0,-45} {1,-40} {2}  {3}' -f $p.FriendlyName, $clsid, $dll, $state))
            if ($state -eq 'DLL MISSING' -or $state -eq 'no InprocServer32') {
                if ([string]$p.FriendlyName -notmatch $ignoreDead) { $script:dshowDeadFilters += "$($p.FriendlyName) [$($view.Name)]" }
            }
            else {
                $script:dshowVendorFilters += "$($p.FriendlyName) [$($view.Name)]"
            }
        }
        if ($flagged -eq 0) { $lines.Add('(all registered filters point to existing files inside the Windows folder)') }
        $lines.Add('')
        $lines.Add('--- Preferred decoder for MJPG (HKLM\SOFTWARE\Microsoft\DirectShow\Preferred) ---')
        $pref = Get-ItemProperty -LiteralPath (Join-Path $view.Software 'Microsoft\DirectShow\Preferred') -ErrorAction SilentlyContinue
        $mjpgTarget = $null
        if ($pref) { $mjpgTarget = $pref.'{47504A4D-0000-0010-8000-00AA00389B71}' }
        if ($mjpgTarget) {
            $tName = (Get-ItemProperty -LiteralPath (Join-Path $view.Classes ("CLSID\" + $mjpgTarget)) -ErrorAction SilentlyContinue).'(default)'
            $tDll = Get-DsInproc $view.Classes $mjpgTarget
            $tState = Get-DsFileState $tDll
            $lines.Add("MJPG -> $mjpgTarget  $tName  ($tState)")
            if ($tState -ne 'Windows' -or ([string]$mjpgTarget) -notmatch '(?i)^\{301056D0-6DFF-11D2-9EEB-006008039E37\}$') {
                $script:dshowPreferredMjpgIssue = "$mjpgTarget $tName ($tState) [$($view.Name)]"
            }
        }
        else { $lines.Add('MJPG -> not set (Windows default applies)') }
        $lines.Add('')
        $lines.Add('--- DoNotUse (filters DirectShow is told to skip) ---')
        $dnu = Get-ItemProperty -LiteralPath (Join-Path $view.Software 'Microsoft\DirectShow\DoNotUse') -ErrorAction SilentlyContinue
        $dnuCount = 0
        if ($dnu) {
            foreach ($prop in ($dnu.PSObject.Properties | Where-Object { $_.Name -match '^\{' })) {
                $dnuCount++
                $dn = (Get-ItemProperty -LiteralPath (Join-Path $view.Classes ("CLSID\" + $prop.Name)) -ErrorAction SilentlyContinue).'(default)'
                $lines.Add("$($prop.Name)  $dn")
                $script:dshowDoNotUse += "$($prop.Name) $dn [$($view.Name)]"
            }
        }
        if ($dnuCount -eq 0) { $lines.Add('(empty)') }
        $lines.Add('')
        $lines.Add('--- VFW video codecs (Drivers32 vidc.* entries) ---')
        $d32 = Get-ItemProperty -LiteralPath (Join-Path $view.Software 'Microsoft\Windows NT\CurrentVersion\Drivers32') -ErrorAction SilentlyContinue
        $present = @{}
        if ($d32) {
            foreach ($prop in ($d32.PSObject.Properties | Where-Object { $_.Name -match '(?i)^vidc\.' })) {
                $present[$prop.Name.ToLower()] = [string]$prop.Value
                $lines.Add(('{0,-14} {1}' -f $prop.Name, $prop.Value))
            }
        }
        $missing = @($expectedVfw.Keys | Where-Object { -not $present.ContainsKey($_) } | Sort-Object)
        if ($missing.Count -gt 0) { $lines.Add('Missing stock entries: ' + ($missing -join ', ')) }
        if ($view.Name -eq '64-bit') { $script:vfwMissing64 = $missing } else { $script:vfwMissing32 = $missing }
        $lines.Add('')
    }
    $cachePresent = Test-Path -LiteralPath 'HKCU:\Software\Microsoft\ActiveMovie\devenum'
    $lines.Add("Per-user DirectShow device cache (HKCU\Software\Microsoft\ActiveMovie\devenum) present: $cachePresent")
    $lines | Set-Content -LiteralPath $path -Encoding UTF8
}

$script:softwareCount = 0
$script:softwareCodecPacks = @()
$script:softwareCleaners = @()
$script:softwareVirtualCams = @()
$script:softwareSecuritySuites = @()
$script:softwarePs3EyeTooling = @()
$script:softwareTracking = @()
$script:softwareInjectors = @()
Run-Step 'Installed software' {
    $path = Join-Path $work 'installed-software.txt'
    $uninstallPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $apps = @(Get-ItemProperty -Path $uninstallPaths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName } |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
        Sort-Object DisplayName -Unique)
    $script:softwareCount = $apps.Count

    foreach ($app in $apps) {
        $n = [string]$app.DisplayName
        if ($n -match '(?i)k-lite|ffdshow|shark007|cccp|codec pack|lav filters|xvid|divx') { $script:softwareCodecPacks += $n }
        if ($n -match '(?i)driver booster|ccleaner|advanced systemcare|iobit|glary|wise care|shutup10|debloat|winutil|reg organizer|jv16') { $script:softwareCleaners += $n }
        if ($n -match '(?i)nikon webcam|webcam utility|streamlabs|manycam|xsplit|snap camera|nvidia broadcast|imyfone|magicmic|voicemod|virtual camera|virtualcam|obs studio|droidcam|ivcam|chromacam|epoccam') { $script:softwareVirtualCams += $n }
        if ($n -match '(?i)kaspersky|eset|bitdefender|norton|mcafee|avast|avg (anti|internet|ultimate)|trend micro|hp wolf|malwarebytes|sophos|webroot|f-secure|g data|panda security|avira') { $script:softwareSecuritySuites += $n }
        if ($n -match '(?i)cl-eye|code laboratories|libusb|zadig') { $script:softwarePs3EyeTooling += $n }
        if ($n -match '(?i)opentrack|aitrack|facetracknoir|tobii|trackir|track ir|eyeware|smoothtrack') { $script:softwareTracking += $n }
        if ($n -match '(?i)nahimic|sonic studio|afterburner|rivatuner|razer cortex') { $script:softwareInjectors += $n }
    }

    $hot = '(?i)camera|webcam|\bcam\b|codec|k-lite|ffdshow|\blav\b|shark007|cccp|xvid|divx|nikon|streamlabs|\bobs\b|manycam|xsplit|snap camera|broadcast|imyfone|magicmic|voicemod|virtual|opentrack|aitrack|facetrack|tobii|trackir|eyeware|logitech|g hub|razer|synapse|cortex|corsair|icue|msi center|dragon center|afterburner|rivatuner|nahimic|sonic studio|oculus|steamvr|discord|zoom|teams|skype|cl-eye|code laboratories|libusb|zadig|driver booster|ccleaner|advanced systemcare|iobit|glary|wise care|shutup|debloat|winutil|kaspersky|eset|bitdefender|norton|mcafee|avast|avg |trend micro|malwarebytes|hp wolf'
    $highlights = @($apps | Where-Object { ([string]$_.DisplayName) -match $hot })

    $out = New-Object System.Collections.Generic.List[string]
    $out.Add("Installed programs: $($apps.Count). Only names, versions, publishers and install dates are listed.")
    $out.Add('Camera, codec, tracking, overlay, security and system-cleaner software comes first because these are the')
    $out.Add('usual sources of camera conflicts; the full list follows.')
    $out.Add('')
    $out.Add("===== Highlights ($($highlights.Count)) =====")
    if ($highlights.Count -gt 0) {
        ($highlights | Format-Table DisplayName, DisplayVersion, Publisher, InstallDate -AutoSize | Out-String -Width 400) -split "`r?`n" | ForEach-Object { $out.Add($_) }
    }
    else { $out.Add('(none matched)') }
    $out.Add("===== Full list ($($apps.Count)) =====")
    ($apps | Format-Table DisplayName, DisplayVersion, Publisher, InstallDate -AutoSize | Out-String -Width 400) -split "`r?`n" | ForEach-Object { $out.Add($_) }
    $out | Set-Content -LiteralPath $path -Encoding UTF8
}

$script:uptimeDays = -1
$script:fastStartup = $null
$script:pendingReboot = $false
Run-Step 'Restart state' {
    $path = Join-Path $work 'restart-state.txt'
    $os = Get-CimInstance Win32_OperatingSystem
    $uptime = (Get-Date) - $os.LastBootUpTime
    $script:uptimeDays = [int][math]::Floor($uptime.TotalDays)
    $hiber = (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -ErrorAction SilentlyContinue).HiberbootEnabled
    $script:fastStartup = $hiber
    $pendWU = Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    $pendCBS = Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    $pendRename = $null -ne (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction SilentlyContinue).PendingFileRenameOperations
    $script:pendingReboot = [bool]($pendWU -or $pendCBS -or $pendRename)
    @(
        "Last boot: $($os.LastBootUpTime)",
        "Time since last boot: $([int]$uptime.TotalDays) day(s) $($uptime.Hours) hour(s)",
        "Fast Startup (HiberbootEnabled): $hiber   (1 means 'Shut down' hibernates the kernel; only 'Restart' fully reloads drivers)",
        "Pending reboot: WindowsUpdate=$pendWU  ComponentServicing=$pendCBS  PendingFileRename=$pendRename"
    ) | Set-Content -LiteralPath $path -Encoding UTF8
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
    (& $powercfg /query SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 2>&1) | Out-String -Width 500 | Add-Content -LiteralPath $path -Encoding UTF8
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
            ForEach-Object {
                $message = ''
                try { $message = [string]$_.Message } catch {}
                if ([string]::IsNullOrWhiteSpace($message)) {
                    try { $message = (($_.Properties | ForEach-Object { [string]$_.Value }) -join ' ') } catch {}
                }
                [PSCustomObject]@{ TimeCreated = $_.TimeCreated; Id = $_.Id; Level = $_.LevelDisplayName; Provider = $_.ProviderName; Text = $message }
            } |
            Where-Object {
                $message = [string]$_.Text
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
                Select-Object TimeCreated, Id, Level, Provider, Text |
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
            if ($script:formatProbePerformed -and $script:formatProbeMjpgFrames -eq 0 -and $script:formatProbeRawFrames -gt 0) {
                $summary.Add("REVIEW HIGH: DelanCam1 delivered zero MJPEG frames, yet $script:formatProbeRawFrames NV12/YUY2 frame(s) arrived in the format probe. The camera and USB link work; MJPEG decoding inside Windows Media Foundation is broken on this PC. See FORMAT PROBE and WINDOWS VIDEO PIPELINE below.")
            }
            elseif ($script:formatProbePerformed -and $script:formatProbeMjpgFrames -eq 0 -and $script:formatProbeRawFrames -eq 0) {
                $summary.Add('REVIEW HIGH: DelanCam1 opened but delivered zero frames in the stream test and in every probed format. This points to USB, cable, driver or hardware, or to another application holding the camera, not to the application layer.')
            }
            else {
                $summary.Add('REVIEW HIGH: DelanCam1 opened but delivered zero frames. This points to USB, driver or hardware, not the application layer. See format-probe.txt for whether the failure is format-specific.')
            }
        }
        elseif ($script:streamTestFramesReceived -lt 5) {
            $summary.Add("REVIEW HIGH: The stream delivered only $script:streamTestFramesReceived frame(s) in the capture window (first frame after $script:streamTestFirstFrameDelayMs ms). Too few to measure a working video feed. This usually points to USB, driver or hardware; extreme low light can also slow frame delivery this much on an IR camera, so check the sampled brightness below before ruling that out.")
        }
        elseif ($script:streamTestStreamStalls -gt 0 -and $script:streamTestGapPattern -eq 'uniform-slow') {
            $summary.Add('INFO: Frames arrived slower than the nominal FPS but with uniform spacing - consistent with auto-exposure in a scene that appears dark to this IR tracking camera, not with a transport fault. See stream-test.txt.')
        }
        elseif ($script:streamTestStreamStalls -gt 0 -and $script:streamTestMinorHiccup) {
            $summary.Add("INFO: $script:streamTestStreamStalls brief frame-delivery hiccup(s) (largest gap $script:streamTestMaxGapMs ms) in an otherwise steady stream - common under normal system load, not treated as a fault.")
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
        if ($script:streamTestStoppedEarly) {
            $summary.Add('REVIEW: The stream stopped delivering frames well before the end of the capture window. Webcam-protection features in security software can cut camera streams mid-use; USB or driver faults can too. Compare with the security products listed below.')
        }
        $summary.Add('Content analysis flags frozen/identical frames but cannot judge whether a varying image looks correct. See stream-test.txt for full detail.')
    }

    $summary.Add('')
    $summary.Add('FORMAT PROBE')
    if (-not $script:formatProbePerformed) {
        if ($script:formatProbeError) { $summary.Add("Format probe did not run: $script:formatProbeError") }
        else { $summary.Add('Format probe was skipped (DelanCam1 absent or not openable). See format-probe.txt.') }
    }
    else {
        $summary.Add("MJPG frames: $script:formatProbeMjpgFrames, NV12/YUY2 frames: $script:formatProbeRawFrames across $script:formatProbeRows probed format(s), 2 s each.")
        if ($script:formatProbeMjpgFrames -eq 0 -and $script:formatProbeRawFrames -gt 0) {
            $summary.Add('REVIEW HIGH: MJPEG delivers nothing while raw formats stream normally. The camera and USB link are fine; MJPEG decoding inside Windows Media Foundation is broken on this PC. Windows Camera (raw formats) keeps working, OpenTrack and AITrack (MJPEG) get no frames. Check WINDOWS VIDEO PIPELINE below for the decoder responsible.')
        }
        elseif ($script:formatProbeMjpgFrames -eq 0 -and $script:formatProbeRawFrames -eq 0) {
            $summary.Add('REVIEW HIGH: No probed format delivered frames. This points to USB, cable, driver or hardware, or to another application holding the camera.')
        }
        elseif ($script:formatProbeMjpgFrames -gt 0 -and $script:formatProbeRawFrames -gt 0) {
            $summary.Add('Every probed format delivered frames: the Media Foundation path to this camera is healthy. If OpenTrack still cannot open the camera, the fault is in the DirectShow layer it uses; see WINDOWS VIDEO PIPELINE below.')
        }
        else {
            $summary.Add('MJPEG delivered frames but the raw formats did not. Unusual; see format-probe.txt.')
        }
    }

    $summary.Add('')
    $summary.Add('WINDOWS VIDEO PIPELINE')
    $pipelineFindings = 0
    if ($script:mftVendorMjpeg.Count -gt 0) {
        $pipelineFindings++
        if ($null -eq $script:mftHardwareDecoders -or $script:mftHardwareDecoders -ne 0) {
            $summary.Add('REVIEW HIGH: A vendor MJPEG decoder is registered in Media Foundation and hardware decoders are enabled: ' + ($script:mftVendorMjpeg -join ', ') + '. Such decoders are known to swallow every MJPEG frame while raw formats keep working. Compare with FORMAT PROBE. See media-foundation.txt.')
        }
        else {
            $summary.Add('INFO: A vendor MJPEG decoder is registered in Media Foundation, but hardware decoders are disabled (EnableDecoders=0), so it is not used: ' + ($script:mftVendorMjpeg -join ', ') + '.')
        }
    }
    if ($script:mftMissingDll.Count -gt 0) {
        $pipelineFindings++
        $summary.Add('REVIEW: Media Foundation decoder(s) registered with a missing DLL: ' + ($script:mftMissingDll -join ', ') + '.')
    }
    if ($script:dshowMissingCore.Count -gt 0) {
        $pipelineFindings++
        $summary.Add('REVIEW HIGH: DirectShow core component(s) missing or redirected: ' + ($script:dshowMissingCore -join '; ') + '. OpenTrack and AITrack build their camera graph on these. See directshow.txt.')
    }
    if ($script:dshowVirtualCameras.Count -gt 0) {
        $pipelineFindings++
        $summary.Add('REVIEW: Software/virtual cameras registered in DirectShow: ' + ($script:dshowVirtualCameras -join '; ') + '. They appear in OpenTrack''s camera list; an entry whose DLL is missing is a leftover of removed software.')
    }
    if ($script:dshowDeadFilters.Count -gt 0) {
        $pipelineFindings++
        $summary.Add('REVIEW HIGH: DirectShow filter(s) registered with missing files: ' + ($script:dshowDeadFilters -join '; ') + '. Dead codec registrations (for example LAV filters left behind by an uninstalled app) can stop MJPEG capture graphs from building.')
    }
    if ($script:dshowVendorFilters.Count -gt 0) {
        $pipelineFindings++
        $summary.Add('INFO: Third-party DirectShow filters present: ' + (($script:dshowVendorFilters | Select-Object -First 8) -join '; ') + '.')
    }
    if ($script:dshowPreferredMjpgIssue) {
        $pipelineFindings++
        $summary.Add("REVIEW HIGH: The DirectShow preferred decoder for MJPG is not the Windows default: $script:dshowPreferredMjpgIssue. Codec packs set this; a target that no longer exists breaks every MJPG graph.")
    }
    if ($script:dshowDoNotUse.Count -gt 0) {
        $pipelineFindings++
        $summary.Add('REVIEW: DirectShow DoNotUse list blocks filter(s): ' + ($script:dshowDoNotUse -join '; ') + '.')
    }
    if ($script:vfwMissing64.Count -gt 0) {
        $pipelineFindings++
        $summary.Add('REVIEW HIGH: 64-bit VFW codec registrations missing from Drivers32: ' + ($script:vfwMissing64 -join ', ') + '. 64-bit DirectShow apps such as OpenTrack need vidc.yuy2 (msyuv.dll) to convert camera frames to RGB; without it the capture graph fails to build even with MJPEG off.')
    }
    if ($script:vfwMissing32.Count -gt 0) {
        $pipelineFindings++
        $summary.Add('REVIEW: 32-bit VFW codec registrations missing from Drivers32: ' + ($script:vfwMissing32 -join ', ') + '.')
    }
    if ($pipelineFindings -eq 0) {
        $summary.Add('Media Foundation decoders, DirectShow registrations and VFW codecs look stock. See media-foundation.txt and directshow.txt.')
    }

    $summary.Add('')
    $summary.Add('INSTALLED SOFTWARE')
    $summary.Add("$script:softwareCount installed program(s) are listed in installed-software.txt.")
    $softwareFindings = 0
    if ($script:softwareCodecPacks.Count -gt 0) {
        $softwareFindings++
        $summary.Add('REVIEW HIGH: Codec pack(s) installed: ' + ($script:softwareCodecPacks -join ', ') + '. Codec packs replace DirectShow decoders and are the usual reason camera graphs fail on MJPEG or YUY2.')
    }
    if ($script:softwareCleaners.Count -gt 0) {
        $softwareFindings++
        $summary.Add('REVIEW: System cleaner / tweak tool(s) installed: ' + ($script:softwareCleaners -join ', ') + '. These remove registry entries such as VFW codecs and DirectShow filters; compare with WINDOWS VIDEO PIPELINE.')
    }
    if ($script:softwarePs3EyeTooling.Count -gt 0) {
        $softwareFindings++
        $summary.Add('REVIEW: PS3 Eye / libusb tooling installed: ' + ($script:softwarePs3EyeTooling -join ', ') + '. Ask whether the PS3 Eye driver procedure was ever applied to DelanCam1.')
    }
    if ($script:softwareVirtualCams.Count -gt 0) {
        $softwareFindings++
        $summary.Add('INFO: Virtual-camera or codec-bundling software installed: ' + ($script:softwareVirtualCams -join ', ') + '.')
    }
    if ($script:softwareSecuritySuites.Count -gt 0) {
        $softwareFindings++
        $summary.Add('INFO: Security suite(s) with possible webcam protection: ' + ($script:softwareSecuritySuites -join ', ') + '.')
    }
    if ($script:softwareInjectors.Count -gt 0) {
        $softwareFindings++
        $summary.Add('INFO: Overlay / process-injecting software installed: ' + ($script:softwareInjectors -join ', ') + '.')
    }
    if ($script:softwareTracking.Count -gt 0) {
        $softwareFindings++
        $summary.Add('INFO: Tracking software installed: ' + ($script:softwareTracking -join ', ') + '.')
    }
    if ($softwareFindings -eq 0) {
        $summary.Add('No codec packs, system cleaners, virtual cameras, PS3 Eye tooling or security suites were found among installed programs.')
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
    if ($script:uptimeDays -ge 7) {
        $summary.Add("INFO: $script:uptimeDays day(s) since the last full restart (Fast Startup = $script:fastStartup). Ask for Restart, not Shut down, before drawing conclusions from driver behaviour.")
    }
    if ($script:pendingReboot) {
        $summary.Add('INFO: Windows reports a pending reboot (servicing not finished). Restart before judging driver or codec state.')
    }

    $summary.Add('')
    $summary.Add('LIMITATION')
    $summary.Add('This version opens DelanCam1, measures whether its video stream delivers frames at a steady rate, checksums frames in memory to detect a frozen stream, probes MJPG, NV12 and YUY2 separately, and inspects the Windows video-pipeline registrations (Media Foundation decoders, DirectShow filters, VFW codecs) and the installed-program list.')
    $summary.Add('Content analysis cannot judge whether a varying image is visually correct, and registry findings are review flags for Delanclip Support, not proof of the cause.')
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