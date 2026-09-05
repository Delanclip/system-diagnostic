# Delanclip DelanCam1 stream probe (support-side helper)
#
# Opens DelanCam1 through the Windows Runtime camera API (Media Foundation /
# Frame Server, the same path the Windows Camera app uses) once per format and
# reports how many frames arrive within a few seconds for each format.
#
# The probe prints to the console only. It writes no files, saves no image or
# video data, makes no network connections and changes nothing on the system.
#
# Usage (run from the interactive user session, not from a SYSTEM console):
#   powershell -NoProfile -ExecutionPolicy Bypass -NoExit -File StreamProbe.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -NoExit -File StreamProbe.ps1 -All
#   powershell -NoProfile -ExecutionPolicy Bypass -NoExit -File StreamProbe.ps1 -Seconds 5

param(
    [int]$Seconds = 3,
    [switch]$All
)

$ErrorActionPreference = 'Stop'
$vidPidPattern = '(?i)VID_0120.*PID_1234'

# Curated list: the OpenTrack format first, then the same resolution at 30 fps
# in every pixel format the camera offers, then the formats Windows Camera
# typically picks by itself. 'DEFAULT' means "whatever the device starts with".
$curated = @(
    'MJPG 640x480@60',
    'NV12 640x480@60',
    'MJPG 640x480@30',
    'NV12 640x480@30',
    'YUY2 640x480@30',
    'MJPG 1280x720@30',
    'NV12 1280x720@30',
    'YUY2 1280x720@10',
    'DEFAULT'
)

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

function Get-FormatFps {
    param($Format)
    $fr = $Format.FrameRate
    if ($fr -and $fr.Denominator -ne 0) { return [math]::Round($fr.Numerator / $fr.Denominator, 2) }
    return 0
}

function Format-Label {
    param($Format)
    $vf = $Format.VideoFormat
    return ('{0} {1}x{2}@{3}' -f $Format.Subtype, $vf.Width, $vf.Height, (Get-FormatFps $Format))
}

function Get-FrameSource {
    param($MediaCapture, $Group)
    $sourceInfos = @($Group.SourceInfos)
    $chosenInfo = $sourceInfos | Where-Object { $_.SourceKind -eq [Windows.Media.Capture.Frames.MediaFrameSourceKind]::Color } | Select-Object -First 1
    if (-not $chosenInfo -and $sourceInfos.Count -gt 0) { $chosenInfo = $sourceInfos[0] }
    if (-not $chosenInfo) { throw 'MediaFrameSourceGroup exposed no source infos for this device.' }
    $framePairs = @($MediaCapture.FrameSources)
    $frameSource = $null
    foreach ($pair in $framePairs) {
        if ([string]$pair.Key -eq [string]$chosenInfo.Id) { $frameSource = $pair.Value; break }
    }
    if (-not $frameSource -and $framePairs.Count -gt 0) { $frameSource = $framePairs[0].Value }
    if (-not $frameSource) { throw "MediaCapture did not expose a usable frame source (entries: $($framePairs.Count))." }
    return $frameSource
}

function New-Capture {
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

function Test-OneFormat {
    param($Group, [string]$Label, $Format, [int]$CaptureSeconds)

    $result = [ordered]@{
        Requested   = $Label
        Negotiated  = ''
        SetFormat   = ''
        Start       = ''
        Frames      = 0
        Acquired    = 0
        Bitmaps     = 0
        FirstMs     = ''
        Error       = ''
    }

    $mc = $null
    $reader = $null
    try {
        $mc = New-Capture $Group
        $source = Get-FrameSource $mc $Group

        if ($Format) {
            try {
                Wait-WinRtAction ($source.SetFormatAsync($Format)) 5000
                $result.SetFormat = 'ok'
            }
            catch {
                $result.SetFormat = 'FAILED: ' + $_.Exception.Message
            }
        }
        else {
            $result.SetFormat = 'not requested'
        }

        $result.Negotiated = Format-Label $source.CurrentFormat

        $reader = Wait-WinRtOperation ($mc.CreateFrameReaderAsync($source)) ([Windows.Media.Capture.Frames.MediaFrameReader]) 8000
        $startStatus = Wait-WinRtOperation ($reader.StartAsync()) ([Windows.Media.Capture.Frames.MediaFrameReaderStartStatus]) 8000
        $result.Start = $startStatus.ToString()
        if ($startStatus.ToString() -ne 'Success') {
            return $result
        }

        $lastTs = -1.0
        $loopStart = [DateTime]::UtcNow
        $deadline = $loopStart.AddSeconds($CaptureSeconds)
        while ([DateTime]::UtcNow -lt $deadline) {
            $frame = $null
            try {
                $frame = $reader.TryAcquireLatestFrame()
                if ($null -ne $frame) {
                    $result.Acquired++
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
                        $result.Frames++
                        if ($result.FirstMs -eq '') { $result.FirstMs = [int]([DateTime]::UtcNow - $loopStart).TotalMilliseconds }
                        $vmf = $frame.VideoMediaFrame
                        if ($vmf -and $vmf.SoftwareBitmap) { $result.Bitmaps++ }
                    }
                }
            }
            catch {
                if ($result.Error -eq '') { $result.Error = 'frame loop: ' + $_.Exception.Message }
            }
            finally {
                if ($null -ne $frame) { try { $frame.Dispose() } catch {} }
            }
            Start-Sleep -Milliseconds 2
        }
    }
    catch {
        $result.Error = $_.Exception.Message
    }
    finally {
        if ($reader) {
            try { Wait-WinRtAction ($reader.StopAsync()) 5000 } catch {}
            try { $reader.Dispose() } catch {}
        }
        if ($mc) { try { $mc.Dispose() } catch {} }
    }
    return $result
}

Write-Host ''
Write-Host 'Delanclip DelanCam1 stream probe (Media Foundation / Frame Server path)'
Write-Host ("Time: {0}   User: {1}   Windows build: {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'), [Environment]::UserName, [Environment]::OSVersion.Version.Build)
Write-Host ''

Add-Type -AssemblyName System.Runtime.WindowsRuntime
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
Write-Host ("Video capture devices seen by Windows: {0}" -f @($devices).Count)
foreach ($d in $devices) { Write-Host ("  - {0}  [{1}]" -f $d.Name, $d.Id) }
Write-Host ''

$target = $devices | Where-Object { $_.Id -match $vidPidPattern } | Select-Object -First 1
if (-not $target) { $target = $devices | Where-Object { $_.Name -match '(?i)DelanCam' } | Select-Object -First 1 }
if (-not $target) {
    Write-Host 'DelanCam1 was not found among the video capture devices. Nothing to probe.'
    return
}
Write-Host ("Probing: {0}" -f $target.Name)

$group = Wait-WinRtOperation ([Windows.Media.Capture.Frames.MediaFrameSourceGroup]::FromIdAsync($target.Id)) ([Windows.Media.Capture.Frames.MediaFrameSourceGroup]) 5000
if (-not $group) { throw "No MediaFrameSourceGroup was found for device Id $($target.Id)." }

# Enumerate the supported formats once, using a throwaway capture.
$probeCapture = New-Capture $group
$probeSource = Get-FrameSource $probeCapture $group
$supported = @($probeSource.SupportedFormats)
Write-Host ("Formats offered by the device: {0}" -f $supported.Count)
try { $probeCapture.Dispose() } catch {}
$probeCapture = $null

$plan = New-Object System.Collections.Generic.List[object]
if ($All) {
    foreach ($f in $supported) { $plan.Add(@{ Label = (Format-Label $f); Format = $f }) }
    $plan.Add(@{ Label = 'DEFAULT'; Format = $null })
}
else {
    foreach ($want in $curated) {
        if ($want -eq 'DEFAULT') { $plan.Add(@{ Label = 'DEFAULT'; Format = $null }); continue }
        $match = $supported | Where-Object { (Format-Label $_) -eq $want } | Select-Object -First 1
        if ($match) { $plan.Add(@{ Label = $want; Format = $match }) }
        else { $plan.Add(@{ Label = $want; Format = 'MISSING' }) }
    }
}

Write-Host ("Capture window per format: {0}s. Each row opens the camera fresh." -f $Seconds)
Write-Host ''
Write-Host ('{0,-18} {1,-18} {2,-8} {3,-8} {4,6} {5,8} {6,8} {7,8}  {8}' -f 'Requested', 'Negotiated', 'SetFmt', 'Start', 'Frames', 'Acquired', 'Bitmaps', 'FirstMs', 'Error')
Write-Host ('-' * 120)

foreach ($item in $plan) {
    if ($item.Format -is [string] -and $item.Format -eq 'MISSING') {
        Write-Host ('{0,-18} {1,-18} {2,-8} {3,-8} {4,6} {5,8} {6,8} {7,8}  {8}' -f $item.Label, '-', '-', '-', '-', '-', '-', '-', 'format not offered by this device')
        continue
    }
    $r = Test-OneFormat $group $item.Label $item.Format $Seconds
    $setFmt = $r.SetFormat
    if ($setFmt.Length -gt 8) { $setFmt = 'FAILED' }
    $err = $r.Error
    if ($r.SetFormat -like 'FAILED:*') { if ($err -eq '') { $err = $r.SetFormat } else { $err = $r.SetFormat + ' | ' + $err } }
    Write-Host ('{0,-18} {1,-18} {2,-8} {3,-8} {4,6} {5,8} {6,8} {7,8}  {8}' -f $r.Requested, $r.Negotiated, $setFmt, $r.Start, $r.Frames, $r.Acquired, $r.Bitmaps, $r.FirstMs, $err)
    Start-Sleep -Milliseconds 500
}

Write-Host ''
Write-Host 'Reading the table: Frames > 0 means this format streams through Media Foundation on this PC.'
Write-Host 'Frames = 0 with Start = Success means the camera accepted the format but delivered nothing.'
Write-Host 'Nothing was saved to disk.'
