@echo off
setlocal
title Delanclip DelanCam1 Fix Tool
set "DELAN_SCRIPT=%~f0"
set "DELAN_MODE=check"
set "DELAN_SKIPPROBE=0"
set "DELAN_ELEVATED=0"

:parse_args
if "%~1"=="" goto args_done
if /i "%~1"=="/apply" set "DELAN_MODE=apply"
if /i "%~1"=="/check" set "DELAN_MODE=check"
if /i "%~1"=="/skipprobe" set "DELAN_SKIPPROBE=1"
if /i "%~1"=="/elevated" set "DELAN_ELEVATED=1"
shift
goto parse_args
:args_done

rem A 32-bit cmd.exe on 64-bit Windows would start the 32-bit PowerShell, whose
rem registry view is redirected. Sysnative only exists for 32-bit processes and
rem always points at the native 64-bit PowerShell.
set "DELAN_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "DELAN_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"

if "%DELAN_ELEVATED%"=="1" goto run

echo ============================================================
echo        Delanclip DelanCam1 Fix Tool
echo ============================================================
echo.
echo This tool checks the Windows video pipeline that OpenTrack, AITrack
echo and similar camera software depend on, and repairs the known damage
echo that stops them from opening DelanCam1 while Windows Camera still works:
echo.
echo   A. a vendor hardware MJPEG decoder intercepting Media Foundation
echo   B. missing 64-bit or 32-bit VFW codec registrations (Drivers32)
echo   C. dead DirectShow filter and virtual-camera registrations
echo   D. DirectShow decoder preferences pointing at removed codecs
echo   E. camera privacy consent, Frame Server service and restart state
echo.
echo It first only CHECKS and prints what it found. Nothing is changed
echo unless you type APPLY when asked, or start it with the /apply switch.
echo.
echo Every registry change is exported to a backup folder on your Desktop
echo first, together with an UNDO.cmd that restores the previous state.
echo The tool deletes no files, installs nothing, makes no network
echo connections and sends nothing anywhere.
echo.
echo Keep DelanCam1 connected and close apps that may use the camera
echo (Windows Camera, OBS, Teams, Discord, OpenTrack) before continuing.
echo.
echo Administrator rights are required for the repairs, so Windows will
echo show a User Account Control prompt next.
echo.
pause

fltmc >nul 2>&1
if %ERRORLEVEL%==0 goto run

echo.
echo Requesting administrator rights...
set "DELAN_RELAUNCH_ARGS=/elevated"
if "%DELAN_MODE%"=="apply" set "DELAN_RELAUNCH_ARGS=%DELAN_RELAUNCH_ARGS% /apply"
if "%DELAN_SKIPPROBE%"=="1" set "DELAN_RELAUNCH_ARGS=%DELAN_RELAUNCH_ARGS% /skipprobe"
"%DELAN_PS%" -NoProfile -ExecutionPolicy Bypass -Command "try { $p = Start-Process -FilePath $env:DELAN_SCRIPT -ArgumentList $env:DELAN_RELAUNCH_ARGS -WorkingDirectory (Split-Path -Parent $env:DELAN_SCRIPT) -Verb RunAs -PassThru -Wait -ErrorAction Stop; if ($p -and $null -ne $p.ExitCode) { exit $p.ExitCode } else { exit 0 } } catch { exit 99 }"
set "RC=%ERRORLEVEL%"
if "%RC%"=="99" (
    echo.
    echo Administrator rights were not granted.
    echo The tool will only CHECK the system now; nothing can be repaired
    echo without administrator rights. Run it again to repair.
    echo.
    set "DELAN_MODE=check"
    goto run
)
echo.
echo The administrator window has finished. Its log is on your Desktop.
echo.
pause
exit /b %RC%

:run
echo.
echo Checking the Windows video pipeline. Please wait...
echo.

"%DELAN_PS%" -NoProfile -ExecutionPolicy Bypass -Command "$raw = Get-Content -LiteralPath $env:DELAN_SCRIPT -Raw; $marker = '### DELANCLIP_' + 'POWERSHELL ###'; $idx = $raw.LastIndexOf($marker); if ($idx -lt 0) { throw 'Embedded PowerShell section not found.' }; $code = $raw.Substring($idx + $marker.Length); Invoke-Expression $code"

set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="1" (
    echo The tool did not complete successfully.
    echo Please take a screenshot of this window and send it to Delanclip Support.
) else (
    echo The tool has finished. The result is shown above and saved on your Desktop.
    echo Send Delanclip Support the DelanCam1-FixTool log or backup folder from the Desktop
    echo if they asked for it.
)
echo.
pause
exit /b %RC%

### DELANCLIP_POWERSHELL ###
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# ---------------------------------------------------------------------------
# Delanclip DelanCam1 Fix Tool - embedded Windows PowerShell 5.1 implementation
#
# Modes (set by the .cmd wrapper through environment variables):
#   DELAN_MODE=check      report only, then offer to apply (default)
#   DELAN_MODE=apply      apply the repairs without asking
#   DELAN_SKIPPROBE=1     do not open the camera for the MJPG/NV12/YUY2 probe
#
# Exit codes: 0 = clean (nothing to do, or repairs applied and verified),
#             2 = findings remain (not applied, or still present after apply),
#             1 = the tool itself failed.
# ---------------------------------------------------------------------------

$toolVersion = '1.0.0'
$mode = 'check'
if ($env:DELAN_MODE -eq 'apply') { $mode = 'apply' }
$skipProbe = ($env:DELAN_SKIPPROBE -eq '1')

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$desktop = [Environment]::GetFolderPath('Desktop')
if (-not $desktop -or -not (Test-Path -LiteralPath $desktop)) {
    # A SYSTEM console (remote-support session) has no usable Desktop folder.
    $desktop = Join-Path $env:SystemDrive 'temp'
    if (-not (Test-Path -LiteralPath $desktop)) { New-Item -ItemType Directory -Force -Path $desktop | Out-Null }
}
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $desktop ("DelanCam1-FixTool-backup-" + $stamp)
$script:LogPath = Join-Path $desktop ("DelanCam1-FixTool-check-" + $stamp + ".txt")
$script:LogLines = New-Object System.Collections.Generic.List[string]
$script:Findings = New-Object System.Collections.Generic.List[object]
$script:Undo = New-Object System.Collections.Generic.List[string]
$script:AppliedAreas = @{}
$script:ApplyErrors = 0
$script:Probe = $null
$script:Pass = ''
$script:FastStartup = $false

$sysDir64 = Join-Path $env:SystemRoot 'System32'
$sysDir32 = Join-Path $env:SystemRoot 'SysWOW64'
$views = @(
    @{ Name = '64-bit'; Classes = 'HKLM\SOFTWARE\Classes'; Software = 'HKLM\SOFTWARE'; SysDir = $sysDir64; Regsvr = (Join-Path $sysDir64 'regsvr32.exe') }
)
if ([Environment]::Is64BitOperatingSystem) {
    $views += @{ Name = '32-bit'; Classes = 'HKLM\SOFTWARE\Classes\WOW6432Node'; Software = 'HKLM\SOFTWARE\WOW6432Node'; SysDir = $sysDir32; Regsvr = (Join-Path $sysDir32 'regsvr32.exe') }
}

$catVideoInput = '{860BB310-5D01-11d0-BD3B-00A0C911CE86}'
$catFilters = '{083863F1-70DE-11d0-BD40-00A0C911CE86}'
$mjpgSubtype = '{47504A4D-0000-0010-8000-00AA00389B71}'
$stockMjpgDecoder = '{301056D0-6DFF-11d2-9EEB-006008039E37}'
$hardwareMftKey = 'HKLM\SOFTWARE\Microsoft\Windows Media Foundation\HardwareMFT'
$ignoreDeadFilters = '(?i)^(Line 21 Decoder|Overlay Mixer|Overlay Mixer2|VBI Surface Allocator)$'
$expectedVfw = [ordered]@{
    'vidc.cvid' = 'iccvid.dll'; 'vidc.i420' = 'iyuv_32.dll'; 'vidc.iyuv' = 'iyuv_32.dll'
    'vidc.mrle' = 'msrle32.dll'; 'vidc.msvc' = 'msvidc32.dll'; 'vidc.uyvy' = 'msyuv.dll'
    'vidc.yuy2' = 'msyuv.dll'; 'vidc.yvu9' = 'tsbyuv.dll'; 'vidc.yvyu' = 'msyuv.dll'
}
$coreComponents = @(
    @{ N = 'KS proxy'; File = 'ksproxy.ax'; C = '{17CCA71B-ECD7-11D0-B908-00A0C9223196}' },
    @{ N = 'SampleGrabber'; File = 'qedit.dll'; C = '{C1F400A0-3F08-11d3-9F0B-006008039E37}' },
    @{ N = 'Null Renderer'; File = 'qedit.dll'; C = '{C1F400A4-3F08-11d3-9F0B-006008039E37}' },
    @{ N = 'FilterGraph'; File = 'quartz.dll'; C = '{e436ebb3-524f-11ce-9f53-0020af0ba770}' },
    @{ N = 'MJPEG Decompressor'; File = 'quartz.dll'; C = '{301056D0-6DFF-11d2-9EEB-006008039E37}' },
    @{ N = 'AVI Decompressor'; File = 'quartz.dll'; C = '{CF49D4E0-1115-11CE-B03A-0020AF0BA770}' },
    @{ N = 'Color Space Converter'; File = 'quartz.dll'; C = '{1643E180-90F5-11CE-97D5-00AA0055595A}' },
    @{ N = 'CaptureGraphBuilder2'; File = 'qcap.dll'; C = '{BF87B6E1-8C27-11d0-B3F0-00AA003761C5}' },
    @{ N = 'Smart Tee'; File = 'qcap.dll'; C = '{CC58E280-8AA1-11d1-B3F1-00AA003761C5}' },
    @{ N = 'SystemDeviceEnum'; File = 'devenum.dll'; C = '{62BE5D10-60EB-11d0-BD3B-00A0C911CE86}' }
)
$coreDlls = @('quartz.dll', 'qcap.dll', 'qedit.dll', 'qdv.dll', 'devenum.dll', 'ksproxy.ax')

# ------------------------------------------------------------------ logging

function Write-ToolLog {
    param([string]$Text = '', [string]$Color = '')
    if ($Color) { Write-Host $Text -ForegroundColor $Color } else { Write-Host $Text }
    $script:LogLines.Add($Text)
    try { [System.IO.File]::AppendAllText($script:LogPath, $Text + "`r`n", (New-Object System.Text.UTF8Encoding($false))) } catch {}
}

function Write-Section {
    param([string]$Title)
    Write-ToolLog ''
    Write-ToolLog ('=== ' + $Title + ' ===') 'Cyan'
}

function Add-Finding {
    # Severity: FIX (applied in apply mode), MANUAL (needs a person), WARN, INFO
    param([string]$Id, [string]$Severity, [string]$Text, [string[]]$Plan = @(), [scriptblock]$Action = $null, [hashtable]$Context = @{})
    $script:Findings.Add([pscustomobject]@{ Id = $Id; Severity = $Severity; Text = $Text; Plan = $Plan; Action = $Action; Context = $Context })
    $color = 'Gray'
    if ($Severity -eq 'FIX') { $color = 'Yellow' }
    elseif ($Severity -eq 'MANUAL' -or $Severity -eq 'WARN') { $color = 'Magenta' }
    Write-ToolLog ('  [' + $Severity + '] ' + $Id + ': ' + $Text) $color
}

function Add-Undo {
    param([string]$Command)
    $script:Undo.Add($Command)
}

# --------------------------------------------------------------- registry

function ConvertTo-ProviderPath {
    param([string]$RegPath)
    $p = $RegPath
    if ($p -match '^(?i)HKLM\\') { return 'Registry::HKEY_LOCAL_MACHINE\' + $p.Substring(5) }
    if ($p -match '^(?i)HKU\\') { return 'Registry::HKEY_USERS\' + $p.Substring(4) }
    if ($p -match '^(?i)HKCU\\') { return 'Registry::HKEY_CURRENT_USER\' + $p.Substring(5) }
    throw "Unsupported registry path: $RegPath"
}

function Test-RegKey {
    param([string]$RegPath)
    return (Test-Path -LiteralPath (ConvertTo-ProviderPath $RegPath))
}

function Get-RegValue {
    param([string]$RegPath, [string]$Name)
    try {
        $item = Get-ItemProperty -LiteralPath (ConvertTo-ProviderPath $RegPath) -ErrorAction Stop
        if ($null -eq $item) { return $null }
        if ($Name -eq '(default)') { return $item.'(default)' }
        return $item.$Name
    }
    catch { return $null }
}

function Get-RegValueNames {
    # Names of the real values under a key (PowerShell's PS* noise removed).
    param([string]$RegPath)
    $names = @()
    try {
        $item = Get-ItemProperty -LiteralPath (ConvertTo-ProviderPath $RegPath) -ErrorAction Stop
        foreach ($prop in $item.PSObject.Properties) {
            if ($prop.Name -in @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')) { continue }
            $names += $prop.Name
        }
    }
    catch {}
    return $names
}

function Get-RegSubKeyNames {
    param([string]$RegPath)
    $result = @()
    try { $result = @(Get-ChildItem -LiteralPath (ConvertTo-ProviderPath $RegPath) -ErrorAction Stop | ForEach-Object { $_.PSChildName }) } catch {}
    return $result
}

function Get-InprocServer {
    param([string]$ClassesRoot, [string]$Clsid)
    return (Get-RegValue ($ClassesRoot + '\CLSID\' + $Clsid + '\InprocServer32') '(default)')
}

function Get-FileState {
    # 'no InprocServer32', 'DLL MISSING', 'Windows' or 'third-party location'
    param([string]$Dll)
    if (-not $Dll) { return 'no InprocServer32' }
    $clean = [Environment]::ExpandEnvironmentVariables(([string]$Dll).Trim().Trim('"'))
    if (-not (Test-Path -LiteralPath $clean)) { return 'DLL MISSING' }
    if ($clean -match '(?i)^[a-z]:\\Windows\\') { return 'Windows' }
    return 'third-party location'
}

function Get-CleanPath {
    param([string]$Dll)
    if (-not $Dll) { return '' }
    return [Environment]::ExpandEnvironmentVariables(([string]$Dll).Trim().Trim('"'))
}

function Get-SafeFileName {
    param([string]$Text)
    $s = $Text -replace '[^A-Za-z0-9\.\-_{}]', '_'
    if ($s.Length -gt 90) { $s = $s.Substring(0, 90) }
    return $s
}

function Backup-RegKey {
    # Exports a key with reg.exe before it is touched. Returns the .reg file
    # name (relative to the backup folder) or $null when the key does not exist.
    param([string]$RegPath, [string]$Label)
    if (-not (Test-RegKey $RegPath)) {
        Write-ToolLog ('    backup: key does not exist yet, nothing to export: ' + $RegPath)
        return $null
    }
    $file = (Get-SafeFileName $Label) + '.reg'
    $full = Join-Path $backupDir $file
    $n = 1
    while (Test-Path -LiteralPath $full) { $n++; $file = (Get-SafeFileName $Label) + '-' + $n + '.reg'; $full = Join-Path $backupDir $file }
    $regExe = Join-Path $env:SystemRoot 'System32\reg.exe'
    $p = Start-Process -FilePath $regExe -ArgumentList ('export "' + $RegPath + '" "' + $full + '" /y') -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
    if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $full)) {
        throw ('reg export failed for ' + $RegPath + ' (exit code ' + $p.ExitCode + ')')
    }
    Write-ToolLog ('    backup: ' + $RegPath + ' -> ' + $file)
    return $file
}

function Remove-RegKeyWithBackup {
    param([string]$RegPath, [string]$Label)
    $file = Backup-RegKey $RegPath $Label
    if (-not $file) { return }
    Remove-Item -LiteralPath (ConvertTo-ProviderPath $RegPath) -Recurse -Force -ErrorAction Stop
    Add-Undo ('reg import "%~dp0' + $file + '"')
    Write-ToolLog ('    deleted key: ' + $RegPath)
}

function Set-RegStringWithUndo {
    # Sets a REG_SZ value; the caller has already exported the key. Records
    # the exact undo (delete the value if it did not exist, else reg import).
    param([string]$RegPath, [string]$Name, [string]$Value, [string]$BackupFile)
    $provider = ConvertTo-ProviderPath $RegPath
    if (-not (Test-Path -LiteralPath $provider)) { New-Item -Path $provider -Force | Out-Null }
    $existed = ($null -ne (Get-RegValue $RegPath $Name))
    New-ItemProperty -LiteralPath $provider -Name $Name -Value $Value -PropertyType String -Force | Out-Null
    if (-not $existed) { Add-Undo ('reg delete "' + $RegPath + '" /v "' + $Name + '" /f') }
    elseif ($BackupFile) { Add-Undo ('reg import "%~dp0' + $BackupFile + '"') }
    Write-ToolLog ('    set value: ' + $RegPath + ' ' + $Name + ' = ' + $Value)
}

function Set-RegDwordWithUndo {
    # Sets a REG_DWORD value; the caller has already exported the key (or
    # learned that it did not exist). Records the exact undo.
    param([string]$RegPath, [string]$Name, [int]$Value, [string]$BackupFile)
    $provider = ConvertTo-ProviderPath $RegPath
    if (-not (Test-Path -LiteralPath $provider)) { New-Item -Path $provider -Force | Out-Null }
    $old = Get-RegValue $RegPath $Name
    New-ItemProperty -LiteralPath $provider -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
    if ($null -eq $old) { Add-Undo ('reg delete "' + $RegPath + '" /v "' + $Name + '" /f') }
    elseif ($BackupFile) { Add-Undo ('reg import "%~dp0' + $BackupFile + '"') }
    else { Add-Undo ('reg add "' + $RegPath + '" /v "' + $Name + '" /t REG_DWORD /d ' + [int]$old + ' /f') }
    Write-ToolLog ('    set value: ' + $RegPath + ' ' + $Name + ' = ' + $Value + ' (was: ' + $(if ($null -eq $old) { 'not set' } else { [string]$old }) + ')')
}

function Remove-RegValueWithUndo {
    param([string]$RegPath, [string]$Name, [string]$BackupFile)
    Remove-ItemProperty -LiteralPath (ConvertTo-ProviderPath $RegPath) -Name $Name -Force -ErrorAction Stop
    if ($BackupFile) { Add-Undo ('reg import "%~dp0' + $BackupFile + '"') }
    Write-ToolLog ('    deleted value: ' + $RegPath + ' ' + $Name)
}

function Get-UserHives {
    # Loaded per-user hives (SID -> profile name). Works from an elevated
    # session of a different account and from a SYSTEM console alike.
    $list = @()
    try {
        $profiles = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -ErrorAction Stop
        foreach ($p in $profiles) {
            $sid = $p.PSChildName
            if ($sid -notmatch '^S-1-5-21-') { continue }
            $imagePath = (Get-ItemProperty $p.PSPath -ErrorAction SilentlyContinue).ProfileImagePath
            $loaded = Test-Path ('Registry::HKEY_USERS\' + $sid)
            $list += [pscustomobject]@{ Sid = $sid; User = (Split-Path ([string]$imagePath) -Leaf); HiveLoaded = $loaded }
        }
    }
    catch {}
    return $list
}

function Invoke-Regsvr32 {
    param([string]$Regsvr, [string]$Dll, [switch]$Unregister)
    $arguments = '/s "' + $Dll + '"'
    if ($Unregister) { $arguments = '/s /u "' + $Dll + '"' }
    $p = Start-Process -FilePath $Regsvr -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
    return $p.ExitCode
}

function Set-FrameServerManual {
    Set-Service -Name FrameServer -StartupType Manual -ErrorAction Stop
}

function Get-FrameServerState {
    # Returns @{ Present; Status; StartType } for the Windows Camera Frame Server.
    $svc = Get-Service -Name FrameServer -ErrorAction SilentlyContinue
    if (-not $svc) { return @{ Present = $false; Status = ''; StartType = '' } }
    $startType = ''
    try { $startType = [string](Get-CimInstance Win32_Service -Filter "Name='FrameServer'" -ErrorAction Stop).StartMode } catch { $startType = [string]$svc.StartType }
    return @{ Present = $true; Status = [string]$svc.Status; StartType = $startType }
}

function Get-BootState {
    # Returns @{ UptimeDays; UptimeHours; FastStartup } or $null when unavailable.
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $uptime = (Get-Date) - $os.LastBootUpTime
    $hiber = Get-RegValue 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled'
    return @{ UptimeDays = [int][math]::Floor($uptime.TotalDays); UptimeHours = $uptime.Hours; Hiber = $hiber }
}

function Stop-FrameServerServices {
    foreach ($svcName in @('FrameServer', 'FrameServerMonitor')) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') {
            try {
                Stop-Service -Name $svcName -Force -ErrorAction Stop
                Write-ToolLog ('    stopped service: ' + $svcName + ' (it restarts on demand when a camera app opens)')
            }
            catch { Write-ToolLog ('    could not stop service ' + $svcName + ': ' + $_.Exception.Message) 'Magenta' }
        }
    }
}

# ------------------------------------------------------------ camera probe

function Invoke-FormatProbe {
    # Opens DelanCam1 through the Windows Runtime camera API (Media Foundation
    # / Frame Server) once per format and counts frames for two seconds each.
    # Nothing is saved from the frames; only counts are kept.
    $result = [pscustomobject]@{ Performed = $false; Skipped = ''; Error = ''; Rows = @(); MjpgFrames = 0; RawFrames = 0; MjpgRows = 0 }
    if ($skipProbe) { $result.Skipped = 'skipped by the /skipprobe switch'; return $result }

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
    $wanted = @('MJPG 640x480@60', 'MJPG 640x480@30', 'NV12 640x480@30', 'YUY2 640x480@30')
    $vidPidPattern = '(?i)VID_0120.*PID_1234'
    $rows = @()

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
        if (-not $target) {
            $result.Skipped = 'DelanCam1 is not visible to Windows camera enumeration (not connected, or renamed by another driver)'
            return $result
        }
        $group = Wait-WinRtOperation ([Windows.Media.Capture.Frames.MediaFrameSourceGroup]::FromIdAsync($target.Id)) ([Windows.Media.Capture.Frames.MediaFrameSourceGroup]) 5000
        if (-not $group) { throw 'No MediaFrameSourceGroup was found for DelanCam1.' }

        $listCapture = New-ProbeCapture $group
        $listSource = Get-ProbeSource $listCapture $group
        $supported = @($listSource.SupportedFormats)
        try { $listCapture.Dispose() } catch {}
        $listCapture = $null
        $result.Performed = $true

        foreach ($want in $wanted) {
            $fmt = $supported | Where-Object { (Get-ProbeLabel $_) -eq $want } | Select-Object -First 1
            if (-not $fmt) {
                $rows += [pscustomobject]@{ Requested = $want; Negotiated = ''; Start = ''; Frames = 0; Error = 'not offered by this device'; Attempted = $false }
                continue
            }
            $row = [pscustomobject]@{ Requested = $want; Negotiated = ''; Start = ''; Frames = 0; Error = ''; Attempted = $true }
            $mc = $null
            $reader = $null
            try {
                $mc = New-ProbeCapture $group
                $src = Get-ProbeSource $mc $group
                try { Wait-WinRtAction ($src.SetFormatAsync($fmt)) 5000 }
                catch { $row.Error = 'SetFormat failed: ' + $_.Exception.Message }
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
                                if ($isNew) { $row.Frames++ }
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
            $rows += $row
            if ($want -like 'MJPG*') { $result.MjpgFrames += $row.Frames; $result.MjpgRows++ } else { $result.RawFrames += $row.Frames }
            Start-Sleep -Milliseconds 300
        }
    }
    catch {
        $realEx = $_.Exception
        while ($realEx.InnerException) { $realEx = $realEx.InnerException }
        $result.Error = $realEx.Message
    }
    $result.Rows = $rows
    return $result
}

function Write-ProbeResult {
    param($Probe, [string]$Title)
    Write-ToolLog ('  Camera probe (' + $Title + '): opens DelanCam1 per format for 2 seconds and counts frames')
    if ($Probe.Skipped) { Write-ToolLog ('    ' + $Probe.Skipped); return }
    if (-not $Probe.Performed) { Write-ToolLog ('    probe could not run: ' + $Probe.Error) 'Magenta'; return }
    foreach ($row in $Probe.Rows) {
        $extra = ''
        if ($row.Negotiated -and $row.Negotiated -ne $row.Requested) { $extra += '  negotiated ' + $row.Negotiated }
        if ($row.Start -and $row.Start -ne 'Success') { $extra += '  start=' + $row.Start }
        if ($row.Error) { $extra += '  ' + $row.Error }
        Write-ToolLog ('    {0,-16} {1,4} frames{2}' -f $row.Requested, $row.Frames, $extra)
    }
    if ($Probe.Error) { Write-ToolLog ('    probe error: ' + $Probe.Error) 'Magenta' }
    if ($Probe.MjpgRows -gt 0 -and $Probe.MjpgFrames -eq 0 -and $Probe.RawFrames -gt 0) {
        Write-ToolLog '    Reading: raw formats stream, every MJPEG request yields nothing. Windows-side MJPEG decoding is broken.' 'Yellow'
    }
    elseif ($Probe.MjpgFrames -eq 0 -and $Probe.RawFrames -eq 0) {
        Write-ToolLog '    Reading: no format delivered frames. USB, cable, driver or another app holding the camera; not a decoder problem.' 'Magenta'
    }
    else {
        Write-ToolLog '    Reading: frames arrived in MJPEG and raw formats. The Media Foundation path is healthy.' 'Green'
    }
}

# ------------------------------------------------------------- detection

function Test-MediaFoundation {
    Write-Section 'A. Media Foundation: hardware MJPEG decoder switch'
    $enableDecoders = Get-RegValue $hardwareMftKey 'EnableDecoders'
    $decodersText = 'not set (default: hardware decoders enabled)'
    if ($null -ne $enableDecoders) { $decodersText = [string]$enableDecoders }
    Write-ToolLog ('  HardwareMFT EnableDecoders: ' + $decodersText)

    $vendorMjpeg = @()
    foreach ($view in $views) {
        $catPath = $view.Classes + '\MediaFoundation\Transforms\Categories\d6c02d4b-6833-45b4-971a-05a4b04bab91'
        if (-not (Test-RegKey $catPath)) { $catPath = $view.Classes + '\MediaFoundation\Transforms\Categories\{d6c02d4b-6833-45b4-971a-05a4b04bab91}' }
        $members = Get-RegSubKeyNames $catPath
        $vendorNames = @()
        foreach ($member in $members) {
            $id = $member.Trim('{}')
            $name = Get-RegValue ($view.Classes + '\MediaFoundation\Transforms\' + $id) '(default)'
            if (-not $name) { $name = Get-RegValue ($view.Classes + '\MediaFoundation\Transforms\{' + $id + '}') '(default)' }
            if (-not $name) { $name = '(unnamed)' }
            $dll = Get-InprocServer $view.Classes ('{' + $id + '}')
            if (-not $dll) { continue }
            $clean = Get-CleanPath $dll
            $isVendor = ($clean -match '(?i)\\DriverStore\\FileRepository\\' -or $clean -notmatch '(?i)^[a-z]:\\Windows\\(System32|SysWOW64)\\[^\\]+$' -or $name -match '(?i)intel|nvidia|amd |radeon|qualcomm|snapdragon|mediatek')
            if ($isVendor -and $name -match '(?i)jpeg|jpg') {
                $vendorNames += $name
                $vendorMjpeg += ($name + ' [' + $view.Name + '] ' + $clean)
            }
        }
        Write-ToolLog ('  Registered video decoders (' + $view.Name + '): ' + $members.Count + '; vendor MJPEG decoders: ' + $(if ($vendorNames.Count -gt 0) { ($vendorNames | Select-Object -Unique) -join ', ' } else { 'none' }))
    }
    foreach ($v in $vendorMjpeg) { Write-ToolLog ('    ' + $v) }

    Write-ProbeResult $script:Probe $script:Pass

    $probe = $script:Probe
    $mjpgBroken = ($probe.Performed -and $probe.MjpgRows -gt 0 -and $probe.MjpgFrames -eq 0 -and $probe.RawFrames -gt 0)
    $mjpgHealthy = ($probe.Performed -and $probe.MjpgFrames -gt 0)
    $decodersEnabled = ($null -eq $enableDecoders -or [int]$enableDecoders -ne 0)

    if (-not $decodersEnabled) {
        if ($vendorMjpeg.Count -gt 0) { Add-Finding 'A' 'INFO' 'Hardware decoders are already disabled (EnableDecoders=0); the vendor MJPEG decoder is inert.' }
        else { Add-Finding 'A' 'INFO' 'Hardware decoders are already disabled (EnableDecoders=0). Nothing to do.' }
        if ($mjpgBroken) { Add-Finding 'A' 'WARN' 'MJPEG still delivers no frames although hardware decoders are disabled. That is outside what this tool repairs; send Delanclip Support the diagnostic report.' }
        return
    }

    $reason = ''
    if ($mjpgBroken) { $reason = 'the probe shows MJPEG delivering 0 frames while raw formats stream' }
    elseif ($vendorMjpeg.Count -gt 0 -and -not $mjpgHealthy) { $reason = 'a vendor MJPEG decoder is registered and the probe could not confirm MJPEG works' }

    if ($reason) {
        $plan = @(
            ('reg export "' + $hardwareMftKey + '" (backup)'),
            ('set ' + $hardwareMftKey + '\EnableDecoders = 0 (REG_DWORD; reversible, UNDO restores the previous value)'),
            'stop the Windows Camera Frame Server service so the change takes effect (it restarts on demand)',
            'probe MJPG again to verify'
        )
        Add-Finding 'A' 'FIX' ('Disable hardware Media Foundation decoders because ' + $reason + '.') $plan {
            $file = Backup-RegKey $hardwareMftKey 'A-HardwareMFT'
            Set-RegDwordWithUndo $hardwareMftKey 'EnableDecoders' 0 $file
            Stop-FrameServerServices
            $script:AppliedAreas['A'] = $true
        }
    }
    elseif ($vendorMjpeg.Count -gt 0) {
        Add-Finding 'A' 'INFO' 'A vendor MJPEG decoder is registered but the probe shows MJPEG streaming normally. Left as is.'
    }
    else {
        Add-Finding 'A' 'INFO' 'No vendor MJPEG decoder registered; hardware decoders stay enabled.'
    }
}

function Test-VfwCodecs {
    Write-Section 'B. VFW video codecs (Drivers32 vidc.* entries)'
    foreach ($view in $views) {
        $key = $view.Software + '\Microsoft\Windows NT\CurrentVersion\Drivers32'
        $present = @{}
        foreach ($name in (Get-RegValueNames $key)) {
            if ($name -match '(?i)^vidc\.') { $present[$name.ToLower()] = [string](Get-RegValue $key $name) }
        }
        Write-ToolLog ('  ' + $view.Name + ' view: ' + $present.Count + ' vidc.* entries present')
        $toRestore = @()
        $planLines = @()
        $manual = @()
        $nonStock = @()
        foreach ($entry in $expectedVfw.GetEnumerator()) {
            $name = $entry.Key
            $stockDll = $entry.Value
            $stockPath = Join-Path $view.SysDir $stockDll
            if ($present.ContainsKey($name)) {
                $current = $present[$name]
                if ($current -ieq $stockDll) { continue }
                $currentPath = $current
                if ($currentPath -notmatch '[\\/]') { $currentPath = Join-Path $view.SysDir $currentPath }
                $currentPath = Get-CleanPath $currentPath
                if (Test-Path -LiteralPath $currentPath) { $nonStock += ($name + '=' + $current); continue }
                if (Test-Path -LiteralPath $stockPath) { $toRestore += @{ Name = $name; Value = $stockDll; Was = $current }; $planLines += ($name + ' = ' + $stockDll + ' (currently ' + $current + ', file missing)') }
                else { $manual += ($name + ' -> ' + $stockDll + ' (not found in ' + $view.SysDir + ')') }
            }
            else {
                if (Test-Path -LiteralPath $stockPath) { $toRestore += @{ Name = $name; Value = $stockDll; Was = $null }; $planLines += ($name + ' = ' + $stockDll + ' (missing)') }
                else { $manual += ($name + ' -> ' + $stockDll + ' (not found in ' + $view.SysDir + ')') }
            }
        }
        foreach ($line in $planLines) { Write-ToolLog ('    missing or broken: ' + $line) }
        if ($nonStock.Count -gt 0) { Add-Finding ('B-' + $view.Name) 'INFO' ('Non-stock but existing codec entries left as is: ' + ($nonStock -join ', ')) }
        if ($manual.Count -gt 0) { Add-Finding ('B-' + $view.Name) 'MANUAL' ('Codec DLL missing from Windows itself, cannot register it: ' + ($manual -join '; ') + '. Run "sfc /scannow" as administrator, then run this tool again.') }
        if ($toRestore.Count -gt 0) {
            $plan = @(('reg export "' + $key + '" (backup)')) + ($planLines | ForEach-Object { 'reg add ' + $key + ' /v ' + $_ })
            $action = {
                param($Ctx)
                $file = Backup-RegKey $Ctx.Key ('B-Drivers32-' + $Ctx.View)
                foreach ($item in $Ctx.List) { Set-RegStringWithUndo $Ctx.Key $item.Name $item.Value $file }
                $script:AppliedAreas['B'] = $true
            }
            Add-Finding ('B-' + $view.Name) 'FIX' ('Restore ' + $toRestore.Count + ' stock VFW codec entr' + $(if ($toRestore.Count -eq 1) { 'y' } else { 'ies' }) + ' in the ' + $view.Name + ' Drivers32 list: ' + (($toRestore | ForEach-Object { $_.Name }) -join ', ') + '.') $plan $action @{ Key = $key; List = $toRestore; View = $view.Name }
        }
        else {
            Add-Finding ('B-' + $view.Name) 'INFO' ('All nine stock vidc.* entries are present in the ' + $view.Name + ' view.')
        }
    }
}

function Test-DirectShow {
    Write-Section 'C. DirectShow: dead filters, ghost cameras and core components'
    $needPostCleanup = $false
    $treatAsFindings = @()

    foreach ($view in $views) {
        Write-ToolLog ('  ' + $view.Name + ' view')
        $needCoreReg = $false

        # Core components -----------------------------------------------------
        $coreMissing = @()
        $coreFileMissing = @()
        foreach ($c in $coreComponents) {
            $dll = Get-InprocServer $view.Classes $c.C
            $state = Get-FileState $dll
            $treatAs = Get-RegValue ($view.Classes + '\CLSID\' + $c.C + '\TreatAs') '(default)'
            if (-not $dll -or $state -eq 'DLL MISSING') {
                if (Test-Path -LiteralPath (Join-Path $view.SysDir $c.File)) { $coreMissing += ($c.N + ' (' + $c.File + ')'); $needCoreReg = $true }
                else { $coreFileMissing += ($c.File + ' missing from ' + $view.SysDir) }
            }
            if ($treatAs) { $treatAsFindings += @{ View = $view; Name = $c.N; Clsid = $c.C; Target = [string]$treatAs } }
        }
        if ($coreMissing.Count -gt 0) { Write-ToolLog ('    core components not registered: ' + ($coreMissing -join ', ')) 'Yellow' }
        else { Write-ToolLog '    core components: all registered' }
        if ($coreFileMissing.Count -gt 0) { Add-Finding ('C-core-' + $view.Name) 'MANUAL' ('DirectShow system file(s) missing from Windows: ' + (($coreFileMissing | Select-Object -Unique) -join '; ') + '. Run "sfc /scannow" as administrator.') }

        # Ghost virtual cameras ---------------------------------------------
        $instanceRoot = $view.Classes + '\CLSID\' + $catVideoInput + '\Instance'
        $deadCams = @()
        $liveCams = @()
        foreach ($sub in (Get-RegSubKeyNames $instanceRoot)) {
            $entry = $instanceRoot + '\' + $sub
            $clsid = [string](Get-RegValue $entry 'CLSID')
            if (-not $clsid) { $clsid = $sub }
            $friendly = [string](Get-RegValue $entry 'FriendlyName')
            if (-not $friendly) { $friendly = $sub }
            $dll = Get-InprocServer $view.Classes $clsid
            $state = Get-FileState $dll
            if ($state -eq 'DLL MISSING' -or $state -eq 'no InprocServer32') {
                $deadCams += @{ Entry = $entry; Sub = $sub; Clsid = $clsid; Name = $friendly; Dll = $dll; State = $state }
                Write-ToolLog ('    ghost camera: "' + $friendly + '" ' + $clsid + ' -> ' + $dll + ' [' + $state + ']') 'Yellow'
            }
            else {
                $liveCams += ($friendly + ' -> ' + (Get-CleanPath $dll))
                Write-ToolLog ('    virtual camera (file exists, left alone): "' + $friendly + '" -> ' + (Get-CleanPath $dll))
            }
        }
        if ($liveCams.Count -gt 0) {
            Add-Finding ('C-cams-' + $view.Name) 'INFO' ('Working virtual camera registration(s) present, not touched: ' + ($liveCams -join '; ') + '. If the program is uninstalled, support removes it with: ' + $view.Regsvr + ' /s /u "<dll>".')
        }

        # Dead filters --------------------------------------------------------
        $filterRoot = $view.Classes + '\CLSID\' + $catFilters + '\Instance'
        $deadFilters = @()
        $filterSubs = Get-RegSubKeyNames $filterRoot
        foreach ($sub in $filterSubs) {
            $entry = $filterRoot + '\' + $sub
            $clsid = [string](Get-RegValue $entry 'CLSID')
            if (-not $clsid) { $clsid = $sub }
            $friendly = [string](Get-RegValue $entry 'FriendlyName')
            if (-not $friendly) { $friendly = $sub }
            $dll = Get-InprocServer $view.Classes $clsid
            $state = Get-FileState $dll
            if ($state -ne 'DLL MISSING' -and $state -ne 'no InprocServer32') { continue }
            if ($friendly -match $ignoreDeadFilters) { continue }
            $deadFilters += @{ Entry = $entry; Sub = $sub; Clsid = $clsid; Name = $friendly; Dll = $dll; State = $state }
            Write-ToolLog ('    dead filter: "' + $friendly + '" ' + $clsid + ' -> ' + $dll + ' [' + $state + ']') 'Yellow'
        }
        Write-ToolLog ('    registered filters: ' + $filterSubs.Count + ', dead: ' + $deadFilters.Count + ', ghost cameras: ' + $deadCams.Count)

        $dead = @($deadCams + $deadFilters)
        if ($dead.Count -gt 0) {
            $needPostCleanup = $true
            $plan = @()
            foreach ($d in $dead) {
                $plan += ('reg export + reg delete "' + $d.Entry + '"')
                $clsidKey = $view.Classes + '\CLSID\' + $d.Clsid
                if (Test-RegKey $clsidKey) { $plan += ('reg export + reg delete "' + $clsidKey + '"') }
            }
            $action = {
                param($Ctx)
                foreach ($d in $Ctx.Dead) {
                    Remove-RegKeyWithBackup $d.Entry ('C-' + $Ctx.View.Name + '-instance-' + $d.Clsid)
                    $clsidKey = $Ctx.View.Classes + '\CLSID\' + $d.Clsid
                    if (Test-RegKey $clsidKey) {
                        $srv = Get-InprocServer $Ctx.View.Classes $d.Clsid
                        $st = Get-FileState $srv
                        if ($st -eq 'DLL MISSING' -or $st -eq 'no InprocServer32') { Remove-RegKeyWithBackup $clsidKey ('C-' + $Ctx.View.Name + '-clsid-' + $d.Clsid) }
                        else { Write-ToolLog ('    kept CLSID key (its file exists): ' + $clsidKey) }
                    }
                }
                $script:AppliedAreas['C'] = $true
            }
            Add-Finding ('C-' + $view.Name) 'FIX' ('Remove ' + $dead.Count + ' dead DirectShow registration(s) in the ' + $view.Name + ' view: ' + (($dead | ForEach-Object { '"' + $_.Name + '"' }) -join ', ') + '.') $plan $action @{ Dead = $dead; View = $view }
        }
        if ($needCoreReg) { $needPostCleanup = $true }
    }

    # TreatAs on core filters (area D, detected here because it belongs to the core loop)
    foreach ($t in $treatAsFindings) {
        $key = $t.View.Classes + '\CLSID\' + $t.Clsid + '\TreatAs'
        $action = {
            param($Ctx)
            Remove-RegKeyWithBackup $Ctx.Key ('D-TreatAs-' + $Ctx.View + '-' + $Ctx.Name)
            $script:AppliedAreas['D'] = $true
        }
        Add-Finding ('D-TreatAs-' + $t.View.Name) 'FIX' ('Remove the TreatAs redirection on "' + $t.Name + '" (' + $t.View.Name + ') that points to ' + $t.Target + '.') @(('reg export + reg delete "' + $key + '"')) $action @{ Key = $key; Name = $t.Name; View = $t.View.Name }
    }

    if ($needPostCleanup) {
        $plan = @('for every logged-on user: reg export + reg delete HKU\<SID>\Software\Microsoft\ActiveMovie\devenum (DirectShow device cache)')
        foreach ($view in $views) { $plan += ($view.Regsvr + ' /s ' + $view.SysDir + '\{' + ($coreDlls -join ',') + '}') }
        Add-Finding 'C-post' 'FIX' 'Clear each user''s DirectShow device cache and re-register the DirectShow core (quartz, qcap, qedit, qdv, devenum, ksproxy) in every view.' $plan {
            foreach ($h in (Get-UserHives)) {
                if (-not $h.HiveLoaded) { continue }
                $cache = 'HKU\' + $h.Sid + '\Software\Microsoft\ActiveMovie\devenum'
                if (Test-RegKey $cache) { Remove-RegKeyWithBackup $cache ('C-devenum-cache-' + $h.User) }
            }
            foreach ($view in $views) {
                foreach ($dllName in $coreDlls) {
                    $dllPath = Join-Path $view.SysDir $dllName
                    if (-not (Test-Path -LiteralPath $dllPath)) { Write-ToolLog ('    not present, skipped: ' + $dllPath) 'Magenta'; continue }
                    $code = Invoke-Regsvr32 $view.Regsvr $dllPath
                    if ($code -eq 0) { Write-ToolLog ('    registered: ' + $dllPath) }
                    else { Write-ToolLog ('    regsvr32 returned ' + $code + ' for ' + $dllPath) 'Magenta' }
                }
            }
            Add-Undo 'rem The DirectShow core re-registration is idempotent and needs no undo.'
            $script:AppliedAreas['C'] = $true
        }
    }
    else {
        Add-Finding 'C' 'INFO' 'No dead DirectShow registrations; core components registered in every view.'
    }
}

function Test-DecoderPreferences {
    Write-Section 'D. DirectShow decoder selection (Preferred, DoNotUse)'
    foreach ($view in $views) {
        $prefKey = $view.Software + '\Microsoft\DirectShow\Preferred'
        $dnuKey = $view.Software + '\Microsoft\DirectShow\DoNotUse'

        $mjpgTarget = Get-RegValue $prefKey $mjpgSubtype
        if ($mjpgTarget) {
            $tName = Get-RegValue ($view.Classes + '\CLSID\' + $mjpgTarget) '(default)'
            if (-not $tName) { $tName = '(no name registered)' }
            $tState = Get-FileState (Get-InprocServer $view.Classes ([string]$mjpgTarget))
            Write-ToolLog ('  ' + $view.Name + ' Preferred MJPG -> ' + $mjpgTarget + ' ' + $tName + ' [' + $tState + ']')
            if (([string]$mjpgTarget) -notmatch '(?i)^\{301056D0-6DFF-11D2-9EEB-006008039E37\}$') {
                $action = {
                    param($Ctx)
                    $file = Backup-RegKey $Ctx.Key ('D-Preferred-' + $Ctx.View)
                    Set-RegStringWithUndo $Ctx.Key $mjpgSubtype $stockMjpgDecoder $file
                    $script:AppliedAreas['D'] = $true
                }
                $plan = @(('reg export "' + $prefKey + '"'), ('reg add ' + $prefKey + ' /v ' + $mjpgSubtype + ' /d ' + $stockMjpgDecoder))
                Add-Finding ('D-MJPG-' + $view.Name) 'FIX' ('Preferred MJPG decoder is ' + $mjpgTarget + ' (' + $tName + ', ' + $tState + ') instead of the Windows MJPEG Decompressor; restore it.') $plan $action @{ Key = $prefKey; View = $view.Name }
            }
        }
        else { Write-ToolLog ('  ' + $view.Name + ' Preferred MJPG -> not set (Windows default applies)') }

        $dangling = @()
        foreach ($name in (Get-RegValueNames $prefKey)) {
            if ($name -notmatch '^\{') { continue }
            if ($name -ieq $mjpgSubtype) { continue }
            $target = [string](Get-RegValue $prefKey $name)
            if (-not $target) { continue }
            $state = Get-FileState (Get-InprocServer $view.Classes $target)
            if ($state -eq 'DLL MISSING' -or $state -eq 'no InprocServer32') { $dangling += @{ Name = $name; Target = $target; State = $state } }
        }
        if ($dangling.Count -gt 0) {
            foreach ($d in $dangling) { Write-ToolLog ('    dangling Preferred entry: ' + $d.Name + ' -> ' + $d.Target + ' [' + $d.State + ']') 'Yellow' }
            $action = {
                param($Ctx)
                $file = Backup-RegKey $Ctx.Key ('D-Preferred-' + $Ctx.View)
                foreach ($d in $Ctx.List) { Remove-RegValueWithUndo $Ctx.Key $d.Name $file }
                $script:AppliedAreas['D'] = $true
            }
            $plan = @(('reg export "' + $prefKey + '"')) + @($dangling | ForEach-Object { 'reg delete ' + $prefKey + ' /v ' + $_.Name })
            Add-Finding ('D-Preferred-' + $view.Name) 'FIX' ('Delete ' + $dangling.Count + ' Preferred decoder entr' + $(if ($dangling.Count -eq 1) { 'y' } else { 'ies' }) + ' pointing at decoders that no longer exist (' + $view.Name + ').') $plan $action @{ Key = $prefKey; View = $view.Name; List = $dangling }
        }

        $dnuNames = @(Get-RegValueNames $dnuKey | Where-Object { $_ -ne '(default)' })
        if ($dnuNames.Count -gt 0) {
            foreach ($n in $dnuNames) {
                $dn = Get-RegValue ($view.Classes + '\CLSID\' + $n) '(default)'
                Write-ToolLog ('    DoNotUse blocks: ' + $n + ' ' + $dn) 'Yellow'
            }
            $action = {
                param($Ctx)
                $file = Backup-RegKey $Ctx.Key ('D-DoNotUse-' + $Ctx.View)
                foreach ($n in $Ctx.List) { Remove-RegValueWithUndo $Ctx.Key $n $file }
                $script:AppliedAreas['D'] = $true
            }
            $plan = @(('reg export "' + $dnuKey + '"')) + @($dnuNames | ForEach-Object { 'reg delete ' + $dnuKey + ' /v ' + $_ })
            Add-Finding ('D-DoNotUse-' + $view.Name) 'FIX' ('Clear ' + $dnuNames.Count + ' DoNotUse entr' + $(if ($dnuNames.Count -eq 1) { 'y' } else { 'ies' }) + ' telling DirectShow to skip filters (' + $view.Name + ').') $plan $action @{ Key = $dnuKey; View = $view.Name; List = $dnuNames }
        }
        else { Write-ToolLog ('  ' + $view.Name + ' DoNotUse: empty') }
    }
    if (@($script:Findings | Where-Object { $_.Id -like 'D-*' -and $_.Severity -eq 'FIX' }).Count -eq 0) {
        Add-Finding 'D' 'INFO' 'Preferred MJPG decoder, DoNotUse list and TreatAs are stock.'
    }
}

function Test-ConsentAndServices {
    Write-Section 'E. Camera consent, Frame Server service and restart state'
    $consentBase = 'SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam'
    $hklmAll = Get-RegValue ('HKLM\' + $consentBase) 'Value'
    $hklmDesktop = Get-RegValue ('HKLM\' + $consentBase + '\NonPackaged') 'Value'
    Write-ToolLog ('  Machine camera consent: all apps = ' + $(if ($hklmAll) { $hklmAll } else { 'not set' }) + ', desktop apps = ' + $(if ($hklmDesktop) { $hklmDesktop } else { 'not set' }))
    if ($hklmAll -eq 'Deny') { Add-Finding 'E-consent' 'MANUAL' 'Camera access is denied for the whole PC. Settings > Privacy & security > Camera > "Camera access" must be On.' }
    if ($hklmDesktop -eq 'Deny') { Add-Finding 'E-consent' 'MANUAL' 'Camera access is denied for desktop apps on the whole PC. Settings > Privacy & security > Camera > "Let desktop apps access your camera" must be On.' }
    foreach ($h in (Get-UserHives)) {
        if (-not $h.HiveLoaded) { continue }
        $uAll = Get-RegValue ('HKU\' + $h.Sid + '\' + $consentBase) 'Value'
        $uDesktop = Get-RegValue ('HKU\' + $h.Sid + '\' + $consentBase + '\NonPackaged') 'Value'
        Write-ToolLog ('  User ' + $h.User + ': all apps = ' + $(if ($uAll) { $uAll } else { 'not set' }) + ', desktop apps = ' + $(if ($uDesktop) { $uDesktop } else { 'not set' }))
        if ($uAll -eq 'Deny') { Add-Finding 'E-consent' 'MANUAL' ('User ' + $h.User + ': camera access is Off. Settings > Privacy & security > Camera > "Let apps access your camera" must be On.') }
        if ($uDesktop -eq 'Deny') { Add-Finding 'E-consent' 'MANUAL' ('User ' + $h.User + ': desktop apps are denied the camera; OpenTrack and AITrack are desktop apps. Settings > Privacy & security > Camera > "Let desktop apps access your camera" must be On.') }
    }
    $polCam = Get-RegValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsAccessCamera'
    if ($polCam -eq 2) { Add-Finding 'E-policy' 'MANUAL' 'Group Policy LetAppsAccessCamera = 2 forces camera access off. A policy set by an administrator or a tweak tool must be removed first.' }
    $allowCam = Get-RegValue 'HKLM\SOFTWARE\Policies\Microsoft\Camera' 'AllowCamera'
    if ($allowCam -eq 0) { Add-Finding 'E-policy' 'MANUAL' 'Policy AllowCamera = 0 disables the camera. A policy set by an administrator or a tweak tool must be removed first.' }
    $disableWebcam = Get-RegValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Webcam' 'DisableWebcam'
    if ($disableWebcam -eq 1) { Add-Finding 'E-policy' 'MANUAL' 'Policy DisableWebcam = 1 disables the camera. A policy set by an administrator or a tweak tool must be removed first.' }

    $fs = Get-FrameServerState
    if (-not $fs.Present) { Add-Finding 'E-service' 'WARN' 'The Windows Camera Frame Server service is not present on this system.' }
    else {
        Write-ToolLog ('  Windows Camera Frame Server: ' + $fs.Status + ', start type ' + $fs.StartType + ' (Manual is the Windows default; it starts on demand)')
        if ($fs.StartType -match '(?i)disabled') {
            Add-Finding 'E-service' 'FIX' 'The Windows Camera Frame Server service is disabled; every Media Foundation camera app fails without it. Set it back to Manual.' @('sc config FrameServer start= demand') {
                Set-FrameServerManual
                Add-Undo 'sc config FrameServer start= disabled'
                Write-ToolLog '    FrameServer start type set to Manual'
                $script:AppliedAreas['E'] = $true
            }
        }
    }

    try {
        $boot = Get-BootState
        $hiber = $boot.Hiber
        $script:FastStartup = ($hiber -eq 1)
        Write-ToolLog ('  Time since last boot: ' + $boot.UptimeDays + ' day(s) ' + $boot.UptimeHours + ' hour(s); Fast Startup: ' + $(if ($null -eq $hiber) { 'not set' } elseif ($hiber -eq 1) { 'ON ("Shut down" does not reload drivers; use "Restart")' } else { 'off' }))
    }
    catch { Write-ToolLog ('  Restart state unavailable: ' + $_.Exception.Message) }
}

function Invoke-Detection {
    param([string]$Pass)
    $script:Pass = $Pass
    $script:Findings.Clear()
    $script:Probe = Invoke-FormatProbe
    Test-MediaFoundation
    Test-VfwCodecs
    Test-DirectShow
    Test-DecoderPreferences
    Test-ConsentAndServices
}

function Write-FindingsSummary {
    param([string]$Title)
    Write-Section $Title
    $fixes = @($script:Findings | Where-Object { $_.Severity -eq 'FIX' })
    $manual = @($script:Findings | Where-Object { $_.Severity -eq 'MANUAL' -or $_.Severity -eq 'WARN' })
    if ($fixes.Count -eq 0 -and $manual.Count -eq 0) {
        Write-ToolLog '  CLEAN: nothing to repair. The Windows video pipeline checks all pass.' 'Green'
    }
    foreach ($f in $fixes) { Write-ToolLog ('  [FIX] ' + $f.Id + ': ' + $f.Text) 'Yellow' }
    foreach ($f in $manual) { Write-ToolLog ('  [' + $f.Severity + '] ' + $f.Id + ': ' + $f.Text) 'Magenta' }
    return $fixes
}

function Write-UndoScript {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('@echo off')
    $lines.Add('setlocal')
    $lines.Add('title Delanclip DelanCam1 Fix Tool - UNDO')
    $lines.Add('echo This restores the registry state that DelanCam1-FixTool saved on ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '.')
    $lines.Add('echo It re-imports the .reg backups in this folder and reverts the settings the tool changed.')
    $lines.Add('echo.')
    $lines.Add('fltmc >nul 2>&1')
    $lines.Add('if not %ERRORLEVEL%==0 (')
    $lines.Add('    echo Please right-click UNDO.cmd and choose "Run as administrator".')
    $lines.Add('    pause')
    $lines.Add('    exit /b 1')
    $lines.Add(')')
    $lines.Add('echo Press any key to restore the previous state, or close this window to keep the repairs.')
    $lines.Add('pause')
    $lines.Add('cd /d "%~dp0"')
    $undo = @($script:Undo)
    [array]::Reverse($undo)
    foreach ($cmd in $undo) { $lines.Add($cmd) }
    $lines.Add('net stop FrameServer >nul 2>&1')
    $lines.Add('echo.')
    $lines.Add('echo Done. Restart Windows (Restart, not Shut down) to complete the rollback.')
    $lines.Add('pause')
    $path = Join-Path $backupDir 'UNDO.cmd'
    [System.IO.File]::WriteAllText($path, (($lines -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
    Write-ToolLog ('  UNDO.cmd written: ' + $path)
}

# ------------------------------------------------------------------- main

try {
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        throw 'This tool must run in 64-bit PowerShell on 64-bit Windows; the 32-bit PowerShell sees a redirected registry.'
    }

    Write-ToolLog ('Delanclip DelanCam1 Fix Tool ' + $toolVersion)
    Write-ToolLog ('Started: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz') + '   Mode: ' + $mode + '   Administrator: ' + $isAdmin + '   User: ' + [Environment]::UserName)
    Write-ToolLog ('Windows build: ' + [Environment]::OSVersion.Version.ToString() + '   64-bit OS: ' + [Environment]::Is64BitOperatingSystem)
    Write-ToolLog ('Log: ' + $script:LogPath)
    if (-not $isAdmin -and $mode -eq 'apply') {
        Write-ToolLog 'Apply mode needs administrator rights; falling back to check mode.' 'Magenta'
        $mode = 'check'
    }

    Invoke-Detection 'before'
    $fixes = @(Write-FindingsSummary 'RESULT OF THE CHECK')

    if ($fixes.Count -eq 0) {
        Write-ToolLog ''
        $manualLeft = @($script:Findings | Where-Object { $_.Severity -eq 'MANUAL' -or $_.Severity -eq 'WARN' })
        if ($manualLeft.Count -gt 0) {
            Write-ToolLog 'Nothing for this tool to repair automatically. The items marked MANUAL or WARN above need a person; follow their instructions, then run the tool again.' 'Yellow'
            exit 2
        }
        Write-ToolLog 'No repairs are needed. If OpenTrack still cannot open DelanCam1, send Delanclip Support the diagnostic report and this log.' 'Green'
        exit 0
    }

    Write-Section 'CHANGES THE APPLY STEP WOULD MAKE'
    foreach ($f in $fixes) {
        Write-ToolLog ('  ' + $f.Id + ': ' + $f.Text)
        foreach ($p in $f.Plan) { Write-ToolLog ('      - ' + $p) }
    }
    Write-ToolLog ''
    Write-ToolLog ('  Backups and UNDO.cmd would go to: ' + $backupDir)

    if ($mode -ne 'apply') {
        if (-not $isAdmin) {
            Write-ToolLog ''
            Write-ToolLog 'Administrator rights are needed to apply these repairs. Run the tool again and accept the Windows prompt.' 'Magenta'
            exit 2
        }
        Write-Host ''
        Write-Host 'Type APPLY and press Enter to make the changes listed above now.' -ForegroundColor Yellow
        Write-Host 'Press Enter alone to exit without changing anything.'
        $answer = ''
        try { $answer = Read-Host 'Your choice' } catch { $answer = '' }
        if (([string]$answer).Trim() -ne 'APPLY') {
            Write-ToolLog ''
            Write-ToolLog 'Nothing was changed. Run the tool again and type APPLY (or start it with /apply) to repair.' 'Yellow'
            exit 2
        }
        $mode = 'apply'
        Write-ToolLog 'APPLY confirmed in the console.'
    }

    # ---- apply -------------------------------------------------------------
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    $oldLog = $script:LogPath
    $script:LogPath = Join-Path $backupDir 'LOG.txt'
    try {
        [System.IO.File]::WriteAllText($script:LogPath, (($script:LogLines -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
        Remove-Item -LiteralPath $oldLog -Force -ErrorAction SilentlyContinue
    }
    catch {}
    Write-Section 'APPLYING REPAIRS'
    Write-ToolLog ('  Backup folder: ' + $backupDir)
    foreach ($f in $fixes) {
        Write-ToolLog ('  ' + $f.Id + ': ' + $f.Text) 'Yellow'
        try { & $f.Action $f.Context }
        catch {
            $script:ApplyErrors++
            Write-ToolLog ('    FAILED: ' + $_.Exception.Message) 'Red'
        }
    }
    Write-UndoScript

    Invoke-Detection 'after'
    $remaining = @(Write-FindingsSummary 'VERIFICATION AFTER THE REPAIRS')

    Write-Section 'WHAT TO DO NEXT'
    $areas = @($script:AppliedAreas.Keys | Sort-Object)
    if ($areas.Count -gt 0) { Write-ToolLog ('  Repairs applied in area(s): ' + ($areas -join ', ') + '. Backups and UNDO.cmd: ' + $backupDir) }
    if ($script:ApplyErrors -gt 0) { Write-ToolLog ('  ' + $script:ApplyErrors + ' repair step(s) failed; see the FAILED lines above.') 'Red' }
    $needRestart = ($script:AppliedAreas.ContainsKey('B') -or $script:AppliedAreas.ContainsKey('C') -or $script:AppliedAreas.ContainsKey('D') -or $script:AppliedAreas.ContainsKey('E'))
    if ($needRestart) {
        Write-ToolLog '  1. Restart Windows now using "Restart" (not "Shut down"). DirectShow changes only take full effect after a real restart.' 'Yellow'
        if ($script:FastStartup) { Write-ToolLog '     Fast Startup is ON on this PC, so "Shut down" would keep the old driver state in memory.' 'Yellow' }
        Write-ToolLog '  2. After the restart, run the DelanCam1 Diagnostics tool again and send the new report to Delanclip Support.'
        Write-ToolLog '  3. Then test OpenTrack: select DelanCam1 again in the camera list and press Start.'
    }
    else {
        Write-ToolLog '  1. Close and reopen OpenTrack or AITrack, select DelanCam1 again and press Start.'
        Write-ToolLog '  2. If it still fails, restart Windows using "Restart" and run the DelanCam1 Diagnostics tool again for Delanclip Support.'
    }
    Write-ToolLog '  To undo everything this tool changed, run UNDO.cmd in the backup folder as administrator.'
    Write-ToolLog ''
    Write-ToolLog ('Finished: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'))

    try { Start-Process explorer.exe -ArgumentList ('"' + $backupDir + '"') } catch {}
    if ($remaining.Count -gt 0 -or $script:ApplyErrors -gt 0) { exit 2 }
    exit 0
}
catch {
    $msg = $_.Exception.Message
    Write-Host ''
    Write-Host ('ERROR: ' + $msg) -ForegroundColor Red
    try { Write-ToolLog ('ERROR: ' + $msg + ' at ' + $_.InvocationInfo.PositionMessage) } catch {}
    exit 1
}
