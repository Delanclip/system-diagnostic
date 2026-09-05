# Delanclip DelanCam1 deep collector (support-side helper)
#
# Run by Delanclip Support on a customer's PC during an agreed remote-support
# session, when the customer-facing diagnostic ZIP was not enough. It gathers
# the Windows camera-pipeline state that decides whether OpenTrack can open
# DelanCam1: device/driver/USB, Media Foundation (transforms, Frame Server,
# a per-format frame probe), DirectShow (filters, virtual cameras, Preferred,
# DoNotUse, VFW codecs), camera privacy consent, installed software, services,
# startup entries, OpenTrack/AITrack installs and configs, relevant event logs
# and security products. It writes an auto-flagged summary first.
#
# Output: a folder and ZIP under C:\temp (or -OutRoot). Nothing leaves the PC;
# the script makes no network connections and changes nothing. It briefly
# opens DelanCam1 for the frame probe and keeps only counts, never images.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File DelanCam1-DeepCollect.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File DelanCam1-DeepCollect.ps1 -SkipProbe
#   powershell -NoProfile -ExecutionPolicy Bypass -File DelanCam1-DeepCollect.ps1 -OutRoot D:\support

param(
    [string]$OutRoot = 'C:\temp',
    [int]$ProbeSeconds = 3,
    [switch]$SkipProbe
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out = Join-Path $OutRoot ("DelanCam1-DeepCollect-" + $stamp)
New-Item -ItemType Directory -Path $out -Force | Out-Null

$script:Flags = New-Object System.Collections.Generic.List[string]
$script:Notes = New-Object System.Collections.Generic.List[string]
$script:Errors = New-Object System.Collections.Generic.List[string]
$script:SignerCache = @{}

$vidPidPattern = '(?i)VID_0120.*PID_1234'
$views = @(
    @{ Name = '64-bit'; Classes = 'HKLM:\SOFTWARE\Classes'; Software = 'HKLM:\SOFTWARE' },
    @{ Name = '32-bit'; Classes = 'HKLM:\SOFTWARE\Classes\WOW6432Node'; Software = 'HKLM:\SOFTWARE\WOW6432Node' }
)

# ---------------------------------------------------------------- helpers

function Save-Text {
    param([string]$Name, $Content)
    $path = Join-Path $out $Name
    $text = ($Content | Out-String -Width 500)
    [System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))
}

function Invoke-Section {
    param([string]$Name, [scriptblock]$Body)
    Write-Host ("  {0}" -f $Name)
    try {
        $result = & $Body 2>&1
        Save-Text $Name $result
    }
    catch {
        $msg = "ERROR in ${Name}: " + $_.Exception.Message
        Save-Text $Name $msg
        $script:Errors.Add($msg)
    }
}

function Add-Flag { param([string]$Text) $script:Flags.Add($Text) }
function Add-Note { param([string]$Text) $script:Notes.Add($Text) }

function Get-RegValue {
    param([string]$Path, [string]$Name)
    try {
        $item = Get-ItemProperty -Path $Path -ErrorAction Stop
        if ($null -eq $item) { return $null }
        if ($Name -eq '(default)') { return $item.'(default)' }
        return $item.$Name
    }
    catch { return $null }
}

function Get-SignerInfo {
    param([string]$Path)
    if (-not $Path) { return 'NO PATH' }
    $clean = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
    if ($script:SignerCache.ContainsKey($clean)) { return $script:SignerCache[$clean] }
    $result = ''
    try {
        if (-not (Test-Path -LiteralPath $clean)) { $result = 'MISSING FILE' }
        else {
            $sig = Get-AuthenticodeSignature -FilePath $clean -ErrorAction Stop
            if ($sig.SignerCertificate) {
                $subject = $sig.SignerCertificate.Subject
                if ($subject -match 'CN=([^,]+)') { $result = $Matches[1] } else { $result = $subject }
                if ($sig.Status -ne 'Valid') { $result += ' [' + $sig.Status + ']' }
            }
            else { $result = 'UNSIGNED' }
        }
    }
    catch { $result = 'sig-error' }
    $script:SignerCache[$clean] = $result
    return $result
}

function Get-InprocServer {
    param([string]$ClassesRoot, [string]$Clsid)
    return (Get-RegValue (Join-Path $ClassesRoot ("CLSID\" + $Clsid + "\InprocServer32")) '(default)')
}

function Get-UserHives {
    # Returns loaded per-user hives (SID -> profile path/name). Works from SYSTEM and from a user session.
    $list = @()
    try {
        $profiles = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -ErrorAction Stop
        foreach ($p in $profiles) {
            $sid = $p.PSChildName
            if ($sid -notmatch '^S-1-5-21-') { continue }
            $imagePath = (Get-ItemProperty $p.PSPath -ErrorAction SilentlyContinue).ProfileImagePath
            $loaded = Test-Path ("Registry::HKEY_USERS\" + $sid)
            $list += [pscustomobject]@{ Sid = $sid; ProfilePath = $imagePath; User = (Split-Path $imagePath -Leaf); HiveLoaded = $loaded }
        }
    }
    catch {}
    return $list
}

function ConvertFrom-FileTimeSafe {
    param($Value)
    try { if ($Value -and [int64]$Value -gt 0) { return ([DateTime]::FromFileTime([int64]$Value)).ToString('yyyy-MM-dd HH:mm:ss') } } catch {}
    return ''
}

# ---------------------------------------------------------------- WinRT helpers (frame probe)

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
    $result = [ordered]@{ Requested = $Label; Negotiated = ''; SetFormat = ''; Start = ''; Frames = 0; Acquired = 0; FirstMs = ''; Error = '' }
    $mc = $null
    $reader = $null
    try {
        $mc = New-Capture $Group
        $source = Get-FrameSource $mc $Group
        if ($Format) {
            try { Wait-WinRtAction ($source.SetFormatAsync($Format)) 5000; $result.SetFormat = 'ok' }
            catch { $result.SetFormat = 'FAILED: ' + $_.Exception.Message }
        }
        else { $result.SetFormat = 'not requested' }
        $result.Negotiated = Format-Label $source.CurrentFormat
        $reader = Wait-WinRtOperation ($mc.CreateFrameReaderAsync($source)) ([Windows.Media.Capture.Frames.MediaFrameReader]) 8000
        $startStatus = Wait-WinRtOperation ($reader.StartAsync()) ([Windows.Media.Capture.Frames.MediaFrameReaderStartStatus]) 8000
        $result.Start = $startStatus.ToString()
        if ($startStatus.ToString() -ne 'Success') { return $result }
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
                    if ($null -ne $tsMs) { if ($tsMs -ne $lastTs) { $isNew = $true; $lastTs = $tsMs } } else { $isNew = $true }
                    if ($isNew) {
                        $result.Frames++
                        if ($result.FirstMs -eq '') { $result.FirstMs = [int]([DateTime]::UtcNow - $loopStart).TotalMilliseconds }
                    }
                }
            }
            catch { if ($result.Error -eq '') { $result.Error = 'frame loop: ' + $_.Exception.Message } }
            finally { if ($null -ne $frame) { try { $frame.Dispose() } catch {} } }
            Start-Sleep -Milliseconds 2
        }
    }
    catch { $result.Error = $_.Exception.Message }
    finally {
        if ($reader) { try { Wait-WinRtAction ($reader.StopAsync()) 5000 } catch {}; try { $reader.Dispose() } catch {} }
        if ($mc) { try { $mc.Dispose() } catch {} }
    }
    return $result
}

# ---------------------------------------------------------------- start

Write-Host ''
Write-Host 'Delanclip DelanCam1 deep collector'
Write-Host ("Output folder: {0}" -f $out)
Write-Host ''

$userHives = Get-UserHives

# 01 system -----------------------------------------------------------------
Invoke-Section '01-system.txt' {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $board = Get-CimInstance Win32_BaseBoard
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $uptime = (Get-Date) - $os.LastBootUpTime
    "Collected:            $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
    "Running as:           $([Environment]::UserDomainName)\$([Environment]::UserName)  (64-bit process: $([Environment]::Is64BitProcess), PS $($PSVersionTable.PSVersion))"
    "OS:                   $($os.Caption) $($os.Version) build $($os.BuildNumber) $($os.OSArchitecture)"
    "Install date:         $($os.InstallDate)"
    "Last boot:            $($os.LastBootUpTime)   uptime: $([int]$uptime.TotalDays) d $($uptime.Hours) h"
    "Computer:             $($cs.Manufacturer) / $($cs.Model)   RAM: $([math]::Round($cs.TotalPhysicalMemory/1GB,1)) GB"
    "Board:                $($board.Manufacturer) / $($board.Product)"
    "BIOS:                 $($bios.Manufacturer) $($bios.SMBIOSBIOSVersion)  released $($bios.ReleaseDate)"
    "CPU:                  $($cpu.Name)"
    foreach ($gpu in (Get-CimInstance Win32_VideoController)) { "GPU:                  $($gpu.Name)  driver $($gpu.DriverVersion) ($($gpu.DriverDate))" }
    $hiber = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled'
    "Fast Startup:         HiberbootEnabled = $hiber"
    $pendWU = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    $pendCBS = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    $pendRename = $null -ne (Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'PendingFileRenameOperations')
    "Pending reboot:       WindowsUpdate=$pendWU  CBS=$pendCBS  PendingFileRename=$pendRename"
    "Culture / TimeZone:   $((Get-Culture).Name) / $((Get-TimeZone).Id)"
    ''
    'Power scheme:'
    (powercfg /getactivescheme 2>&1)
    ''
    'USB selective suspend (current scheme):'
    (powercfg /q SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb50f7e36c 2>&1 | Select-String 'Power Setting Index|Current')
    ''
    'Last 15 hotfixes:'
    (Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 15 HotFixID, Description, InstalledOn | Format-Table -AutoSize)

    if ($uptime.TotalDays -ge 7) { Add-Flag ("Uptime {0} days without a real restart (Fast Startup = {1}). Ask for Restart, not Shut down." -f [int]$uptime.TotalDays, $hiber) }
    if ($pendWU -or $pendCBS -or $pendRename) { Add-Flag 'Windows reports a pending reboot (servicing not finished). Restart before judging anything.' }
    $bd = $bios.ReleaseDate
    if ($board.Product -match 'B550|X570|A520|B450|X470' -and $bd -and $bd -lt (Get-Date '2021-06-01')) { Add-Flag ("AMD 400/500-series board with BIOS from {0}: pre-AGESA 1.2.0.2 firmware had known USB dropouts; a BIOS update is worth suggesting." -f $bd.ToString('yyyy-MM-dd')) }
}

# 02 cameras / PnP -----------------------------------------------------------
Invoke-Section '02-cameras-pnp.txt' {
    $devs = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.Class -in 'Camera', 'Image' -or $_.FriendlyName -match '(?i)cam' -or $_.InstanceId -match $vidPidPattern }
    "Present camera-like devices: $(@($devs).Count)"
    ''
    $keys = 'DEVPKEY_Device_Stack', 'DEVPKEY_Device_UpperFilters', 'DEVPKEY_Device_LowerFilters', 'DEVPKEY_Device_DriverProvider', 'DEVPKEY_Device_DriverVersion', 'DEVPKEY_Device_DriverDate', 'DEVPKEY_Device_DriverInfPath', 'DEVPKEY_Device_MatchingDeviceId', 'DEVPKEY_Device_FirstInstallDate', 'DEVPKEY_Device_InstallDate', 'DEVPKEY_Device_LastArrivalDate', 'DEVPKEY_Device_LastRemovalDate', 'DEVPKEY_Device_LocationPaths', 'DEVPKEY_Device_Parent', 'DEVPKEY_Device_ProblemCode', 'DEVPKEY_Device_ConfigFlags', 'DEVPKEY_Device_BusReportedDeviceDesc', 'DEVPKEY_Device_HardwareIds', 'DEVPKEY_Device_CompatibleIds'
    foreach ($d in $devs) {
        "===== $($d.FriendlyName) ====="
        "Class: $($d.Class)   Status: $($d.Status)   Problem: $($d.Problem)   InstanceId: $($d.InstanceId)"
        foreach ($k in $keys) {
            $p = Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName $k -ErrorAction SilentlyContinue
            if ($p -and $null -ne $p.Data) {
                $val = if ($p.Data -is [array]) { $p.Data -join ' | ' } else { [string]$p.Data }
                '{0,-40} {1}' -f ($k -replace '^DEVPKEY_Device_', ''), $val
            }
        }
        if ($d.InstanceId -match $vidPidPattern) {
            $stack = (Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_Stack' -ErrorAction SilentlyContinue).Data
            $stackText = ($stack -join ' ')
            if ($stackText -and $stackText -notmatch 'usbvideo') { Add-Flag ("DelanCam1 is not bound to usbvideo (stack: {0}). Wrong driver (libusb/WinUSB/other) on the camera." -f $stackText) }
            $extra = @($stack | Where-Object { $_ -notmatch '(?i)ksthunk|usbvideo|usbccgp|WdmCompanionFilter' })
            if ($extra.Count -gt 0) { Add-Flag ("Third-party driver(s) in DelanCam1 kernel stack: {0}" -f ($extra -join ', ')) }
            $upper = (Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_UpperFilters' -ErrorAction SilentlyContinue).Data
            if ($upper) { Add-Flag ("DelanCam1 device UpperFilters present: {0}" -f ($upper -join ', ')) }
            if ($d.Status -ne 'OK') { Add-Flag ("DelanCam1 PnP status is {0} (problem {1})." -f $d.Status, $d.Problem) }
        }
        ''
    }
    if (-not ($devs | Where-Object { $_.InstanceId -match $vidPidPattern })) { Add-Flag 'DelanCam1 (VID_0120&PID_1234) is not present as a PnP device right now.' }

    'Class-level filter drivers:'
    foreach ($cls in @(@{ N = 'Camera'; G = '{ca3e7ab9-b4c3-4ae6-8251-579ef933890f}' }, @{ N = 'Image'; G = '{6bdd1fc6-810f-11d0-bec7-08002be2092f}' }, @{ N = 'Media'; G = '{4d36e96c-e325-11ce-bfc1-08002be10318}' }, @{ N = 'USB'; G = '{36fc9e60-c465-11cf-8056-444553540000}' })) {
        $k = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\' + $cls.G
        $u = Get-RegValue $k 'UpperFilters'
        $l = Get-RegValue $k 'LowerFilters'
        '{0,-8} UpperFilters={1}   LowerFilters={2}' -f $cls.N, ($u -join ','), ($l -join ',')
        if ($u -or ($l -and ($l -join ',') -notmatch '^(WdmCompanionFilter)?$')) { Add-Flag ("Class-level filter driver on {0} class: Upper={1} Lower={2}" -f $cls.N, ($u -join ','), ($l -join ',')) }
    }
}

# 03 USB ---------------------------------------------------------------------
Invoke-Section '03-usb.txt' {
    'USB host controllers and hubs (driver versions):'
    (Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceClass -eq 'USB' -and $_.DeviceName -match '(?i)host controller|root hub' } | Select-Object DeviceName, DriverVersion, DriverDate, DriverProviderName, DeviceID | Format-Table -AutoSize)
    ''
    'Present USB devices (names and IDs only):'
    (Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'USB\*' } | Sort-Object FriendlyName | Select-Object Status, Class, FriendlyName, InstanceId | Format-Table -AutoSize)
    ''
    'DelanCam1 parent chain:'
    $cam = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match $vidPidPattern } | Select-Object -First 1
    if ($cam) {
        $id = $cam.InstanceId
        $depth = 0
        while ($id -and $depth -lt 12) {
            $dev = Get-PnpDevice -InstanceId $id -ErrorAction SilentlyContinue
            $loc = (Get-PnpDeviceProperty -InstanceId $id -KeyName 'DEVPKEY_Device_LocationPaths' -ErrorAction SilentlyContinue).Data
            '{0}: [{1}] {2}  {3}' -f $depth, $dev.Class, $dev.FriendlyName, $id
            if ($loc) { '     ' + ($loc -join ' ; ') }
            if ($dev.FriendlyName -match '(?i)hub' -and $dev.Class -eq 'USB' -and $depth -gt 0 -and $dev.FriendlyName -notmatch '(?i)root hub') { Add-Note ("DelanCam1 sits behind an external/internal USB hub: {0}" -f $dev.FriendlyName) }
            $id = (Get-PnpDeviceProperty -InstanceId $id -KeyName 'DEVPKEY_Device_Parent' -ErrorAction SilentlyContinue).Data
            $depth++
        }
    }
    else { 'DelanCam1 not present.' }
}

# 04 Media Foundation --------------------------------------------------------
Invoke-Section '04-media-foundation.txt' {
    $hw = 'HKLM:\SOFTWARE\Microsoft\Windows Media Foundation\HardwareMFT'
    $encDec = Get-RegValue $hw 'EnableDecoders'
    "HardwareMFT: EnableDecoders=$encDec  EnableEncoders=$(Get-RegValue $hw 'EnableEncoders')  (default when absent: enabled)"
    $plat = 'HKLM:\SOFTWARE\Microsoft\Windows Media Foundation\Platform'
    'Platform key values:'
    (Get-ItemProperty $plat -ErrorAction SilentlyContinue | Select-Object * -ExcludeProperty PS* | Format-List)
    "FrameServer service: $((Get-Service FrameServer -ErrorAction SilentlyContinue).Status)"
    ''
    $catNames = @{
        '{d6c02d4b-6833-45b4-971a-05a4b04bab91}' = 'VIDEO_DECODER'
        '{f79eac7d-e545-4387-bdee-d647d7bde42a}' = 'VIDEO_ENCODER'
        '{12e17c21-532c-4a6e-8a1c-40825a736397}' = 'VIDEO_EFFECT'
        '{302ea3fc-aa5f-47f9-9f7a-c2188bb16302}' = 'VIDEO_PROCESSOR'
        '{9ea73fb4-ef7a-4559-8d5d-719d8f0426c7}' = 'AUDIO_DECODER'
        '{91c64bd0-f91e-4d8c-9276-db248279d975}' = 'AUDIO_ENCODER'
        '{11064c48-3648-4ed0-932e-05ce8ac811b7}' = 'AUDIO_EFFECT'
        '{059c561e-05ae-4b61-b69d-55b61ee54a7b}' = 'MULTIPLEXER'
        '{a8700a7a-939b-44c5-99d7-76226b23b3f1}' = 'DEMULTIPLEXER'
        '{90175d57-b7ea-4901-aeb3-933a8747756f}' = 'OTHER'
    }
    foreach ($v in $views) {
        "===== Media Foundation transforms ($($v.Name) view) ====="
        $tRoot = Join-Path $v.Classes 'MediaFoundation\Transforms'
        $catRoot = Join-Path $tRoot 'Categories'
        $membership = @{}
        if (Test-Path $catRoot) {
            foreach ($cat in (Get-ChildItem $catRoot -ErrorAction SilentlyContinue)) {
                $cn = $catNames[$cat.PSChildName.ToLower()]
                if (-not $cn) { $cn = $cat.PSChildName }
                foreach ($m in (Get-ChildItem $cat.PSPath -ErrorAction SilentlyContinue)) {
                    $key = $m.PSChildName.ToLower()
                    if (-not $membership.ContainsKey($key)) { $membership[$key] = @() }
                    $membership[$key] += $cn
                }
            }
        }
        $rows = @()
        foreach ($t in (Get-ChildItem $tRoot -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\{?[0-9A-Fa-f-]{36}\}?$' })) {
            $clsid = $t.PSChildName
            if ($clsid -notmatch '^\{') { $clsid = '{' + $clsid + '}' }
            $name = (Get-ItemProperty $t.PSPath -ErrorAction SilentlyContinue).'(default)'
            $srv = Get-InprocServer $v.Classes $clsid
            $signer = if ($srv) { Get-SignerInfo $srv } else { 'NO InprocServer32' }
            $cats = $membership[$clsid.ToLower()]
            if (-not $cats) { $cats = $membership[$t.PSChildName.ToLower()] }
            $rows += [pscustomobject]@{ Name = $name; Category = ($cats -join ','); Signer = $signer; CLSID = $clsid; Dll = $srv }
            if ($cats -contains 'VIDEO_DECODER' -and $signer -notmatch '(?i)^Microsoft' -and $name -match '(?i)jpeg|jpg') {
                if ($encDec -ne 0) { Add-Flag ("Non-Microsoft MJPEG decoder MFT active: '{0}' ({1}, {2} view). Known to swallow MJPEG frames; test HardwareMFT EnableDecoders=0 and restart FrameServer." -f $name, $signer, $v.Name) }
                else { Add-Note ("Non-Microsoft MJPEG decoder MFT present but hardware decoders disabled: '{0}' ({1})" -f $name, $signer) }
            }
            if ($signer -eq 'MISSING FILE') { Add-Flag ("MFT registered with missing DLL: '{0}' -> {1} ({2} view)" -f $name, $srv, $v.Name) }
        }
        ($rows | Sort-Object Category, Name | Format-Table -AutoSize)
        'Preferred MFT mappings (subtype -> MFT):'
        (Get-ItemProperty (Join-Path $tRoot 'Preferred') -ErrorAction SilentlyContinue | Select-Object * -ExcludeProperty PS* | Format-List)
        ''
    }
}

# 05 MF frame probe ----------------------------------------------------------
if ($SkipProbe) {
    Save-Text '05-mf-format-probe.txt' 'Skipped (-SkipProbe).'
}
else {
    Invoke-Section '05-mf-format-probe.txt' {
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
        "Video capture devices seen by Windows Runtime: $(@($devices).Count)"
        foreach ($d in $devices) { "  - $($d.Name)  [$($d.Id)]" }
        ''
        $target = $devices | Where-Object { $_.Id -match $vidPidPattern } | Select-Object -First 1
        if (-not $target) { $target = $devices | Where-Object { $_.Name -match '(?i)DelanCam' } | Select-Object -First 1 }
        if (-not $target) { Add-Flag 'Frame probe: DelanCam1 not visible to Windows Runtime camera enumeration.'; return 'DelanCam1 not found.' }
        $group = Wait-WinRtOperation ([Windows.Media.Capture.Frames.MediaFrameSourceGroup]::FromIdAsync($target.Id)) ([Windows.Media.Capture.Frames.MediaFrameSourceGroup]) 5000
        $probeCapture = New-Capture $group
        $probeSource = Get-FrameSource $probeCapture $group
        $supported = @($probeSource.SupportedFormats)
        try { $probeCapture.Dispose() } catch {}
        "Formats offered by the device: $($supported.Count)"
        foreach ($f in $supported) { '  - ' + (Format-Label $f) }
        ''
        $curated = @('MJPG 640x480@60', 'NV12 640x480@60', 'MJPG 640x480@30', 'NV12 640x480@30', 'YUY2 640x480@30', 'MJPG 1280x720@30', 'NV12 1280x720@30', 'DEFAULT')
        "Capture window per format: ${ProbeSeconds}s"
        '{0,-18} {1,-18} {2,-8} {3,-8} {4,6} {5,8} {6,8}  {7}' -f 'Requested', 'Negotiated', 'SetFmt', 'Start', 'Frames', 'Acquired', 'FirstMs', 'Error'
        ('-' * 110)
        $mjpgFrames = 0; $rawFrames = 0; $rowsRun = 0
        foreach ($want in $curated) {
            $fmt = $null
            if ($want -ne 'DEFAULT') {
                $fmt = $supported | Where-Object { (Format-Label $_) -eq $want } | Select-Object -First 1
                if (-not $fmt) { '{0,-18} {1}' -f $want, 'format not offered by this device'; continue }
            }
            $r = Test-OneFormat $group $want $fmt $ProbeSeconds
            $rowsRun++
            $sf = $r.SetFormat; if ($sf.Length -gt 8) { $sf = 'FAILED' }
            '{0,-18} {1,-18} {2,-8} {3,-8} {4,6} {5,8} {6,8}  {7}' -f $r.Requested, $r.Negotiated, $sf, $r.Start, $r.Frames, $r.Acquired, $r.FirstMs, $r.Error
            if ($want -like 'MJPG*') { $mjpgFrames += $r.Frames } elseif ($want -ne 'DEFAULT') { $rawFrames += $r.Frames }
            Start-Sleep -Milliseconds 400
        }
        if ($rowsRun -gt 0) {
            if ($mjpgFrames -eq 0 -and $rawFrames -gt 0) { Add-Flag 'Frame probe: MJPEG delivers 0 frames while NV12/YUY2 stream normally. MJPEG decoding in Media Foundation is broken on this PC (see 04 for MJPEG MFTs).' }
            elseif ($mjpgFrames -eq 0 -and $rawFrames -eq 0) { Add-Flag 'Frame probe: no frames in any format through Media Foundation. Camera/USB/driver level problem, or the camera is held by another app.' }
            else { Add-Note ("Frame probe: MJPEG {0} frames, raw {1} frames - Media Foundation path healthy." -f $mjpgFrames, $rawFrames) }
        }
    }
}

# 06 DirectShow --------------------------------------------------------------
Invoke-Section '06-directshow.txt' {
    $coreClsids = @(
        @{ N = 'KS proxy (ksproxy.ax)'; C = '{17CCA71B-ECD7-11D0-B908-00A0C9223196}' },
        @{ N = 'SampleGrabber (qedit.dll)'; C = '{C1F400A0-3F08-11d3-9F0B-006008039E37}' },
        @{ N = 'Null Renderer (qedit.dll)'; C = '{C1F400A4-3F08-11d3-9F0B-006008039E37}' },
        @{ N = 'FilterGraph (quartz.dll)'; C = '{e436ebb3-524f-11ce-9f53-0020af0ba770}' },
        @{ N = 'MJPEG Decompressor (quartz.dll)'; C = '{301056D0-6DFF-11d2-9EEB-006008039E37}' },
        @{ N = 'AVI Decompressor (quartz.dll)'; C = '{CF49D4E0-1115-11CE-B03A-0020AF0BA770}' },
        @{ N = 'Color Space Converter (quartz.dll)'; C = '{1643E180-90F5-11CE-97D5-00AA0055595A}' },
        @{ N = 'CaptureGraphBuilder2 (qcap.dll)'; C = '{BF87B6E1-8C27-11d0-B3F0-00AA003761C5}' },
        @{ N = 'Smart Tee (qcap.dll)'; C = '{CC58E280-8AA1-11d1-B3F1-00AA003761C5}' },
        @{ N = 'SystemDeviceEnum (devenum.dll)'; C = '{62BE5D10-60EB-11d0-BD3B-00A0C911CE86}' }
    )
    $expectedVfw = @{ 'vidc.cvid' = 'iccvid.dll'; 'vidc.i420' = 'iyuv_32.dll'; 'vidc.iyuv' = 'iyuv_32.dll'; 'vidc.mrle' = 'msrle32.dll'; 'vidc.msvc' = 'msvidc32.dll'; 'vidc.uyvy' = 'msyuv.dll'; 'vidc.yuy2' = 'msyuv.dll'; 'vidc.yvu9' = 'tsbyuv.dll'; 'vidc.yvyu' = 'msyuv.dll' }

    foreach ($v in $views) {
        "################ DirectShow ($($v.Name) view) ################"
        ''
        '--- Core component registrations ---'
        foreach ($c in $coreClsids) {
            $srv = Get-InprocServer $v.Classes $c.C
            $treatAs = Get-RegValue (Join-Path $v.Classes ("CLSID\" + $c.C + "\TreatAs")) '(default)'
            $state = if ($srv) { Get-SignerInfo $srv } else { 'NO REGISTRATION' }
            '{0,-38} {1,-45} {2}{3}' -f $c.N, $srv, $state, $(if ($treatAs) { "  TreatAs=$treatAs" } else { '' })
            if (-not $srv) { Add-Flag ("DirectShow core component not registered ({0} view): {1}. Fix: regsvr32 of the named DLL." -f $v.Name, $c.N) }
            elseif ($state -eq 'MISSING FILE') { Add-Flag ("DirectShow core component DLL missing ({0} view): {1} -> {2}" -f $v.Name, $c.N, $srv) }
            if ($treatAs) { Add-Flag ("TreatAs redirection on {0} ({1} view) -> {2}. Codec-pack hijack; remove the TreatAs key." -f $c.N, $v.Name, $treatAs) }
        }
        ''
        '--- Video input device registrations (software/virtual cameras; real USB cameras are never listed here) ---'
        $vidInst = Join-Path $v.Classes 'CLSID\{860BB310-5D01-11d0-BD3B-00A0C911CE86}\Instance'
        $ghosts = @(Get-ChildItem $vidInst -ErrorAction SilentlyContinue)
        if ($ghosts.Count -eq 0) { '(none)' }
        foreach ($g in $ghosts) {
            $p = Get-ItemProperty $g.PSPath -ErrorAction SilentlyContinue
            $clsid = if ($p.CLSID) { $p.CLSID } else { $g.PSChildName }
            $srv = Get-InprocServer $v.Classes $clsid
            $state = if ($srv) { Get-SignerInfo $srv } else { 'NO InprocServer32' }
            '{0,-40} {1,-40} {2}  {3}' -f $p.FriendlyName, $clsid, $srv, $state
            Add-Flag ("Virtual camera registered ({0} view): '{1}' -> {2} [{3}]. Appears in OpenTrack's camera list; remove if the app is gone." -f $v.Name, $p.FriendlyName, $srv, $state)
        }
        ''
        '--- DirectShow filters that are not Microsoft-signed, or whose DLL is missing ---'
        $filtInst = Join-Path $v.Classes 'CLSID\{083863F1-70DE-11d0-BD40-00A0C911CE86}\Instance'
        $allFilters = @(Get-ChildItem $filtInst -ErrorAction SilentlyContinue)
        "Total registered filters: $($allFilters.Count)"
        $suspicious = 0
        foreach ($f in $allFilters) {
            $p = Get-ItemProperty $f.PSPath -ErrorAction SilentlyContinue
            $clsid = if ($p.CLSID) { $p.CLSID } else { $f.PSChildName }
            $srv = Get-InprocServer $v.Classes $clsid
            $state = if ($srv) { Get-SignerInfo $srv } else { 'NO InprocServer32' }
            $merit = ''
            try { if ($p.FilterData -and $p.FilterData.Length -ge 8) { $merit = '0x{0:X8}' -f [BitConverter]::ToUInt32($p.FilterData, 4) } } catch {}
            $isMs = ($state -match '(?i)^Microsoft')
            if (-not $isMs -or $state -eq 'MISSING FILE') {
                $suspicious++
                '{0,-45} merit={1,-10} {2,-40} {3}  {4}' -f $p.FriendlyName, $merit, $clsid, $srv, $state
                if ($state -eq 'MISSING FILE' -or $state -eq 'NO InprocServer32') {
                    if ($p.FriendlyName -notmatch '(?i)^(Line 21 Decoder|Overlay Mixer|Overlay Mixer2|VBI Surface Allocator)$') { Add-Flag ("Dead DirectShow filter registration ({0} view): '{1}' -> {2} [{3}]. Delete Instance entry and CLSID key (backup first)." -f $v.Name, $p.FriendlyName, $srv, $state) }
                }
                elseif ($p.FriendlyName -match '(?i)lav|ffdshow|xvid|divx|k-lite|cccp|shark|haali|coreavc|mpc|nikon|streamlabs|obs|manycam|xsplit|snap|broadcast|virtual') { Add-Flag ("Third-party DirectShow filter ({0} view): '{1}' [{2}] merit {3}. Codec packs/virtual cameras hijack MJPEG/YUY2 rendering." -f $v.Name, $p.FriendlyName, $state, $merit) }
                else { Add-Note ("Non-Microsoft DirectShow filter ({0} view): '{1}' [{2}]" -f $v.Name, $p.FriendlyName, $state) }
            }
        }
        if ($suspicious -eq 0) { '(all registered filters are Microsoft-signed with existing files)' }
        ''
        '--- Preferred decoders (HKLM\SOFTWARE\Microsoft\DirectShow\Preferred) ---'
        $pref = Get-ItemProperty (Join-Path $v.Software 'Microsoft\DirectShow\Preferred') -ErrorAction SilentlyContinue
        if ($pref) {
            foreach ($prop in ($pref.PSObject.Properties | Where-Object { $_.Name -match '^\{' })) {
                $target = [string]$prop.Value
                $tName = Get-RegValue (Join-Path $v.Classes ("CLSID\" + $target)) '(default)'
                $tSrv = Get-InprocServer $v.Classes $target
                $tState = if ($tSrv) { Get-SignerInfo $tSrv } else { 'NO REGISTRATION' }
                $label = $prop.Name
                if ($label -match '^\{47504A4D') { $label += ' (MJPG)' } elseif ($label -match '^\{32595559') { $label += ' (YUY2)' } elseif ($label -match '^\{3231564E') { $label += ' (NV12)' }
                '{0,-48} -> {1,-40} {2,-32} {3}' -f $label, $target, $tName, $tState
                if ($tState -eq 'NO REGISTRATION' -or $tState -eq 'MISSING FILE') { Add-Flag ("DirectShow Preferred entry ({0} view) {1} points to unusable decoder {2} [{3}]. Delete the value." -f $v.Name, $label, $target, $tState) }
                elseif ($label -match 'MJPG|YUY2|NV12' -and $tState -notmatch '(?i)^Microsoft') { Add-Flag ("DirectShow Preferred entry ({0} view) {1} -> non-Microsoft decoder '{2}' [{3}]." -f $v.Name, $label, $tName, $tState) }
            }
        }
        else { '(key absent)' }
        ''
        '--- DoNotUse (HKLM\SOFTWARE\Microsoft\DirectShow\DoNotUse) ---'
        $dnu = Get-ItemProperty (Join-Path $v.Software 'Microsoft\DirectShow\DoNotUse') -ErrorAction SilentlyContinue
        $dnuVals = @()
        if ($dnu) { $dnuVals = @($dnu.PSObject.Properties | Where-Object { $_.Name -match '^\{' }) }
        if ($dnuVals.Count -eq 0) { '(empty)' }
        foreach ($d in $dnuVals) {
            $dn = Get-RegValue (Join-Path $v.Classes ("CLSID\" + $d.Name)) '(default)'
            '{0}  {1}' -f $d.Name, $dn
            Add-Flag ("DirectShow DoNotUse blocks filter {0} ({1}) in {2} view. Intelligent connect skips it." -f $d.Name, $dn, $v.Name)
        }
        ''
        '--- VFW codecs (Drivers32) ---'
        $d32 = Get-ItemProperty (Join-Path $v.Software 'Microsoft\Windows NT\CurrentVersion\Drivers32') -ErrorAction SilentlyContinue
        $present = @{}
        if ($d32) { foreach ($prop in ($d32.PSObject.Properties | Where-Object { $_.Name -match '^(vidc|msacm|VIDC|MSACM)\.' })) { $present[$prop.Name.ToLower()] = [string]$prop.Value; '{0,-14} {1}' -f $prop.Name, $prop.Value } }
        $missing = @($expectedVfw.Keys | Where-Object { -not $present.ContainsKey($_) } | Sort-Object)
        if ($missing.Count -gt 0) { Add-Flag ("VFW codec registrations missing in {0} Drivers32: {1}. 64-bit DirectShow apps need vidc.yuy2 (msyuv.dll) to convert camera YUY2 to RGB. Restore with reg add." -f $v.Name, ($missing -join ', ')) }
        foreach ($k in $present.Keys) { if ($k -like 'vidc.*' -and $expectedVfw.ContainsKey($k) -and $present[$k] -ne $expectedVfw[$k]) { Add-Flag ("VFW codec {0} points to '{1}' instead of stock '{2}' ({3} view)." -f $k, $present[$k], $expectedVfw[$k], $v.Name) } }
        ''
    }
    '--- Per-user DirectShow device cache (devenum) ---'
    foreach ($h in $userHives) {
        if (-not $h.HiveLoaded) { continue }
        $cache = "Registry::HKEY_USERS\$($h.Sid)\Software\Microsoft\ActiveMovie\devenum"
        if (Test-Path $cache) {
            $n = @(Get-ChildItem $cache -Recurse -ErrorAction SilentlyContinue).Count
            '{0,-20} cache present, {1} cached entries (delete the key to force re-enumeration)' -f $h.User, $n
        }
        else { '{0,-20} no cache' -f $h.User }
    }
}

# 07 privacy / consent / policies -------------------------------------------
Invoke-Section '07-privacy-policies.txt' {
    $csm = 'SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam'
    "HKLM webcam Value:              $(Get-RegValue ("HKLM:\" + $csm) 'Value')"
    "HKLM webcam\NonPackaged Value:  $(Get-RegValue ("HKLM:\" + $csm + "\NonPackaged") 'Value')"
    if ((Get-RegValue ("HKLM:\" + $csm) 'Value') -eq 'Deny') { Add-Flag 'Machine-wide camera consent is Deny (HKLM). Every app is blocked.' }
    if ((Get-RegValue ("HKLM:\" + $csm + "\NonPackaged") 'Value') -eq 'Deny') { Add-Flag 'Machine-wide consent for desktop apps (HKLM NonPackaged) is Deny. OpenTrack/AITrack blocked, Windows Camera still works.' }
    ''
    foreach ($h in $userHives) {
        if (-not $h.HiveLoaded) { "User $($h.User): hive not loaded (not logged on)"; continue }
        $base = "Registry::HKEY_USERS\$($h.Sid)\$csm"
        $uv = Get-RegValue $base 'Value'
        $npv = Get-RegValue ($base + '\NonPackaged') 'Value'
        "===== User $($h.User) ====="
        "webcam Value: $uv    NonPackaged Value: $npv"
        if ($uv -eq 'Deny') { Add-Flag ("User {0}: camera consent Deny (Settings > Privacy > Camera off)." -f $h.User) }
        if ($npv -eq 'Deny') { Add-Flag ("User {0}: desktop apps camera consent Deny. OpenTrack/AITrack blocked, Windows Camera works." -f $h.User) }
        'Per-app records (packaged and desktop), with last use:'
        foreach ($k in (Get-ChildItem $base -Recurse -ErrorAction SilentlyContinue)) {
            $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
            $name = $k.PSPath -replace '.*\\webcam\\', ''
            $name = $name -replace [regex]::Escape($h.ProfilePath), '%USERPROFILE%'
            $start = ConvertFrom-FileTimeSafe $p.LastUsedTimeStart
            $stop = ConvertFrom-FileTimeSafe $p.LastUsedTimeStop
            $inUse = ''
            if ($p.LastUsedTimeStart -and (-not $p.LastUsedTimeStop -or [int64]$p.LastUsedTimeStop -eq 0)) { $inUse = '  <-- ACTIVE SESSION'; Add-Flag ("Camera currently held by: {0} (user {1})" -f $name, $h.User) }
            '{0,-90} value={1,-6} start={2,-19} stop={3}{4}' -f $name, $p.Value, $start, $stop, $inUse
        }
        ''
    }
    'Policies:'
    $polCam = Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsAccessCamera'
    "AppPrivacy LetAppsAccessCamera:            $polCam"
    if ($polCam -eq 2) { Add-Flag 'Group Policy LetAppsAccessCamera = 2 (force deny).' }
    $allowCam = Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Camera' 'AllowCamera'
    "Camera policy AllowCamera:                 $allowCam"
    if ($allowCam -eq 0) { Add-Flag 'Policy AllowCamera = 0 disables the camera.' }
    $soc = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' 'SearchOrderConfig'
    $wuPol = Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'ExcludeWUDriversInQualityUpdate'
    "DriverSearching SearchOrderConfig:         $soc   (0 = never search Windows Update for drivers)"
    "WU policy ExcludeWUDriversInQualityUpdate: $wuPol"
    if ($soc -eq 0 -or $wuPol -eq 1) { Add-Note 'Driver updates from Windows Update are blocked by policy/tweak. Sign of a debloat/tweak tool; other registry areas may be modified too.' }
    $devInst = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions' -ErrorAction SilentlyContinue
    if ($devInst) { 'Device installation restrictions policy present:'; ($devInst | Select-Object * -ExcludeProperty PS* | Format-List); Add-Flag 'Device installation restriction policy present (can block new USB devices).' }
    "Webcam disabled by policy (HKLM\...\Policies\...\Webcam):  $(Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Webcam' 'DisableWebcam')"
}

# 08 installed software ------------------------------------------------------
Invoke-Section '08-installed-software.txt' {
    $paths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
    foreach ($h in $userHives) { if ($h.HiveLoaded) { $paths += "Registry::HKEY_USERS\$($h.Sid)\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" } }
    $apps = Get-ItemProperty $paths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } | Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, InstallLocation | Sort-Object DisplayName -Unique
    $hot = '(?i)camera|webcam|\bcam\b|codec|k-lite|ffdshow|\blav\b|shark007|cccp|nikon|streamlabs|\bobs\b|manycam|xsplit|snap camera|broadcast|imyfone|magicmic|voicemod|virtual|opentrack|aitrack|facetrack|tobii|trackir|eyeware|logitech|g hub|razer|synapse|cortex|corsair|icue|msi center|dragon center|afterburner|rivatuner|nahimic|sonic studio|oculus|steamvr|discord|zoom|teams|skype|cl-eye|code laboratories|libusb|zadig|driver booster|ccleaner|advanced systemcare|iobit|glary|wise care|tweak|shutup|debloat|winutil|kaspersky|eset|bitdefender|norton|mcafee|avast|avg |trend micro|malwarebytes|hp wolf'
    "Installed programs: $(@($apps).Count) total. Highlights first (camera/codec/tracking/overlay/security/tweak related):"
    ''
    $hl = @($apps | Where-Object { $_.DisplayName -match $hot -or $_.Publisher -match $hot })
    ($hl | Format-Table DisplayName, DisplayVersion, Publisher, InstallDate -AutoSize)
    foreach ($a in $hl) {
        if ($a.DisplayName -match '(?i)k-lite|ffdshow|shark007|cccp|codec pack|lav filters') { Add-Flag ("Codec pack installed: {0} {1}. Prime suspect for DirectShow MJPEG/YUY2 rendering failures." -f $a.DisplayName, $a.DisplayVersion) }
        if ($a.DisplayName -match '(?i)nikon webcam|streamlabs|manycam|xsplit|snap camera|nvidia broadcast|imyfone|magicmic|voicemod|virtual camera') { Add-Note ("Virtual-camera/codec-bundling software installed: {0} {1}" -f $a.DisplayName, $a.DisplayVersion) }
        if ($a.DisplayName -match '(?i)nahimic|sonic studio|afterburner|rivatuner|razer cortex') { Add-Note ("Process-injecting software installed (known to break camera apps): {0} {1}" -f $a.DisplayName, $a.DisplayVersion) }
        if ($a.DisplayName -match '(?i)driver booster|ccleaner|advanced systemcare|iobit|glary|wise care|shutup|debloat|winutil') { Add-Flag ("System cleaner/tweak tool installed: {0}. Explains wiped registrations (VFW, DirectShow) when found." -f $a.DisplayName) }
        if ($a.DisplayName -match '(?i)kaspersky|eset|bitdefender|norton|mcafee|avast|avg |trend micro|hp wolf') { Add-Flag ("Security suite with possible webcam protection: {0}. Check its webcam/privacy module for OpenTrack." -f $a.DisplayName) }
        if ($a.DisplayName -match '(?i)cl-eye|code laboratories|libusb|zadig') { Add-Flag ("PS3 Eye / libusb tooling installed: {0}. Ask whether the PS3 Eye driver procedure was ever applied to DelanCam1." -f $a.DisplayName) }
    }
    ''
    'Full list:'
    ($apps | Format-Table DisplayName, DisplayVersion, Publisher, InstallDate -AutoSize)
}

# 09 processes / services / startup ------------------------------------------
Invoke-Section '09-processes-services-startup.txt' {
    'Running processes (non-Windows paths first):'
    $procs = Get-Process -ErrorAction SilentlyContinue | Select-Object Name, Id, Path, Company
    ($procs | Where-Object { $_.Path -and $_.Path -notmatch '(?i)\\Windows\\' } | Sort-Object Name | Format-Table Name, Id, Company, Path -AutoSize)
    'Windows-path and system processes:'
    ($procs | Where-Object { -not $_.Path -or $_.Path -match '(?i)\\Windows\\' } | Sort-Object Name | Format-Table Name, Id -AutoSize)
    $inj = @($procs | Where-Object { $_.Name -match '(?i)^(NVIDIA Overlay|nvcontainer|NahimicService|A-Volute|RTSS|MSIAfterburner|RzCortex|Cortex|CorsairService|iCUE|lghub|LogiOverlay|Discord|obs64|Streamlabs|XSplit|ManyCam|Snap Camera|NVIDIA Broadcast)' })
    if ($inj.Count -gt 0) { Add-Note ("Overlay/injection-type processes running: {0}" -f (($inj | Select-Object -ExpandProperty Name -Unique) -join ', ')) }
    ''
    'Services from non-Microsoft paths:'
    (Get-CimInstance Win32_Service | Where-Object { $_.PathName -and $_.PathName -notmatch '(?i)\\Windows\\|Microsoft|Windows Defender' } | Sort-Object State, DisplayName | Select-Object State, StartMode, Name, DisplayName, PathName | Format-Table -AutoSize)
    ''
    'Startup entries (Run/RunOnce, machine and loaded users, Startup folders):'
    $runKeys = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run')
    foreach ($h in $userHives) { if ($h.HiveLoaded) { $runKeys += "Registry::HKEY_USERS\$($h.Sid)\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" } }
    foreach ($rk in $runKeys) {
        $p = Get-ItemProperty $rk -ErrorAction SilentlyContinue
        if ($p) { "[$rk]"; foreach ($prop in ($p.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' })) { '  {0,-30} {1}' -f $prop.Name, $prop.Value } }
    }
    $startupDirs = @("$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup")
    foreach ($h in $userHives) { $startupDirs += (Join-Path $h.ProfilePath 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup') }
    foreach ($sd in $startupDirs) { if (Test-Path $sd) { "[$sd]"; Get-ChildItem $sd -ErrorAction SilentlyContinue | ForEach-Object { '  ' + $_.Name } } }
}

# 10 OpenTrack / AITrack -----------------------------------------------------
Invoke-Section '10-opentrack.txt' {
    $candidates = @("$env:ProgramFiles\opentrack", "${env:ProgramFiles(x86)}\opentrack")
    $installs = @()
    foreach ($c in $candidates) { if (Test-Path (Join-Path $c 'opentrack.exe')) { $installs += $c } }
    "OpenTrack installations found: $($installs.Count)"
    foreach ($i in $installs) {
        $exe = Get-Item (Join-Path $i 'opentrack.exe')
        $bits = 'unknown'
        try {
            $b = [IO.File]::ReadAllBytes($exe.FullName); $o = [BitConverter]::ToInt32($b, 60); $m = [BitConverter]::ToUInt16($b, $o + 4)
            $bits = if ($m -eq 0x8664) { 'x64' } elseif ($m -eq 0x14c) { 'x86' } else { ('0x{0:X}' -f $m) }
        } catch {}
        "===== $i ====="
        "opentrack.exe: {0} bytes, modified {1}, arch {2}, file version '{3}'" -f $exe.Length, $exe.LastWriteTime, $bits, $exe.VersionInfo.FileVersion
        $mods = Get-ChildItem (Join-Path $i 'modules') -Filter '*.dll' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
        "modules ($(@($mods).Count)): " + (($mods | Where-Object { $_ -match '(?i)video|tracker-pt|opencv' }) -join ', ')
        $cv = Get-ChildItem $i -Recurse -Filter 'opencv*.dll' -ErrorAction SilentlyContinue | Select-Object -First 3
        foreach ($c in $cv) { "  opencv: {0} ({1})" -f $c.Name, $c.VersionInfo.FileVersion }
        if (Test-Path (Join-Path $i 'portable.txt')) { '  portable.txt present: settings stored next to the exe' }
    }
    if ($installs.Count -gt 1) { Add-Note ("Two OpenTrack installations present: {0}" -f ($installs -join ' ; ')) }
    if ($installs.Count -eq 0) { Add-Note 'OpenTrack not found in Program Files locations.' }
    ''
    'OpenTrack configuration folders (Documents\opentrack-2.3, also OneDrive-redirected and legacy AppData):'
    $cfgOut = Join-Path $out 'opentrack-configs'
    foreach ($h in $userHives) {
        $dirs = @((Join-Path $h.ProfilePath 'Documents\opentrack-2.3'), (Join-Path $h.ProfilePath 'OneDrive\Documents\opentrack-2.3'), (Join-Path $h.ProfilePath 'AppData\Roaming\opentrack-2.3'))
        foreach ($d in $dirs) {
            if (-not (Test-Path $d)) { continue }
            "[$($h.User)] $d"
            $dest = Join-Path $cfgOut $h.User
            New-Item -ItemType Directory -Path $dest -Force | Out-Null
            foreach ($ini in (Get-ChildItem $d -Filter '*.ini' -ErrorAction SilentlyContinue)) {
                Copy-Item $ini.FullName (Join-Path $dest $ini.Name) -Force -ErrorAction SilentlyContinue
                '  {0}  ({1} bytes, {2})' -f $ini.Name, $ini.Length, $ini.LastWriteTime
                $content = Get-Content $ini.FullName -ErrorAction SilentlyContinue
                $inPt = $false
                foreach ($line in $content) {
                    if ($line -match '^\[(.+)\]') { $inPt = ($Matches[1] -eq 'tracker-pt'); continue }
                    if ($inPt -and $line -match '^(camera-name|camera-fps|camera-res|force-fps|camera-width|camera-height|use-mjpeg|camera-mjpeg)\s*=') { '      [tracker-pt] ' + $line }
                }
            }
        }
    }
    ''
    foreach ($a in @("$env:ProgramFiles\aitrack*", "${env:ProgramFiles(x86)}\aitrack*", "$env:ProgramFiles\FaceTrackNoIR*", "${env:ProgramFiles(x86)}\FaceTrackNoIR*")) {
        foreach ($p in (Get-Item $a -ErrorAction SilentlyContinue)) { "Other tracking software: $($p.FullName)" }
    }
}

# 11 event logs --------------------------------------------------------------
Invoke-Section '11-event-logs.txt' {
    $since = (Get-Date).AddDays(-7)
    'System log, last 7 days, warnings/errors matching USB/PnP/camera/FrameServer (max 150):'
    $sys = Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $since; Level = 1, 2, 3 } -ErrorAction SilentlyContinue |
        Where-Object { $_.ProviderName -match '(?i)usb|kernel-pnp|xhci|hub|camera|frameserver|userpnp|driverframeworks' -or $_.Message -match '(?i)VID_0120|DelanCam|camera|usbvideo' } |
        Select-Object -First 150
    foreach ($e in $sys) { '{0:yyyy-MM-dd HH:mm:ss}  {1,-5} {2,-40} id={3}  {4}' -f $e.TimeCreated, $e.LevelDisplayName, $e.ProviderName, $e.Id, (($e.Message -split "`r?`n")[0]) }
    $camEvents = @($sys | Where-Object { $_.Message -match '(?i)VID_0120' })
    if ($camEvents.Count -gt 0) { Add-Note ("{0} System-log warning/error events mention DelanCam1 in the last 7 days (see 11)." -f $camEvents.Count) }
    ''
    'Kernel-PnP events for DelanCam1 (all levels, last 7 days, max 60):'
    $pnp = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-PnP'; StartTime = $since } -ErrorAction SilentlyContinue | Where-Object { $_.Message -match '(?i)VID_0120' } | Select-Object -First 60
    foreach ($e in $pnp) { '{0:yyyy-MM-dd HH:mm:ss}  id={1}  {2}' -f $e.TimeCreated, $e.Id, (($e.Message -split "`r?`n")[0]) }
    ''
    'Application log, last 7 days: crashes/hangs/WER and camera-app messages (max 100):'
    $app = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $since; Level = 1, 2, 3 } -ErrorAction SilentlyContinue |
        Where-Object { $_.ProviderName -match '(?i)Application Error|Application Hang|Windows Error Reporting|\.NET Runtime' -or $_.Message -match '(?i)opentrack|aitrack|frameserver|opencv|camera' } |
        Select-Object -First 100
    foreach ($e in $app) { '{0:yyyy-MM-dd HH:mm:ss}  {1,-5} {2,-28} id={3}  {4}' -f $e.TimeCreated, $e.LevelDisplayName, $e.ProviderName, $e.Id, ((($e.Message -split "`r?`n") | Select-Object -First 3) -join ' | ') }
    $crashes = @($app | Where-Object { $_.ProviderName -match 'Application Error|Application Hang' -and $_.Message -match '(?i)opentrack|aitrack' })
    if ($crashes.Count -gt 0) { Add-Flag ("{0} crash/hang events for OpenTrack/AITrack in the last 7 days (see 11 for faulting module)." -f $crashes.Count) }
}

# 12 security ----------------------------------------------------------------
Invoke-Section '12-security.txt' {
    'Security Center products:'
    (Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue | Select-Object displayName, productState, pathToSignedProductExe | Format-Table -AutoSize)
    'Defender:'
    (Get-MpComputerStatus -ErrorAction SilentlyContinue | Select-Object AMServiceEnabled, AntivirusEnabled, RealTimeProtectionEnabled, IsTamperProtected, AntivirusSignatureVersion | Format-List)
    'Known webcam-protection services present:'
    $svc = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)^(ekrn|avp|vsserv|bdredline|NortonSecurity|NS|mfe|McAfee|avast|AVG|klif|TmCCSF|Amsp|HPWolf|SophosNtp|WRSVC)' -or $_.DisplayName -match '(?i)eset|kaspersky|bitdefender|norton|mcafee|avast|avg |trend micro|sophos|webroot|hp wolf' }
    if ($svc) { ($svc | Select-Object Status, Name, DisplayName | Format-Table -AutoSize); Add-Flag ("Third-party security product services present: {0}. Check webcam protection settings." -f (($svc | Select-Object -ExpandProperty DisplayName -Unique) -join ', ')) } else { '(none)' }
    'Exploit protection / ASR (informational):'
    (Get-MpPreference -ErrorAction SilentlyContinue | Select-Object AttackSurfaceReductionRules_Ids, EnableControlledFolderAccess | Format-List)
}

# 13 setupapi excerpts -------------------------------------------------------
Invoke-Section '13-setupapi-delancam.txt' {
    $log = Join-Path $env:windir 'INF\setupapi.dev.log'
    if (-not (Test-Path $log)) { return 'setupapi.dev.log not found.' }
    $lines = Get-Content $log -ErrorAction SilentlyContinue
    $hits = New-Object System.Collections.Generic.List[string]
    $sectionHeader = ''
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ($l -match '^>>>  \[') { $sectionHeader = $l; $sectionStart = if ($i + 1 -lt $lines.Count) { $lines[$i + 1] } else { '' }; continue }
        if ($l -match '(?i)VID_0120.*PID_1234' -and $sectionHeader) {
            if (-not $hits.Contains($sectionHeader)) { $hits.Add(''); $hits.Add($sectionHeader); $hits.Add($sectionStart) }
        }
        if ($l -match '^<<<  \[Exit status' -and $hits.Count -gt 0 -and $hits[$hits.Count - 1] -notmatch 'Exit status' -and $sectionHeader -and $hits.Contains($sectionHeader)) { $hits.Add($l) }
        if ($l -match '(?i)VID_0120.*PID_1234|Class GUID of device changed|libusb|WinUSB|Zadig|libusbK' -and $sectionHeader -and $hits.Contains($sectionHeader) -and $l -notmatch '^>>>') { $hits.Add('    ' + $l.Trim()) }
    }
    "Sections in setupapi.dev.log touching DelanCam1 (header, start time, notable lines, exit status):"
    $hits | Select-Object -Last 400
    $manual = @($hits | Where-Object { $_ -match 'DiShowUpdateDevice|Update Driver Software Wizard|Device Uninstall' })
    if ($manual.Count -gt 0) { Add-Note ("setupapi shows manual driver actions on DelanCam1 (Update Driver wizard / uninstall): {0} lines - ask the customer what was installed." -f $manual.Count) }
    if ($hits | Where-Object { $_ -match '(?i)libusb|WinUSB|Zadig' }) { Add-Flag 'setupapi mentions libusb/WinUSB/Zadig for DelanCam1: the PS3 Eye driver procedure was applied to this camera.' }
    if ($hits | Where-Object { $_ -match 'Class GUID of device changed' }) { Add-Note 'setupapi: the device class of DelanCam1 changed at some point (a non-camera driver was bound before).' }
}

# 00 summary -----------------------------------------------------------------
$summary = New-Object System.Collections.Generic.List[string]
$summary.Add('Delanclip DelanCam1 deep collector - SUMMARY')
$summary.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')   Folder: $out")
$summary.Add('')
$summary.Add("FLAGS ($($script:Flags.Count)) - things that explain or block camera access, most specific first:")
if ($script:Flags.Count -eq 0) { $summary.Add('  (none - camera pipeline registrations look stock; look at 05 probe rows and 11 event logs)') }
foreach ($f in $script:Flags) { $summary.Add('  ! ' + $f) }
$summary.Add('')
$summary.Add("NOTES ($($script:Notes.Count)) - context, not proof:")
foreach ($n in $script:Notes) { $summary.Add('  - ' + $n) }
$summary.Add('')
if ($script:Errors.Count -gt 0) { $summary.Add('COLLECTION ERRORS:'); foreach ($e in $script:Errors) { $summary.Add('  x ' + $e) }; $summary.Add('') }
$summary.Add('FILES:')
$summary.Add('  01-system.txt                  OS/BIOS/board/GPU, uptime, Fast Startup, pending reboot, hotfixes, USB suspend')
$summary.Add('  02-cameras-pnp.txt             camera devices, driver stack, device and class filter drivers')
$summary.Add('  03-usb.txt                     USB controllers/hubs/devices, DelanCam1 parent chain')
$summary.Add('  04-media-foundation.txt        HardwareMFT, Frame Server, all MFTs with signer and category, Preferred MFTs')
$summary.Add('  05-mf-format-probe.txt         frames per format through Media Foundation (MJPG vs NV12/YUY2)')
$summary.Add('  06-directshow.txt              core filters, virtual cameras, third-party/dead filters, Preferred, DoNotUse, VFW codecs, devenum cache')
$summary.Add('  07-privacy-policies.txt        camera consent (machine + users, per app, active sessions), policies, driver-update tweaks')
$summary.Add('  08-installed-software.txt      installed programs with camera/codec/tracking/tweak highlights')
$summary.Add('  09-processes-services-startup  processes with paths, non-Microsoft services, Run keys, Startup folders')
$summary.Add('  10-opentrack.txt               OpenTrack installs (arch, OpenCV), config folders, tracker-pt camera settings; opentrack-configs\ holds the ini copies')
$summary.Add('  11-event-logs.txt              System/Application events: USB, PnP, crashes, camera apps')
$summary.Add('  12-security.txt                AV products, Defender, webcam-protection suites')
$summary.Add('  13-setupapi-delancam.txt       driver install history of DelanCam1')
Save-Text '00-SUMMARY.txt' $summary

$zip = $out + '.zip'
try { Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -Force; $zipNote = "ZIP: $zip" } catch { $zipNote = 'ZIP failed: ' + $_.Exception.Message }

Write-Host ''
foreach ($line in $summary) { Write-Host $line }
Write-Host ''
Write-Host $zipNote
Write-Host 'Done.'
