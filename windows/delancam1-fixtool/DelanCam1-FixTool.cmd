@echo off
setlocal
set "DELAN_VERSION=2.0.0"
title Delanclip DelanCam1 Fix Tool v%DELAN_VERSION%
set "DELAN_SCRIPT=%~f0"
set "DELAN_MODE=check"
set "DELAN_SKIPPROBE=0"
set "DELAN_ELEVATED=0"

:parse_args
if "%~1"=="" goto args_done
if /i "%~1"=="/apply" set "DELAN_MODE=apply"
if /i "%~1"=="/check" set "DELAN_MODE=check"
if /i "%~1"=="/undo" set "DELAN_MODE=undo"
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
echo        Delanclip DelanCam1 Fix Tool v%DELAN_VERSION%
echo ============================================================
echo.
echo This tool checks your PC and DelanCam1 the way Delanclip Support does,
echo then repairs the Windows settings that can stop OpenTrack or AITrack
echo from opening the camera.
echo.
echo How it works:
echo  1. It collects information about Windows, the camera and the USB
echo     connection and briefly opens the camera to test its picture
echo     (1 to 2 minutes). No image or video is saved.
echo  2. It tells you in plain words what it found. Nothing is changed
echo     until you answer Y to "Repair now?".
echo  3. Before any change, a backup with an UNDO script is saved, so
echo     everything can be put back with one click.
echo  4. Everything, including a report ZIP for Delanclip Support, lands in
echo     the DELANCLIP folder on your Desktop, which opens by itself at
echo     the end.
echo.
echo It deletes no files, installs nothing and never connects to the internet.
echo.
echo If Windows shows "Smart App Control blocked a file", close that message,
echo right-click DelanCam1-FixTool.cmd and choose "Run as administrator".
echo.
echo Before you continue: keep DelanCam1 connected and close apps that use
echo the camera (Windows Camera, OBS, Teams, Discord, OpenTrack, AITrack).
echo.
echo Windows will now ask for permission to make changes. Please answer Yes.
echo.
pause

fltmc >nul 2>&1
if %ERRORLEVEL%==0 goto run

echo.
echo Asking Windows for administrator permission...
set "DELAN_RELAUNCH_ARGS=/elevated"
if "%DELAN_MODE%"=="apply" set "DELAN_RELAUNCH_ARGS=%DELAN_RELAUNCH_ARGS% /apply"
if "%DELAN_MODE%"=="undo" set "DELAN_RELAUNCH_ARGS=%DELAN_RELAUNCH_ARGS% /undo"
if "%DELAN_SKIPPROBE%"=="1" set "DELAN_RELAUNCH_ARGS=%DELAN_RELAUNCH_ARGS% /skipprobe"
rem A file downloaded from the internet carries a "mark of the web". Windows
rem refuses to elevate such a script file directly ("This app has been blocked
rem for your protection"), so the elevated process is cmd.exe itself with this
rem file as its argument, and the mark is removed from this file first.
set "DELAN_CMDARGS=/c ""%DELAN_SCRIPT%" %DELAN_RELAUNCH_ARGS%""
"%DELAN_PS%" -NoProfile -ExecutionPolicy Bypass -Command "try { Unblock-File -LiteralPath $env:DELAN_SCRIPT -ErrorAction Stop } catch {}; try { $p = Start-Process -FilePath 'cmd.exe' -ArgumentList $env:DELAN_CMDARGS -WorkingDirectory (Split-Path -Parent $env:DELAN_SCRIPT) -Verb RunAs -PassThru -Wait -ErrorAction Stop; if ($p -and $null -ne $p.ExitCode) { exit $p.ExitCode } else { exit 0 } } catch { exit 99 }"
set "RC=%ERRORLEVEL%"
if "%RC%"=="99" (
    echo.
    echo Permission was not given. The tool will only check your PC and
    echo write the report now. To repair, run it again and answer Yes to
    echo the Windows question.
    echo.
    set "DELAN_MODE=check"
    goto run
)
echo.
echo Finished. You can close this window.
echo.
pause
exit /b %RC%

:run
echo.

"%DELAN_PS%" -NoProfile -ExecutionPolicy Bypass -Command "$raw = Get-Content -LiteralPath $env:DELAN_SCRIPT -Raw; $marker = '### DELANCLIP_' + 'POWERSHELL ###'; $idx = $raw.LastIndexOf($marker); if ($idx -lt 0) { throw 'Embedded PowerShell section not found.' }; $code = $raw.Substring($idx + $marker.Length); Invoke-Expression $code"

set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="1" (
    echo The tool could not finish.
    echo Please take a screenshot of this window and send it to Delanclip Support.
    echo.
)
pause
exit /b %RC%

### DELANCLIP_POWERSHELL ###
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# ---------------------------------------------------------------------------
# Delanclip DelanCam1 Fix Tool - embedded Windows PowerShell 5.1 implementation
#
# Modes (set by the .cmd wrapper through environment variables):
#   DELAN_MODE=check      check, explain, then offer to repair (default)
#   DELAN_MODE=apply      repair without asking
#   DELAN_MODE=undo       undo the most recent repair found on the Desktop
#   DELAN_SKIPPROBE=1     do not open the camera (stream test, probe, re-open cycles)
#
# Version 2 runs the complete DelanCam1 Diagnostics collector first (the
# report files support used to ask for), then detects and repairs the known
# Windows video-pipeline damage on the same data, and zips the whole run for
# support. The screen shows plain-language results only. Every technical
# detail goes to LOG.txt in the run folder.
#
# Exit codes: 0 = clean (nothing to do, or repairs applied and verified),
#             2 = findings remain (not applied, or still present after apply),
#             1 = the tool itself failed.
# ---------------------------------------------------------------------------

$toolVersion = if ($env:DELAN_VERSION) { $env:DELAN_VERSION } else { 'unknown' }
$mode = 'check'
if ($env:DELAN_MODE -eq 'apply') { $mode = 'apply' }
if ($env:DELAN_MODE -eq 'undo') { $mode = 'undo' }
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
$script:toolVersion = $toolVersion
# Everything the tool writes goes into one folder on the Desktop, so it can be
# found on a cluttered Desktop and sent to support as a whole. Each run gets
# its own folder with the diagnostic report files, LOG.txt, the registry
# backups and UNDO.cmd; a ZIP of that folder is the report for support.
$outRoot = Join-Path $desktop 'DELANCLIP'
if (-not (Test-Path -LiteralPath $outRoot)) { New-Item -ItemType Directory -Force -Path $outRoot | Out-Null }
$runPrefix = 'DelanCam1-FixTool-'
$runDir = Join-Path $outRoot ($runPrefix + $stamp)
if (-not (Test-Path -LiteralPath $runDir)) { New-Item -ItemType Directory -Force -Path $runDir | Out-Null }
$backupDir = $runDir
$zipPath = Join-Path $outRoot ('SEND-TO-DELANCLIP-DelanCam1-Report-' + $stamp + '.zip')
$script:LogPath = Join-Path $runDir 'LOG.txt'
$script:LogLines = New-Object System.Collections.Generic.List[string]
$script:Findings = New-Object System.Collections.Generic.List[object]
$script:Undo = New-Object System.Collections.Generic.List[string]
$script:AppliedAreas = @{}
$script:ApplyErrors = 0
$script:Probe = $null
$script:Pass = ''
$script:FastStartup = $false
$script:DiagCollected = $false
$script:RunCompleted = $false

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
# Camera apps need msyuv.dll (YUY2/UYVY/YVYU) and iyuv_32.dll (I420/IYUV). The
# other stock codecs (Cinepak, RLE, Video 1, YVU9) are legacy; Windows 11 no
# longer ships a 64-bit iccvid.dll, so a missing legacy DLL is not damage.
$criticalVfwDlls = @('msyuv.dll', 'iyuv_32.dll')

# ------------------------------------------------------------------ logging

function Write-ToolLog {
    # Technical detail: log file only, never the screen.
    param([string]$Text = '')
    $script:LogLines.Add($Text)
    try { [System.IO.File]::AppendAllText($script:LogPath, $Text + "`r`n", (New-Object System.Text.UTF8Encoding($false))) } catch {}
}

function Write-Screen {
    # Plain-language line for the person at the keyboard; also logged.
    param([string]$Text = '', [string]$Color = '')
    if ($Color) { Write-Host $Text -ForegroundColor $Color } else { Write-Host $Text }
    Write-ToolLog ('>> ' + $Text)
}

function Write-Section {
    param([string]$Title)
    Write-ToolLog ''
    Write-ToolLog ('=== ' + $Title + ' ===')
}

function Add-Finding {
    # Severity: FIX (applied in apply mode), MANUAL (needs a person), WARN, INFO.
    # Text is the technical description (log). Human and Fix are the plain
    # sentences shown on screen; a finding without Human stays off the screen.
    param([string]$Id, [string]$Severity, [string]$Text, [string[]]$Plan = @(), [scriptblock]$Action = $null, [hashtable]$Context = @{}, [string]$Human = '', [string]$Fix = '')
    $script:Findings.Add([pscustomobject]@{ Id = $Id; Severity = $Severity; Text = $Text; Plan = $Plan; Action = $Action; Context = $Context; Human = $Human; Fix = $Fix })
    Write-ToolLog ('  [' + $Severity + '] ' + $Id + ': ' + $Text)
}

function Add-Undo {
    param([string]$Command)
    $script:Undo.Add($Command)
}

function Read-Choice {
    # One key, no Enter. Falls back to Read-Host where a key cannot be read.
    param([string]$Prompt)
    Write-Host ($Prompt + ' ') -NoNewline -ForegroundColor Yellow
    $answer = ''
    try {
        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        $answer = [string]$key.Character
        Write-Host $answer
    }
    catch {
        try { $answer = [string](Read-Host) } catch { $answer = '' }
    }
    Write-ToolLog ('>> ' + $Prompt + ' ' + $answer)
    return $answer.Trim().ToUpperInvariant()
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
    # Returns @{ UptimeDays; UptimeHours; Hiber } or throws when unavailable.
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
            catch { Write-ToolLog ('    could not stop service ' + $svcName + ': ' + $_.Exception.Message) }
        }
    }
}

function Invoke-UndoScript {
    # Runs a previously written UNDO.cmd without its pauses. Returns its exit code.
    param([string]$UndoPath)
    $p = Start-Process -FilePath 'cmd.exe' -ArgumentList ('/c ""' + $UndoPath + '" /quiet"') -WorkingDirectory (Split-Path -Parent $UndoPath) -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
    return $p.ExitCode
}

function Request-DelayedRestart {
    param([int]$Seconds)
    $p = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\shutdown.exe') -ArgumentList ('/r /t ' + $Seconds + ' /c "Delanclip DelanCam1 Fix Tool: restarting to finish the repair."') -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
    return $p.ExitCode
}

# ------------------------------------------------------------ camera probe

function Invoke-ProbePass {
    # Opens DelanCam1 through the Windows Runtime camera API (Media Foundation
    # / Frame Server) once per format and counts frames for two seconds each.
    # Nothing is saved from the frames; only counts are kept.
    param([int]$PassNumber = 1)
    $result = [pscustomobject]@{ Performed = $false; Skipped = ''; Error = ''; Rows = @(); MjpgFrames = 0; RawFrames = 0; MjpgRows = 0; Passes = 1; Pass = $PassNumber }
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

function ConvertFrom-DiagnosticsProbe {
    # The diagnostics pass already opened the camera (stream test, per-format
    # probe, re-open cycles), so the first detection pass reads those counts
    # instead of opening the camera again. Every MJPG 640x480@60 sample is
    # kept: the best one counts, and samples that disagree mark the start as
    # intermittent, which no Windows setting repairs.
    $r = [pscustomobject]@{ Performed = $false; Skipped = ''; Error = ''; Rows = @(); MjpgFrames = 0; RawFrames = 0; MjpgRows = 0; Passes = 1; Source = 'diagnostics' }
    if ($skipProbe) { $r.Skipped = 'skipped by the /skipprobe switch'; return $r }
    if (@($script:delanCams).Count -eq 0) { $r.Skipped = 'DelanCam1 was not found among the present camera devices'; return $r }
    if (-not $script:streamTestOpened) {
        $why = [string]$script:streamTestApiError
        if (@($script:cameraHeldByOtherApp).Count -gt 0) { $why = 'another program is holding the camera: ' + (@($script:cameraHeldByOtherApp) -join ', ') }
        $r.Skipped = 'the camera could not be opened' + $(if ($why) { ' (' + $why + ')' } else { '' })
        return $r
    }
    if (-not $script:formatProbePerformed) {
        $r.Error = [string]$script:formatProbeError
        if (-not $r.Error) { $r.Error = 'the per-format probe did not run' }
        return $r
    }
    $r.Performed = $true
    $rows = @()
    foreach ($d in @($script:formatProbeRowResults)) {
        $samples = @([int]$d.Frames)
        $labels = @('probe ' + $d.Frames)
        if ($d.Format -eq 'MJPG 640x480@60') {
            if ($script:streamTestSubtype -match '(?i)MJPG') {
                $samples += [int]$script:streamTestFramesReceived
                $labels = @('stream test ' + $script:streamTestFramesReceived) + $labels
            }
            if (@($script:reopenCycleFrames).Count -gt 0) {
                foreach ($c in @($script:reopenCycleFrames)) { $samples += [int]$c }
                $labels += ('re-open ' + (@($script:reopenCycleFrames) -join ', '))
            }
        }
        $best = 0
        foreach ($v in $samples) { if ($v -gt $best) { $best = $v } }
        $healthy = @($samples | Where-Object { $_ -ge 5 }).Count
        $rows += [pscustomobject]@{ Requested = $d.Format; Negotiated = $d.Format; Start = 'Success'; Frames = [int]$best; Error = [string]$d.Error; Attempted = $true; Pass1 = [int]$d.Frames; Pass2 = [int]$best; Samples = ($labels -join '; '); Intermittent = ($healthy -gt 0 -and $healthy -lt $samples.Count) }
        if ($d.Format -like 'MJPG*') { $r.MjpgFrames += [int]$best; $r.MjpgRows++ } else { $r.RawFrames += [int]$best }
    }
    $r.Rows = $rows
    return $r
}

function Invoke-FormatProbe {
    # First pass: the diagnostics collector has just opened the camera, so its
    # counts are used. Verification pass: the camera is opened again.
    if ($script:Pass -eq 'before' -and $script:DiagCollected) { return ConvertFrom-DiagnosticsProbe }
    # Runs the per-format pass and, when it does not show MJPEG working, runs
    # it a second time after a short pause. A camera that starts only now and
    # then can give zero frames in one pass and a steady stream in the next,
    # which would otherwise look like a decoder problem. Each format keeps the
    # better of its two counts; both counts go to the log.
    $first = Invoke-ProbePass 1
    if (-not $first.Performed) { return $first }
    if ((Get-ProbeVerdict $first) -eq 'healthy') { return $first }
    Start-Sleep -Seconds 1
    $second = Invoke-ProbePass 2
    if (-not $second.Performed) {
        $note = $second.Skipped
        if (-not $note) { $note = $second.Error }
        if ($first.Error) { $first.Error = 'second pass could not run: ' + $note + '; ' + $first.Error }
        else { $first.Error = 'second pass could not run: ' + $note }
        return $first
    }
    $merged = [pscustomobject]@{ Performed = $true; Skipped = ''; Error = ''; Rows = @(); MjpgFrames = 0; RawFrames = 0; MjpgRows = 0; Passes = 2 }
    $rows = @()
    foreach ($row1 in $first.Rows) {
        $row2 = $second.Rows | Where-Object { $_.Requested -eq $row1.Requested } | Select-Object -First 1
        $best = $row1
        if ($row2 -and $row2.Frames -gt $row1.Frames) { $best = $row2 }
        $attempted = [bool]$row1.Attempted
        $pass2 = 0
        if ($row2) { $pass2 = $row2.Frames; if ($row2.Attempted) { $attempted = $true } }
        $rows += [pscustomobject]@{ Requested = $best.Requested; Negotiated = $best.Negotiated; Start = $best.Start; Frames = $best.Frames; Error = $best.Error; Attempted = $attempted; Pass1 = $row1.Frames; Pass2 = $pass2 }
        if (-not $attempted) { continue }
        if ($best.Requested -like 'MJPG*') { $merged.MjpgFrames += $best.Frames; $merged.MjpgRows++ } else { $merged.RawFrames += $best.Frames }
    }
    $merged.Rows = $rows
    $merged.Error = (@($first.Error, $second.Error) | Where-Object { $_ }) -join '; '
    return $merged
}

function Get-ProbeVerdict {
    # 'healthy'  MJPEG streams: at least one MJPG format gave 5 frames or more
    # 'intermittent'  MJPEG streamed in one sample and not in another (diagnostics data)
    # 'broken'   every MJPG format gave nothing while every raw format streamed,
    #            so MJPEG decoding inside Windows is what fails
    # 'erratic'  frames stop or never start in a raw format too, so the camera,
    #            its cable, the USB port or another program is the problem
    # 'dead'     nothing in any format
    # 'none'     no probe
    param($Probe)
    if (-not $Probe.Performed) { return 'none' }
    $rows = @($Probe.Rows | Where-Object { $_.Attempted })
    if ($rows.Count -eq 0) { return 'none' }
    $steady = 5
    $mjpg = @($rows | Where-Object { $_.Requested -like 'MJPG*' })
    $raw = @($rows | Where-Object { $_.Requested -notlike 'MJPG*' })
    $total = 0
    foreach ($r in $rows) { $total += $r.Frames }
    if ($total -eq 0) { return 'dead' }
    if (@($mjpg | Where-Object { $_.Frames -ge $steady }).Count -gt 0) {
        if (@($rows | Where-Object { $_.PSObject.Properties['Intermittent'] -and $_.Intermittent }).Count -gt 0) { return 'intermittent' }
        return 'healthy'
    }
    $rawSteady = ($raw.Count -gt 0 -and @($raw | Where-Object { $_.Frames -lt $steady }).Count -eq 0)
    if ($mjpg.Count -eq 0) { if ($rawSteady) { return 'healthy' } else { return 'erratic' } }
    $mjpgSilent = (@($mjpg | Where-Object { $_.Frames -gt 0 }).Count -eq 0)
    if ($mjpgSilent -and $rawSteady) { return 'broken' }
    return 'erratic'
}

function Get-ProbeSentence {
    param($Probe)
    if ($Probe.Skipped) {
        if ($Probe.Skipped -like 'skipped by*') { return 'skipped' }
        if ($Probe.Skipped -like 'DelanCam1 was not found*') { return 'DelanCam1 was not found, camera test skipped' }
        return 'camera test skipped: ' + $Probe.Skipped
    }
    if (-not $Probe.Performed) { return 'could not run (' + $Probe.Error + ')' }
    switch (Get-ProbeVerdict $Probe) {
        'broken' { return 'MJPEG gives no picture, other formats work' }
        'dead' { return 'no picture in any format (USB, cable or driver, not something this tool repairs)' }
        'erratic' { return 'the picture starts only now and then, in every format (camera, cable, USB port or another program, not something this tool repairs)' }
        'intermittent' { return 'the picture streamed in one test and not in another (camera, cable or USB port, not something this tool repairs)' }
        default { return 'all formats deliver a picture' }
    }
}

function Write-ProbeLog {
    param($Probe, [string]$Title)
    $twoPasses = ($Probe.PSObject.Properties['Passes'] -and $Probe.Passes -eq 2)
    $fromDiag = ($Probe.PSObject.Properties['Source'] -and $Probe.Source -eq 'diagnostics')
    $passNote = ''
    if ($twoPasses) { $passNote = '; two passes, because the first did not show MJPEG working; the better count per format is used' }
    if ($fromDiag) { $passNote = '; counts taken from the diagnostics pass (stream test, per-format probe, re-open cycles); the best sample per format counts' }
    Write-ToolLog ('  Camera probe (' + $Title + '): opens DelanCam1 per format for 2 seconds and counts frames' + $passNote)
    if ($Probe.Skipped) { Write-ToolLog ('    ' + $Probe.Skipped); return }
    if (-not $Probe.Performed) { Write-ToolLog ('    probe could not run: ' + $Probe.Error); return }
    foreach ($row in $Probe.Rows) {
        $extra = ''
        if ($twoPasses) { $extra += '  (pass 1: ' + $row.Pass1 + ', pass 2: ' + $row.Pass2 + ')' }
        if ($fromDiag -and $row.PSObject.Properties['Samples']) { $extra += '  (' + $row.Samples + $(if ($row.Intermittent) { '; intermittent' } else { '' }) + ')' }
        if ($row.Negotiated -and $row.Negotiated -ne $row.Requested) { $extra += '  negotiated ' + $row.Negotiated }
        if ($row.Start -and $row.Start -ne 'Success') { $extra += '  start=' + $row.Start }
        if ($row.Error) { $extra += '  ' + $row.Error }
        Write-ToolLog ('    {0,-16} {1,4} frames{2}' -f $row.Requested, $row.Frames, $extra)
    }
    if ($Probe.Error) { Write-ToolLog ('    probe error: ' + $Probe.Error) }
    Write-ToolLog ('    Reading: ' + (Get-ProbeSentence $Probe))
}

# ------------------------------------------------------------- detection

function Test-CameraPresence {
    # What the diagnostics pass learned about the camera itself: not present,
    # or held by another program. Neither is repaired by a registry change, so
    # the person gets a plain instruction instead of a blind repair.
    if (-not $script:DiagCollected -or $null -eq $script:Probe) { return }
    if (-not $script:Probe.Skipped -or $script:Probe.Skipped -like 'skipped by*') { return }
    if ($script:Probe.Skipped -like 'DelanCam1 was not found*') {
        Add-Finding 'CAM' 'WARN' 'DelanCam1 is not among the camera devices Windows reports.' -Human 'Windows does not see DelanCam1 at all. Check that the camera cable sits firmly in a rear USB port of the PC, try another rear port, then run this tool again. If it is still missing, send the report ZIP to Delanclip Support.'
        return
    }
    if ($script:Probe.Skipped -like 'the camera could not be opened*') {
        $held = @($script:cameraHeldByOtherApp)
        $human = 'DelanCam1 could not be opened for the camera test'
        if ($held.Count -gt 0) { $human += ', because another program is using it (' + ($held -join ', ') + ')' }
        $human += '. Close every program that can use a camera (OpenTrack, AITrack, OBS, Teams, Discord, Zoom, browser tabs with a camera) and run this tool again.'
        Add-Finding 'CAM' 'WARN' ('Camera test skipped: ' + $script:Probe.Skipped) -Human $human
    }
}

function Test-MediaFoundation {
    Write-Section 'A. Media Foundation: hardware MJPEG decoder switch'
    $enableDecoders = Get-RegValue $hardwareMftKey 'EnableDecoders'
    $decodersText = 'not set (default: hardware decoders enabled)'
    if ($null -ne $enableDecoders) { $decodersText = [string]$enableDecoders }
    Write-ToolLog ('  HardwareMFT EnableDecoders: ' + $decodersText)

    $vendorMjpeg = @()
    $vendorNamesAll = @()
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
        $vendorNamesAll += $vendorNames
        Write-ToolLog ('  Registered video decoders (' + $view.Name + '): ' + $members.Count + '; vendor MJPEG decoders: ' + $(if ($vendorNames.Count -gt 0) { ($vendorNames | Select-Object -Unique) -join ', ' } else { 'none' }))
    }
    foreach ($v in $vendorMjpeg) { Write-ToolLog ('    ' + $v) }
    Write-ProbeLog $script:Probe $script:Pass

    $verdict = Get-ProbeVerdict $script:Probe
    $mjpgBroken = ($verdict -eq 'broken')
    $mjpgHealthy = ($verdict -eq 'healthy')
    $decodersEnabled = ($null -eq $enableDecoders -or [int]$enableDecoders -ne 0)
    $vendorLabel = (($vendorNamesAll | Select-Object -Unique) -join ', ')

    if (-not $decodersEnabled) {
        if ($vendorMjpeg.Count -gt 0) { Add-Finding 'A' 'INFO' 'Hardware decoders are already disabled (EnableDecoders=0); the vendor MJPEG decoder is inert.' }
        else { Add-Finding 'A' 'INFO' 'Hardware decoders are already disabled (EnableDecoders=0). Nothing to do.' }
        if ($mjpgBroken) {
            Add-Finding 'A' 'WARN' 'MJPEG still delivers no frames although hardware decoders are disabled.' -Human 'The camera still gives no MJPEG picture although the decoder setting is already correct. This tool cannot repair that; please send the DelanCam1 Diagnostics report to Delanclip Support.'
        }
        return
    }

    $reason = ''
    if ($mjpgBroken) { $reason = 'the probe shows MJPEG delivering 0 frames while raw formats stream' }
    elseif ($vendorMjpeg.Count -gt 0 -and $verdict -eq 'none' -and $script:Probe.Skipped -and $script:Probe.Skipped -notlike 'skipped by*') { $reason = '' }
    elseif ($vendorMjpeg.Count -gt 0 -and $verdict -eq 'none') { $reason = 'a vendor MJPEG decoder is registered and the probe could not confirm MJPEG works' }

    if ($reason) {
        $plan = @(
            ('reg export "' + $hardwareMftKey + '" (backup)'),
            ('set ' + $hardwareMftKey + '\EnableDecoders = 0 (REG_DWORD; reversible, UNDO restores the previous value)'),
            'stop the Windows Camera Frame Server service so the change takes effect (it restarts on demand)',
            'probe MJPG again to verify'
        )
        $human = 'A video decoder from your graphics driver'
        if ($vendorLabel) { $human += ' (' + $vendorLabel + ')' }
        $human += ' takes over the camera''s MJPEG picture inside Windows and delivers nothing, so apps that ask for MJPEG (OpenTrack, AITrack) see no picture.'
        if (-not $mjpgBroken) { $human = 'A video decoder from your graphics driver (' + $vendorLabel + ') is set up to take over the camera''s MJPEG picture inside Windows. This is a known cause of "no picture" in OpenTrack and AITrack.' }
        Add-Finding 'A' 'FIX' ('Disable hardware Media Foundation decoders because ' + $reason + '.') $plan {
            $file = Backup-RegKey $hardwareMftKey 'A-HardwareMFT'
            Set-RegDwordWithUndo $hardwareMftKey 'EnableDecoders' 0 $file
            Stop-FrameServerServices
            $script:AppliedAreas['A'] = $true
        } @{} -Human $human -Fix 'Tell Windows to use its own MJPEG decoder instead (one setting, fully reversible).'
    }
    elseif ($vendorMjpeg.Count -gt 0 -and $mjpgHealthy) {
        Add-Finding 'A' 'INFO' 'A vendor MJPEG decoder is registered but the probe shows MJPEG streaming normally. Left as is.'
    }
    elseif ($vendorMjpeg.Count -gt 0 -and $verdict -eq 'none') {
        Add-Finding 'A' 'INFO' ('A vendor MJPEG decoder is registered, but the camera test was skipped (' + $script:Probe.Skipped + '), so the decoder is left as is until the camera can be tested.')
    }
    elseif ($vendorMjpeg.Count -gt 0) {
        if ($verdict -eq 'intermittent') { Add-Finding 'A' 'INFO' 'A vendor MJPEG decoder is registered, but MJPEG streamed in at least one test, so the decoder is not what stops the camera. Left as is.' }
        else { Add-Finding 'A' 'INFO' ('A vendor MJPEG decoder is registered, but the probe verdict is "' + $verdict + '": frames stop or never start in raw formats too, so the decoder is not what blocks the camera. Left as is.') }
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
        $manualDlls = @()
        $legacyAbsent = @()
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
                elseif ($criticalVfwDlls -contains $stockDll) { $manual += ($name + ' -> ' + $stockDll + ' (not found in ' + $view.SysDir + ')'); $manualDlls += $stockDll }
                else { $legacyAbsent += ($name + ' (' + $stockDll + ' not shipped in this Windows)') }
            }
            else {
                if (Test-Path -LiteralPath $stockPath) { $toRestore += @{ Name = $name; Value = $stockDll; Was = $null }; $planLines += ($name + ' = ' + $stockDll + ' (missing)') }
                elseif ($criticalVfwDlls -contains $stockDll) { $manual += ($name + ' -> ' + $stockDll + ' (not found in ' + $view.SysDir + ')'); $manualDlls += $stockDll }
                else { $legacyAbsent += ($name + ' (' + $stockDll + ' not shipped in this Windows)') }
            }
        }
        foreach ($line in $planLines) { Write-ToolLog ('    missing or broken: ' + $line) }
        if ($legacyAbsent.Count -gt 0) { Write-ToolLog ('    legacy codec absent together with its DLL, not damage: ' + ($legacyAbsent -join ', ')) }
        if ($nonStock.Count -gt 0) { Add-Finding ('B-' + $view.Name) 'INFO' ('Non-stock but existing codec entries left as is: ' + ($nonStock -join ', ')) }
        if ($manual.Count -gt 0) {
            Add-Finding ('B-' + $view.Name) 'MANUAL' ('Codec DLL missing from Windows itself, cannot register it: ' + ($manual -join '; ') + '.') -Human ('A Windows system file is missing (' + (($manualDlls | Select-Object -Unique) -join ', ') + '). Open Command Prompt as administrator, run "sfc /scannow", wait for it to finish, then run this tool again.')
        }
        if ($toRestore.Count -gt 0) {
            $plan = @(('reg export "' + $key + '" (backup)')) + ($planLines | ForEach-Object { 'reg add ' + $key + ' /v ' + $_ })
            $action = {
                param($Ctx)
                $file = Backup-RegKey $Ctx.Key ('B-Drivers32-' + $Ctx.View)
                foreach ($item in $Ctx.List) { Set-RegStringWithUndo $Ctx.Key $item.Name $item.Value $file }
                $script:AppliedAreas['B'] = $true
            }
            $human = 'Windows has lost part of its standard video codec list (' + $view.Name + ' programs). OpenTrack and AITrack need it to convert the camera picture, so they fail even with MJPEG off.'
            Add-Finding ('B-' + $view.Name) 'FIX' ('Restore ' + $toRestore.Count + ' stock VFW codec entr' + $(if ($toRestore.Count -eq 1) { 'y' } else { 'ies' }) + ' in the ' + $view.Name + ' Drivers32 list: ' + (($toRestore | ForEach-Object { $_.Name }) -join ', ') + '.') $plan $action @{ Key = $key; List = $toRestore; View = $view.Name } -Human $human -Fix ('Put the ' + $toRestore.Count + ' missing standard entr' + $(if ($toRestore.Count -eq 1) { 'y' } else { 'ies' }) + ' back (the codec files themselves are still in Windows).')
        }
        else {
            Add-Finding ('B-' + $view.Name) 'INFO' ('Every stock vidc.* entry whose DLL ships with this Windows is present in the ' + $view.Name + ' view.')
        }
    }
}

function Test-DirectShow {
    Write-Section 'C. DirectShow: dead filters, ghost cameras and core components'
    $needPostCleanup = $false
    $treatAsFindings = @()
    $allDeadNames = @()

    foreach ($view in $views) {
        Write-ToolLog ('  ' + $view.Name + ' view')
        $needCoreReg = $false

        # Core components -----------------------------------------------------
        $coreMissing = @()
        $coreFileMissing = @()
        $coreFiles = @()
        foreach ($c in $coreComponents) {
            $dll = Get-InprocServer $view.Classes $c.C
            $state = Get-FileState $dll
            $treatAs = Get-RegValue ($view.Classes + '\CLSID\' + $c.C + '\TreatAs') '(default)'
            if (-not $dll -or $state -eq 'DLL MISSING') {
                if (Test-Path -LiteralPath (Join-Path $view.SysDir $c.File)) { $coreMissing += ($c.N + ' (' + $c.File + ')'); $needCoreReg = $true }
                else { $coreFileMissing += ($c.File + ' missing from ' + $view.SysDir); $coreFiles += $c.File }
            }
            if ($treatAs) { $treatAsFindings += @{ View = $view; Name = $c.N; Clsid = $c.C; Target = [string]$treatAs } }
        }
        if ($coreMissing.Count -gt 0) { Write-ToolLog ('    core components not registered: ' + ($coreMissing -join ', ')) }
        else { Write-ToolLog '    core components: all registered' }
        if ($coreFileMissing.Count -gt 0) {
            Add-Finding ('C-core-' + $view.Name) 'MANUAL' ('DirectShow system file(s) missing from Windows: ' + (($coreFileMissing | Select-Object -Unique) -join '; ') + '.') -Human ('A Windows video component file is missing (' + (($coreFiles | Select-Object -Unique) -join ', ') + '). Open Command Prompt as administrator, run "sfc /scannow", wait for it to finish, then run this tool again.')
        }
        if ($coreMissing.Count -gt 0) {
            Add-Finding ('C-corereg-' + $view.Name) 'FIX' ('DirectShow core components not registered (' + $view.Name + '): ' + ($coreMissing -join ', ') + '. Re-registered by the cleanup step.') @() { param($Ctx) } @{} -Human ('Some of Windows''s own video components are no longer registered (' + $view.Name + ' programs), so camera apps cannot build their video connection.') -Fix 'Register Windows''s own video components again (built-in files, nothing new is installed).'
        }

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
                Write-ToolLog ('    ghost camera: "' + $friendly + '" ' + $clsid + ' -> ' + $dll + ' [' + $state + ']')
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
            Write-ToolLog ('    dead filter: "' + $friendly + '" ' + $clsid + ' -> ' + $dll + ' [' + $state + ']')
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
            $names = @($dead | ForEach-Object { $_.Name } | Select-Object -Unique)
            $newNames = @($names | Where-Object { $allDeadNames -notcontains $_ })
            $allDeadNames += $newNames
            $human = ''
            if ($newNames.Count -gt 0) {
                $human = 'Leftovers of removed camera software or codec packs are still registered in Windows: ' + ($newNames -join ', ') + '. Their files are gone, but the entries still confuse OpenTrack and AITrack when they connect to the camera.'
            }
            Add-Finding ('C-' + $view.Name) 'FIX' ('Remove ' + $dead.Count + ' dead DirectShow registration(s) in the ' + $view.Name + ' view: ' + (($dead | ForEach-Object { '"' + $_.Name + '"' }) -join ', ') + '.') $plan $action @{ Dead = $dead; View = $view } -Human $human -Fix 'Remove the leftover entries and refresh Windows''s own video components.'
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
        Add-Finding ('D-TreatAs-' + $t.View.Name) 'FIX' ('Remove the TreatAs redirection on "' + $t.Name + '" (' + $t.View.Name + ') that points to ' + $t.Target + '.') @(('reg export + reg delete "' + $key + '"')) $action @{ Key = $key; Name = $t.Name; View = $t.View.Name } -Human ('A codec pack redirected one of Windows''s own video components (' + $t.Name + ') to itself, and that target is no longer usable.') -Fix 'Remove the redirection so Windows uses its own component again.'
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
                    if (-not (Test-Path -LiteralPath $dllPath)) { Write-ToolLog ('    not present, skipped: ' + $dllPath); continue }
                    $code = Invoke-Regsvr32 $view.Regsvr $dllPath
                    if ($code -eq 0) { Write-ToolLog ('    registered: ' + $dllPath) }
                    else { Write-ToolLog ('    regsvr32 returned ' + $code + ' for ' + $dllPath) }
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
                $human = 'Windows is told to decode the camera''s MJPEG picture with a decoder from a codec pack instead of its own'
                if ($tName -ne '(no name registered)') { $human += ' (' + $tName + ')' }
                if ($tState -ne 'Windows') { $human += ', and that decoder is no longer usable' }
                $human += '. This affects ' + $view.Name + ' programs.'
                Add-Finding ('D-MJPG-' + $view.Name) 'FIX' ('Preferred MJPG decoder is ' + $mjpgTarget + ' (' + $tName + ', ' + $tState + ') instead of the Windows MJPEG Decompressor; restore it.') $plan $action @{ Key = $prefKey; View = $view.Name } -Human $human -Fix 'Point Windows back at its own MJPEG decoder.'
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
            foreach ($d in $dangling) { Write-ToolLog ('    dangling Preferred entry: ' + $d.Name + ' -> ' + $d.Target + ' [' + $d.State + ']') }
            $action = {
                param($Ctx)
                $file = Backup-RegKey $Ctx.Key ('D-Preferred-' + $Ctx.View)
                foreach ($d in $Ctx.List) { Remove-RegValueWithUndo $Ctx.Key $d.Name $file }
                $script:AppliedAreas['D'] = $true
            }
            $plan = @(('reg export "' + $prefKey + '"')) + @($dangling | ForEach-Object { 'reg delete ' + $prefKey + ' /v ' + $_.Name })
            Add-Finding ('D-Preferred-' + $view.Name) 'FIX' ('Delete ' + $dangling.Count + ' Preferred decoder entr' + $(if ($dangling.Count -eq 1) { 'y' } else { 'ies' }) + ' pointing at decoders that no longer exist (' + $view.Name + ').') $plan $action @{ Key = $prefKey; View = $view.Name; List = $dangling } -Human ('Windows still prefers ' + $dangling.Count + ' video decoder' + $(if ($dangling.Count -eq 1) { '' } else { 's' }) + ' from software that has been removed (' + $view.Name + ' programs).') -Fix 'Remove those stale preferences so Windows falls back to its own decoders.'
        }

        $dnuNames = @(Get-RegValueNames $dnuKey | Where-Object { $_ -ne '(default)' })
        if ($dnuNames.Count -gt 0) {
            foreach ($n in $dnuNames) {
                $dn = Get-RegValue ($view.Classes + '\CLSID\' + $n) '(default)'
                Write-ToolLog ('    DoNotUse blocks: ' + $n + ' ' + $dn)
            }
            $action = {
                param($Ctx)
                $file = Backup-RegKey $Ctx.Key ('D-DoNotUse-' + $Ctx.View)
                foreach ($n in $Ctx.List) { Remove-RegValueWithUndo $Ctx.Key $n $file }
                $script:AppliedAreas['D'] = $true
            }
            $plan = @(('reg export "' + $dnuKey + '"')) + @($dnuNames | ForEach-Object { 'reg delete ' + $dnuKey + ' /v ' + $_ })
            Add-Finding ('D-DoNotUse-' + $view.Name) 'FIX' ('Clear ' + $dnuNames.Count + ' DoNotUse entr' + $(if ($dnuNames.Count -eq 1) { 'y' } else { 'ies' }) + ' telling DirectShow to skip filters (' + $view.Name + ').') $plan $action @{ Key = $dnuKey; View = $view.Name; List = $dnuNames } -Human ('A codec pack told Windows to skip ' + $dnuNames.Count + ' of its own video component' + $(if ($dnuNames.Count -eq 1) { '' } else { 's' }) + ' (' + $view.Name + ' programs).') -Fix 'Remove that block.'
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
    if ($hklmAll -eq 'Deny') { Add-Finding 'E-consent' 'MANUAL' 'Camera access is denied for the whole PC (HKLM).' -Human 'Camera access is switched off for the whole PC. Open Settings > Privacy & security > Camera and turn "Camera access" on, then run this tool again.' }
    if ($hklmDesktop -eq 'Deny') { Add-Finding 'E-consent' 'MANUAL' 'Camera access is denied for desktop apps on the whole PC (HKLM NonPackaged).' -Human 'Desktop apps are not allowed to use the camera on this PC. Open Settings > Privacy & security > Camera and turn "Let desktop apps access your camera" on, then run this tool again.' }
    foreach ($h in (Get-UserHives)) {
        if (-not $h.HiveLoaded) { continue }
        $uAll = Get-RegValue ('HKU\' + $h.Sid + '\' + $consentBase) 'Value'
        $uDesktop = Get-RegValue ('HKU\' + $h.Sid + '\' + $consentBase + '\NonPackaged') 'Value'
        Write-ToolLog ('  User ' + $h.User + ': all apps = ' + $(if ($uAll) { $uAll } else { 'not set' }) + ', desktop apps = ' + $(if ($uDesktop) { $uDesktop } else { 'not set' }))
        if ($uAll -eq 'Deny') { Add-Finding 'E-consent' 'MANUAL' ('User ' + $h.User + ': camera consent Deny.') -Human ('Camera access is switched off for the Windows user "' + $h.User + '". Open Settings > Privacy & security > Camera and turn "Let apps access your camera" on, then run this tool again.') }
        if ($uDesktop -eq 'Deny') { Add-Finding 'E-consent' 'MANUAL' ('User ' + $h.User + ': desktop apps camera consent Deny.') -Human ('Desktop apps such as OpenTrack and AITrack are not allowed to use the camera for the Windows user "' + $h.User + '". Open Settings > Privacy & security > Camera and turn "Let desktop apps access your camera" on, then run this tool again.') }
    }
    $polCam = Get-RegValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsAccessCamera'
    if ($polCam -eq 2) { Add-Finding 'E-policy' 'MANUAL' 'Group Policy LetAppsAccessCamera = 2 (force deny).' -Human 'A Windows policy forces camera access off (LetAppsAccessCamera). It was set by an administrator or a "privacy tweak" tool and has to be removed there first.' }
    $allowCam = Get-RegValue 'HKLM\SOFTWARE\Policies\Microsoft\Camera' 'AllowCamera'
    if ($allowCam -eq 0) { Add-Finding 'E-policy' 'MANUAL' 'Policy AllowCamera = 0 disables the camera.' -Human 'A Windows policy disables the camera (AllowCamera). It was set by an administrator or a "privacy tweak" tool and has to be removed there first.' }
    $disableWebcam = Get-RegValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Webcam' 'DisableWebcam'
    if ($disableWebcam -eq 1) { Add-Finding 'E-policy' 'MANUAL' 'Policy DisableWebcam = 1 disables the camera.' -Human 'A Windows policy disables the webcam (DisableWebcam). It was set by an administrator or a "privacy tweak" tool and has to be removed there first.' }

    $fs = Get-FrameServerState
    if (-not $fs.Present) { Add-Finding 'E-service' 'WARN' 'The Windows Camera Frame Server service is not present on this system.' -Human 'The Windows camera service (Frame Server) is missing from this PC. That is unusual; please send the DelanCam1 Diagnostics report to Delanclip Support.' }
    else {
        Write-ToolLog ('  Windows Camera Frame Server: ' + $fs.Status + ', start type ' + $fs.StartType + ' (Manual is the Windows default; it starts on demand)')
        if ($fs.StartType -match '(?i)disabled') {
            Add-Finding 'E-service' 'FIX' 'The Windows Camera Frame Server service is disabled. Set it back to Manual.' @('sc config FrameServer start= demand') {
                Set-FrameServerManual
                Add-Undo 'sc config FrameServer start= disabled'
                Write-ToolLog '    FrameServer start type set to Manual'
                $script:AppliedAreas['E'] = $true
            } @{} -Human 'The Windows camera service (Frame Server) has been disabled, usually by a "tweak" or "debloat" tool. Without it no camera app can get a picture.' -Fix 'Set the service back to its normal start mode.'
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
    # Runs every check. Quiet=true prints nothing per step (verification pass).
    param([string]$Pass, [switch]$Quiet)
    $script:Pass = $Pass
    $script:Findings.Clear()
    $steps = @(
        @{ Label = 'Camera test'; Run = { $script:Probe = Invoke-FormatProbe; Test-CameraPresence } },
        @{ Label = 'Windows video decoders'; Run = { Test-MediaFoundation } },
        @{ Label = 'Video codec list'; Run = { Test-VfwCodecs } },
        @{ Label = 'Camera software leftovers'; Run = { Test-DirectShow } },
        @{ Label = 'Decoder settings, camera privacy, services'; Run = { Test-DecoderPreferences; Test-ConsentAndServices } }
    )
    $i = 0
    foreach ($step in $steps) {
        $i++
        $before = $script:Findings.Count
        if (-not $Quiet) { Write-Host ('  [' + $i + '/' + $steps.Count + '] ' + $step.Label + ' ... ') -NoNewline }
        & $step.Run
        if (-not $Quiet) {
            $outcome = 'OK'
            $color = 'Green'
            if ($i -eq 1) { $outcome = Get-ProbeSentence $script:Probe; if ((Get-ProbeVerdict $script:Probe) -ne 'healthy') { $color = 'Yellow' } }
            else {
                $new = @($script:Findings | Select-Object -Skip $before | Where-Object { $_.Severity -ne 'INFO' })
                if ($new.Count -gt 0) { $outcome = 'needs attention'; $color = 'Yellow' }
            }
            Write-Host $outcome -ForegroundColor $color
            Write-ToolLog ('>> [' + $i + '/' + $steps.Count + '] ' + $step.Label + ': ' + $outcome)
        }
    }
}

function Get-ScreenFindings {
    # Findings shown to the person: FIX with a Human sentence, and MANUAL/WARN.
    $fixes = @($script:Findings | Where-Object { $_.Severity -eq 'FIX' -and $_.Human })
    $manual = @($script:Findings | Where-Object { ($_.Severity -eq 'MANUAL' -or $_.Severity -eq 'WARN') -and $_.Human })
    return @{ Fixes = $fixes; Manual = $manual }
}

function Write-UndoScript {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('@echo off')
    $lines.Add('setlocal')
    $lines.Add('title Delanclip DelanCam1 Fix Tool - UNDO')
    $lines.Add('set "QUIET=0"')
    $lines.Add('if /i "%~1"=="/quiet" set "QUIET=1"')
    $lines.Add('echo This puts your Windows settings back exactly as they were before')
    $lines.Add('echo the DelanCam1 Fix Tool repaired them on ' + (Get-Date -Format 'yyyy-MM-dd HH:mm') + '.')
    $lines.Add('echo.')
    $lines.Add('fltmc >nul 2>&1')
    $lines.Add('if not %ERRORLEVEL%==0 (')
    $lines.Add('    echo Please right-click UNDO.cmd and choose "Run as administrator".')
    $lines.Add('    if "%QUIET%"=="0" pause')
    $lines.Add('    exit /b 1')
    $lines.Add(')')
    $lines.Add('if "%QUIET%"=="0" (')
    $lines.Add('    echo Press any key to undo the repair, or close this window to keep it.')
    $lines.Add('    pause')
    $lines.Add(')')
    $lines.Add('cd /d "%~dp0"')
    $lines.Add('set "FAILED=0"')
    $undo = @($script:Undo)
    [array]::Reverse($undo)
    foreach ($cmd in $undo) {
        if ($cmd -like 'rem *') { $lines.Add($cmd); continue }
        if ($cmd -match '^reg delete "([^"]+)" /v "([^"]+)" /f$') {
            # Deleting a value that is already gone is not a failure (the script may run twice).
            $lines.Add('reg query "' + $Matches[1] + '" /v "' + $Matches[2] + '" >nul 2>&1 && (' + $cmd + ' >nul 2>&1 || set "FAILED=1")')
            continue
        }
        $lines.Add($cmd + ' >nul 2>&1 || set "FAILED=1"')
    }
    $lines.Add('net stop FrameServer >nul 2>&1')
    $lines.Add('echo.')
    $lines.Add('if "%FAILED%"=="1" (')
    $lines.Add('    echo Some steps could not be undone. Please send this folder to Delanclip Support.')
    $lines.Add(') else (')
    $lines.Add('    echo Done. Your previous settings are back. Restart Windows to finish.')
    $lines.Add(')')
    $lines.Add('if "%QUIET%"=="0" pause')
    $lines.Add('exit /b %FAILED%')
    $path = Join-Path $backupDir 'UNDO.cmd'
    [System.IO.File]::WriteAllText($path, (($lines -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
    Write-ToolLog ('  UNDO.cmd written: ' + $path)
}

function Get-LatestBackup {
    # The most recent run folder (DELANCLIP folder first, then the Desktop
    # itself for folders written by older versions, which were named
    # DelanCam1-FixTool-backup-<stamp>) that still has an unused UNDO.cmd.
    # A used one is renamed to UNDO-done.cmd and is never offered again.
    $dirs = @()
    foreach ($root in @($outRoot, $desktop)) {
        try { $dirs += @(Get-ChildItem -LiteralPath $root -Directory -Filter ($runPrefix + '*') -ErrorAction Stop) } catch {}
    }
    $candidates = @()
    foreach ($d in $dirs) {
        if ($d.FullName -eq $runDir) { continue }
        if ($d.Name -notmatch '(\d{8}-\d{6})$') { continue }
        $when = $Matches[1]
        if (-not (Test-Path -LiteralPath (Join-Path $d.FullName 'UNDO.cmd'))) { continue }
        $candidates += [pscustomobject]@{ Stamp = $when; Path = $d.FullName }
    }
    if ($candidates.Count -eq 0) { return $null }
    return ($candidates | Sort-Object Stamp -Descending | Select-Object -First 1).Path
}

function Invoke-UndoFlow {
    param([string]$Folder)
    $undoPath = Join-Path $Folder 'UNDO.cmd'
    Write-Screen ''
    Write-Screen ('Undoing the repair saved in: ' + $Folder)
    $code = Invoke-UndoScript $undoPath
    if ($code -eq 0) {
        try {
            Rename-Item -LiteralPath $undoPath -NewName 'UNDO-done.cmd' -Force -ErrorAction Stop
            [System.IO.File]::WriteAllText((Join-Path $Folder 'UNDONE.txt'), ('This repair was undone on ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ". UNDO.cmd was renamed to UNDO-done.cmd so it is not offered again.`r`n"), (New-Object System.Text.UTF8Encoding($false)))
            Write-ToolLog ('  marked as undone: ' + $Folder)
        }
        catch { Write-ToolLog ('  could not mark the folder as undone: ' + $_.Exception.Message) }
        Write-Screen 'Done. Your previous Windows settings are back.' 'Green'
        Write-Screen 'Restart Windows (use Restart, not Shut down) to finish.'
    }
    else {
        Write-Screen 'Some steps could not be undone. Please send that folder to Delanclip Support.' 'Red'
    }
    return $code
}

function Write-FixToolSummary {
    # Appends the Fix Tool outcome to SUMMARY.txt, so support reads one file first.
    param([string]$Outcome)
    $path = Join-Path $runDir 'SUMMARY.txt'
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('')
    $lines.Add('FIX TOOL')
    $lines.Add('Fix Tool version: ' + $toolVersion + '   Administrator: ' + $isAdmin + '   Mode: ' + $mode)
    $lines.Add('Outcome: ' + $Outcome)
    if ($null -ne $script:Probe) { $lines.Add('Camera probe verdict: ' + (Get-ProbeVerdict $script:Probe) + ' (' + (Get-ProbeSentence $script:Probe) + ')') }
    $shown = 0
    foreach ($f in $script:Findings) {
        if ($f.Severity -eq 'INFO') { continue }
        $lines.Add('  [' + $f.Severity + '] ' + $f.Id + ': ' + $f.Text)
        $shown++
    }
    if ($shown -eq 0) { $lines.Add('  No findings in the last detection pass.') }
    if ($script:AppliedAreas.Count -gt 0) { $lines.Add('Repaired areas: ' + ((@($script:AppliedAreas.Keys) | Sort-Object) -join ', ') + '. The registry backups and UNDO.cmd are in this folder.') }
    $lines.Add('Full detail: LOG.txt in this folder.')
    try { [System.IO.File]::AppendAllText($path, (($lines -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($false))) } catch {}
}

function Complete-Run {
    # Writes the outcome into SUMMARY.txt, zips the run folder into the report
    # for support and opens the DELANCLIP folder. Runs once per run.
    param([string]$Outcome)
    if ($script:RunCompleted) { return }
    $script:RunCompleted = $true
    if ($script:DiagCollected) { Write-FixToolSummary $Outcome }
    Write-ToolLog ('Outcome: ' + $Outcome)
    Write-ToolLog ('Finished: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'))
    $zipOk = $false
    if ($script:DiagCollected) {
        try {
            if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
            Compress-Archive -Path (Join-Path $runDir '*') -DestinationPath $zipPath -CompressionLevel Optimal -Force
            $zipOk = (Test-Path -LiteralPath $zipPath)
        }
        catch { Write-ToolLog ('  ZIP failed: ' + $_.Exception.Message) }
    }
    Write-Screen ''
    if ($zipOk) { Write-Screen ('Report for Delanclip Support (send it only if the camera still does not work): ' + (Split-Path $zipPath -Leaf) + ' in the DELANCLIP folder on your Desktop.') }
    else { Write-Screen ('The report could not be zipped. If Delanclip Support asks for it, send them this folder: ' + $runDir) 'Yellow' }
    Open-OutputFolder
}

function Open-OutputFolder {
    # Shows the DELANCLIP folder so the results can be found on a cluttered Desktop.
    try { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $outRoot + '"') -ErrorAction Stop | Out-Null } catch {}
}

function Write-NextSteps {
    param([bool]$NeedRestart)
    Write-Screen ''
    Write-Screen 'WHAT TO DO NEXT' 'Cyan'
    if ($NeedRestart) {
        Write-Screen '  1. Restart Windows. Use "Restart", not "Shut down": the repair only takes full effect after a real restart.'
        if ($script:FastStartup) { Write-Screen '     (This PC has Fast Startup on, so "Shut down" would keep the old state in memory.)' }
        Write-Screen '  2. After the restart, start OpenTrack, pick DelanCam1 again in the camera list and press Start.'
        Write-Screen '  3. If it still does not work, send the report ZIP from the DELANCLIP folder on your Desktop to Delanclip Support.'
    }
    else {
        Write-Screen '  1. Close and reopen OpenTrack or AITrack, pick DelanCam1 again in the camera list and press Start.'
        Write-Screen '  2. If it still does not work, restart Windows and send the report ZIP from the DELANCLIP folder on your Desktop to Delanclip Support.'
    }
}

# ------------------------------------------------------- diagnostics module
# The complete DelanCam1 Diagnostics collector (last standalone version 1.4.3)
# runs as the first pass of this tool and writes the same report files into
# the run folder. The steps are unchanged apart from the report README, the
# /skipprobe switch and the log lines.

function Invoke-DiagnosticsCollection {
    param([string]$Work)
    $work = $Work
    $script:toolStartTime = Get-Date
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

$script:stepIndex = 0
$script:stepTotal = 0
try {
    $scriptText = Get-Content -LiteralPath $env:DELAN_SCRIPT -Raw -ErrorAction Stop
    $script:stepTotal = [regex]::Matches($scriptText, "(?m)^Run-Step '").Count
    $scriptText = $null
}
catch {}
if ($script:stepTotal -lt 1) { $script:stepTotal = 30 }

function Run-Step {
    param([string]$Name, [scriptblock]$Action)
    $script:stepIndex++
    $label = "[{0,2}/{1}] {2}" -f $script:stepIndex, $script:stepTotal, $Name
    $percent = [math]::Min(100, [int](($script:stepIndex - 1) * 100 / $script:stepTotal))
    try { Write-Progress -Activity 'Delanclip DelanCam1 Diagnostics' -Status $label -PercentComplete $percent } catch {}
    Write-Host ("  {0,-50}" -f $label) -NoNewline
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        & $Action
        Write-Host ("done ({0,4:N1} s)" -f $sw.Elapsed.TotalSeconds) -ForegroundColor Green
        Write-ToolLog ('  ' + $label + ': done ({0:N1} s)' -f $sw.Elapsed.TotalSeconds)
    }
    catch {
        Record-Error -Step $Name -Err $_
        Write-Host ("failed ({0,4:N1} s), see errors.txt" -f $sw.Elapsed.TotalSeconds) -ForegroundColor Yellow
        Write-ToolLog ('  ' + $label + ': FAILED: ' + $_.Exception.Message)
    }
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
Delanclip DelanCam1 Fix Tool - report
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
Administrator: $isAdmin
Tool version: $script:toolVersion

Purpose:
Collect Windows evidence that can explain DelanCam1 detection, driver, USB, privacy, security-software and application conflicts, then repair the known Windows video-pipeline damage (Media Foundation hardware decoder switch, VFW codec entries, dead DirectShow registrations, decoder preferences, Frame Server service). What the Fix Tool found and changed is under FIX TOOL in SUMMARY.txt and in LOG.txt; the registry backups and UNDO.cmd sit next to this file.

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
- recent camera-related Windows event logs (events from before the tool
  started listed separately from the ones the run generated) and matching
  application errors
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
- the camera's exposure and image-control values at the moment it was
  opened (numbers only)
- the USB path DelanCam1 is connected through: host controller, any hub in
  between and the other USB devices sharing that controller
- a USB port map: every present USB device grouped by host controller and
  hub chain, so a camera behind a hub can be moved once to a known direct port
- three re-open cycles after the format probe (same format, stop between
  each) to tell a camera that dies after its first stop from one that
  restarts cleanly; only frame counts are kept
- USB and Plug and Play warnings and errors from the System event log
- kernel filter drivers attached to the camera device classes and to
  DelanCam1, with file paths and signers
- computer name, model, mainboard, a masked BIOS serial number and the
  Windows installation date, so a report can be tied to the machine it
  came from
- a short diagnostic summary

Not collected:
- camera images or video
- command lines of running processes
- browser history
- passwords
- emails
- personal documents, photos or their contents
- Microsoft Defender threat history or antivirus scan contents

The tool does not change drivers, stop applications, alter privacy settings, install software or make network connections. Its repairs are registry changes only, each exported to a .reg file first and reversible with UNDO.cmd.
"@ | Set-Content -LiteralPath (Join-Path $work 'README.txt') -Encoding UTF8
}

$script:machineLine = ''
$script:machineFingerprint = ''
Run-Step 'Windows information' {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $board = $null
    $bios = $null
    try { $board = Get-CimInstance Win32_BaseBoard -ErrorAction Stop } catch {}
    try { $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop } catch {}
    $serialRaw = ''
    if ($bios -and $bios.SerialNumber) { $serialRaw = ([string]$bios.SerialNumber).Trim() }
    $serialMasked = '(not reported)'
    if ($serialRaw.Length -gt 6) { $serialMasked = $serialRaw.Substring(0, 2) + '...' + $serialRaw.Substring($serialRaw.Length - 4) }
    elseif ($serialRaw.Length -gt 0) { $serialMasked = '...' + $serialRaw.Substring([math]::Max(0, $serialRaw.Length - 2)) }
    $installDate = ''
    try { $installDate = ([DateTime]$os.InstallDate).ToString('yyyy-MM-dd') } catch {}
    $boardText = ''
    if ($board) { $boardText = (([string]$board.Manufacturer).Trim() + ' ' + ([string]$board.Product).Trim()).Trim() }
    $fpSource = "$env:COMPUTERNAME|$serialRaw|$installDate|$($cs.Manufacturer)|$($cs.Model)|$boardText"
    try {
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $hash = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($fpSource))
        $script:machineFingerprint = ([BitConverter]::ToString($hash) -replace '-', '').Substring(0, 8).ToLower()
    }
    catch { $script:machineFingerprint = 'n/a' }
    $script:machineLine = "$env:COMPUTERNAME | $($cs.Manufacturer) $($cs.Model) | board $boardText | Windows $($os.Version) installed $installDate | fingerprint $script:machineFingerprint"
    [PSCustomObject]@{
        Caption = $os.Caption
        Version = $os.Version
        BuildNumber = $os.BuildNumber
        OSArchitecture = $os.OSArchitecture
        InstallDate = $installDate
        LastBootUpTime = $os.LastBootUpTime
        ComputerName = $env:COMPUTERNAME
        Manufacturer = $cs.Manufacturer
        Model = $cs.Model
        BaseBoard = $boardText
        BiosSerialMasked = $serialMasked
        MachineFingerprint = $script:machineFingerprint
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

$script:usbHubsInPath = @()
$script:usbControllerName = ''
$script:usbSiblingCount = -1
$script:usbSiblingNames = @()
$script:usbSelectiveSuspendAc = $null
Run-Step 'DelanCam1 USB path' {
    $path = Join-Path $work 'usb-path.txt'
    $topoPath = Join-Path $work 'usb-topology.txt'
    if ($script:delanCams.Count -eq 0) {
        'No DelanCam1 device available for USB parent-chain collection.' | Set-Content -LiteralPath $path -Encoding UTF8
        'No DelanCam1 device available for USB topology analysis.' | Set-Content -LiteralPath $topoPath -Encoding UTF8
        return
    }
    foreach ($device in $script:delanCams) {
        Add-Content -LiteralPath $path -Value ("===== " + $device.FriendlyName + " =====") -Encoding UTF8
        Get-DeviceParentChain -InstanceId $device.InstanceId |
            Add-Content -LiteralPath $path -Encoding UTF8
    }

    $topo = New-Object System.Collections.Generic.List[string]
    $topo.Add('DelanCam1 USB topology')
    $topo.Add('')
    $topo.Add('Which host controller DelanCam1 hangs off, whether a hub sits between the camera and the root hub, and which')
    $topo.Add('other USB devices share that controller. Isochronous video (what a camera sends) has no retransmission, so')
    $topo.Add('every extra hop and every busy neighbour matters more than it does for keyboards or storage.')
    $topo.Add('')

    $device = $script:delanCams[0]
    $current = $device.InstanceId
    $seen = @{}
    $chain = @()
    for ($depth = 0; $depth -lt 12; $depth++) {
        if ([string]::IsNullOrWhiteSpace($current) -or $seen.ContainsKey($current)) { break }
        $seen[$current] = $true
        $dev = $null
        try { $dev = Get-PnpDevice -InstanceId $current -ErrorAction Stop } catch {}
        $loc = @(Get-DevicePropertyData -InstanceId $current -KeyName 'DEVPKEY_Device_LocationPaths')
        $busDesc = Get-DevicePropertyData -InstanceId $current -KeyName 'DEVPKEY_Device_BusReportedDeviceDesc'
        $name = ''
        $class = ''
        if ($dev) { $name = [string]$dev.FriendlyName; $class = [string]$dev.Class }
        $chain += [PSCustomObject]@{ InstanceId = $current; Name = $name; Class = $class; BusDesc = [string]$busDesc; Location = [string]($loc | Select-Object -First 1) }
        $parent = Get-DevicePropertyData -InstanceId $current -KeyName 'DEVPKEY_Device_Parent'
        if ([string]::IsNullOrWhiteSpace([string]$parent)) { break }
        $current = [string]$parent
    }

    $controller = $null
    $hubs = @()
    foreach ($node in $chain) {
        if ($node.InstanceId -match '(?i)^USB\\ROOT_HUB') { continue }
        if ($node.InstanceId -match '(?i)^USB\\VID_' -and $node.InstanceId -notmatch '(?i)VID_0120&PID_1234') { $hubs += $node; continue }
        if ($node.InstanceId -match '(?i)^PCI\\' -and $null -eq $controller -and $node.Class -match '(?i)USB') { $controller = $node }
    }
    if (-not $controller) {
        foreach ($node in $chain) { if ($node.InstanceId -match '(?i)^PCI\\') { $controller = $node; break } }
    }

    $topo.Add('Chain from the camera upwards:')
    foreach ($node in $chain) {
        $label = $node.Name
        if ($node.BusDesc -and $node.BusDesc -ne $node.Name) { $label = "$label ($($node.BusDesc))" }
        $topo.Add("  - $label  [$($node.InstanceId)]")
    }
    $topo.Add('')
    if ($controller) {
        $script:usbControllerName = $controller.Name
        $topo.Add("Host controller: $($controller.Name)  [$($controller.InstanceId)]")
    }
    else { $topo.Add('Host controller: could not be identified from the parent chain.') }
    if ($hubs.Count -gt 0) {
        foreach ($h in $hubs) {
            $hl = $h.Name
            if ($h.BusDesc) { $hl = "$hl ($($h.BusDesc))" }
            $script:usbHubsInPath += $hl
        }
        $topo.Add('Hub(s) between DelanCam1 and the root hub: ' + ($script:usbHubsInPath -join '; '))
        $topo.Add('Note: an external hub, a monitor hub or a front-panel header appears here, but so does the internal hub that')
        $topo.Add('some motherboard chipsets (for example AMD chipset ports, ASMedia ASM107x) put behind their rear USB ports.')
        $topo.Add('A CPU-connected rear port shows no hub on this list.')
    }
    else { $topo.Add('Hub(s) between DelanCam1 and the root hub: none (the camera sits directly on a root hub port)') }
    $topo.Add('')

    if ($controller -and $controller.Location) {
        $prefix = $controller.Location
        $siblings = New-Object System.Collections.Generic.List[string]
        $chainIds = @($chain | ForEach-Object { $_.InstanceId })
        $candidates = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match '(?i)^USB\\VID_' -and $_.InstanceId -notmatch '(?i)&MI_[0-9A-F][0-9A-F]' })
        foreach ($cand in $candidates) {
            if ($chainIds -contains $cand.InstanceId) { continue }
            $cl = @(Get-DevicePropertyData -InstanceId $cand.InstanceId -KeyName 'DEVPKEY_Device_LocationPaths')
            $first = [string]($cl | Select-Object -First 1)
            if ($first -and $first.StartsWith($prefix + '#USBROOT', [System.StringComparison]::OrdinalIgnoreCase)) {
                $idShort = $cand.InstanceId
                if ($idShort -match '(?i)(VID_[0-9A-F]{4}&PID_[0-9A-F]{4})') { $idShort = $matches[1] }
                $siblings.Add("$($cand.FriendlyName) [$idShort]")
            }
        }
        $script:usbSiblingCount = $siblings.Count
        $script:usbSiblingNames = @($siblings)
        $topo.Add("Other USB devices on the same host controller: $($siblings.Count)")
        foreach ($s in $siblings) { $topo.Add("  - $s") }
    }
    else { $topo.Add('Other USB devices on the same host controller: not determined (controller location unknown)') }
    $topo | Set-Content -LiteralPath $topoPath -Encoding UTF8
}

$script:usbPortMapSummary = @()
Run-Step 'USB port map' {
    $path = Join-Path $work 'usb-port-map.txt'
    $out = New-Object System.Collections.Generic.List[string]
    $out.Add('USB port map')
    $out.Add('')
    $out.Add('Every present USB device grouped by host controller, with the hub chain between the device and the root hub.')
    $out.Add('"direct" means the device sits on a root-hub port with no hub in between; on desktop boards those are usually')
    $out.Add('the ports wired to the CPU. A camera moved to the port that a direct device uses today gets the same clean path,')
    $out.Add('so one targeted swap replaces trying every port in turn.')
    $out.Add('')

    $parentCache = @{}
    $nameCache = @{}
    $devices = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match '(?i)^USB\\VID_' -and $_.InstanceId -notmatch '(?i)&MI_[0-9A-F][0-9A-F]' })
    $entries = @()
    foreach ($d in $devices) {
        $hubs = @()
        $controllerName = ''
        $controllerId = ''
        $current = [string]$d.InstanceId
        $seen = @{}
        for ($depth = 0; $depth -lt 12; $depth++) {
            if ([string]::IsNullOrWhiteSpace($current) -or $seen.ContainsKey($current)) { break }
            $seen[$current] = $true
            if (-not $parentCache.ContainsKey($current)) { $parentCache[$current] = [string](Get-DevicePropertyData -InstanceId $current -KeyName 'DEVPKEY_Device_Parent') }
            $parent = [string]$parentCache[$current]
            if ([string]::IsNullOrWhiteSpace($parent)) { break }
            if (-not $nameCache.ContainsKey($parent)) {
                $pn = $parent
                try { $pn = [string](Get-PnpDevice -InstanceId $parent -ErrorAction Stop).FriendlyName } catch {}
                if ([string]::IsNullOrWhiteSpace($pn)) { $pn = $parent }
                $nameCache[$parent] = $pn
            }
            if ($parent -match '(?i)^USB\\VID_') { $hubs += [string]$nameCache[$parent] }
            elseif ($parent -match '(?i)^PCI\\') { $controllerName = [string]$nameCache[$parent]; $controllerId = $parent; break }
            $current = $parent
        }
        $busDesc = [string](Get-DevicePropertyData -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_BusReportedDeviceDesc')
        $label = [string]$d.FriendlyName
        if ($busDesc -and $busDesc -ne $label) { $label = "$label ($busDesc)" }
        $entries += [PSCustomObject]@{
            Label = $label
            Id = [string]$d.InstanceId
            Controller = $controllerName
            ControllerId = $controllerId
            Hubs = @($hubs)
            HubCount = @($hubs).Count
            IsHub = ([string]$d.FriendlyName -match '(?i)\bhub\b')
            IsDelan = ([string]$d.InstanceId -match '(?i)VID_0120&PID_1234')
        }
    }

    foreach ($g in ($entries | Group-Object ControllerId)) {
        $cname = [string](($g.Group | Select-Object -First 1).Controller)
        if (-not $cname) { $cname = 'unknown controller' }
        $out.Add("===== $cname =====")
        if ($g.Name) { $out.Add("  [$($g.Name)]") }
        foreach ($e in ($g.Group | Sort-Object HubCount, Label)) {
            $pathText = if ($e.HubCount -eq 0) { 'direct' } else { 'via ' + ($e.Hubs -join ' > ') }
            $mark = if ($e.IsDelan) { '   <== DelanCam1' } else { '' }
            $out.Add(('  - {0}: {1}{2}' -f $e.Label, $pathText, $mark))
        }
        $out.Add('')
    }

    $delan = $entries | Where-Object { $_.IsDelan } | Select-Object -First 1
    $directOthers = @($entries | Where-Object { -not $_.IsDelan -and -not $_.IsHub -and $_.HubCount -eq 0 })
    $inputPattern = '(?i)keyboard|mouse|input|clavier|souris|tastatur|maus|teclado|raton|klawiatur|mysz'
    $preferred = @($directOthers | Where-Object { $_.Label -match $inputPattern }) + @($directOthers | Where-Object { $_.Label -notmatch $inputPattern })
    $advice = ''
    if ($delan) {
        if ($delan.HubCount -eq 0) {
            $advice = 'USB port map: DelanCam1 already sits on a direct root-hub port, so moving it for the sake of a cleaner USB path is not needed. See usb-port-map.txt.'
        }
        elseif ($preferred.Count -gt 0) {
            $advice = 'USB port map: DelanCam1 goes through a hub, while ' + $preferred[0].Label + ' sits on a direct port. One targeted move instead of trying every port: swap DelanCam1 into the port that device uses now, and that device into the camera port. See usb-port-map.txt.'
        }
        else {
            $advice = 'USB port map: every present USB device on this PC goes through a hub, so no port is known to be direct. See usb-port-map.txt.'
        }
    }
    else {
        $advice = 'USB port map: DelanCam1 is not present, so no move can be suggested. See usb-port-map.txt for the ports the other devices use.'
    }
    $out.Add($advice)
    $script:usbPortMapSummary += $advice
    $out | Set-Content -LiteralPath $path -Encoding UTF8
}
$script:cameraControlsRead = $false
$script:cameraControls = @()
$script:exposureManual = $false
$script:exposureNearMax = $false
$script:exposureText = ''
$script:exposureControlMs = -1
$script:exposureControlAuto = $null
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
$script:streamTestSubtype = ''
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

    if ($skipProbe) {
        $lines.Add('Skipped by the /skipprobe switch: the camera was not opened.')
        $lines | Set-Content -LiteralPath $path -Encoding UTF8
        return
    }
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

        # Read the camera's image and exposure controls at the moment of opening. Only numbers are kept.
        try {
            $vdc = $mediaCapture.VideoDeviceController
            $ctrlLines = New-Object System.Collections.Generic.List[string]
            $ctrlLines.Add('Delanclip DelanCam1 Camera Controls')
            $ctrlLines.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')")
            $ctrlLines.Add('')
            $ctrlLines.Add('Image and exposure controls as Windows reported them when the camera was opened for the stream test.')
            $ctrlLines.Add('Drivers keep these values between sessions. A manual exposure near its maximum can by itself cut the')
            $ctrlLines.Add('frame rate to about 1 FPS and wash the picture out, which looks exactly like a USB or hardware fault.')
            $ctrlLines.Add('Legacy Exposure values follow the UVC convention: log2 of the exposure time in seconds (-6 is 1/64 s, 0 is 1 s).')
            $ctrlLines.Add('')
            $ctrlLines.Add(('{0,-22} {1,-9} {2,-6} {3,-9} {4,-9} {5,-8} {6,-8} {7}' -f 'Control', 'Supported', 'Auto', 'Value', 'Default', 'Min', 'Max', 'Step'))
            foreach ($ctrlName in @('Exposure', 'Brightness', 'Contrast', 'WhiteBalance', 'BacklightCompensation', 'Hue', 'Focus', 'Zoom', 'Pan', 'Tilt', 'Roll')) {
                try {
                    $ctrl = $vdc.$ctrlName
                    if ($null -eq $ctrl) { $ctrlLines.Add(('{0,-22} {1}' -f $ctrlName, 'not exposed')); continue }
                    $cap = $ctrl.Capabilities
                    $supported = $false
                    if ($cap) { $supported = [bool]$cap.Supported }
                    if (-not $supported) { $ctrlLines.Add(('{0,-22} {1,-9}' -f $ctrlName, 'False')); continue }
                    $val = [double]0
                    $gotVal = $false
                    try { $gotVal = [bool]$ctrl.TryGetValue([ref]$val) } catch { $gotVal = $false }
                    $autoText = 'n/a'
                    $autoOn = $null
                    if ($cap.AutoModeSupported) {
                        $auto = $false
                        $gotAuto = $false
                        try { $gotAuto = [bool]$ctrl.TryGetAuto([ref]$auto) } catch { $gotAuto = $false }
                        if ($gotAuto) { $autoOn = [bool]$auto; $autoText = [string]$autoOn } else { $autoText = '?' }
                    }
                    $valText = '?'
                    if ($gotVal) { $valText = [string]$val }
                    $ctrlLines.Add(('{0,-22} {1,-9} {2,-6} {3,-9} {4,-9} {5,-8} {6,-8} {7}' -f $ctrlName, 'True', $autoText, $valText, $cap.Default, $cap.Min, $cap.Max, $cap.Step))
                    $script:cameraControls += [PSCustomObject]@{ Name = $ctrlName; Value = $val; GotValue = $gotVal; Auto = $autoOn; Min = [double]$cap.Min; Max = [double]$cap.Max; Step = [double]$cap.Step; Default = [double]$cap.Default }
                    if ($ctrlName -eq 'Exposure' -and $gotVal) {
                        $script:exposureText = "value $val, auto $autoText, range $($cap.Min) to $($cap.Max), default $($cap.Default)"
                        if ($autoOn -eq $false) {
                            $script:exposureManual = $true
                            $stepSize = [double]$cap.Step
                            if ($stepSize -le 0) { $stepSize = 1 }
                            if ($val -ge ([double]$cap.Max - $stepSize)) { $script:exposureNearMax = $true }
                        }
                    }
                }
                catch { $ctrlLines.Add(('{0,-22} error: {1}' -f $ctrlName, $_.Exception.Message)) }
            }
            $ctrlLines.Add('')
            try {
                $ec = $vdc.ExposureControl
                if ($ec -and $ec.Supported) {
                    $ecMs = [math]::Round(([TimeSpan]$ec.Value).TotalMilliseconds, 2)
                    $ecMin = [math]::Round(([TimeSpan]$ec.Min).TotalMilliseconds, 2)
                    $ecMax = [math]::Round(([TimeSpan]$ec.Max).TotalMilliseconds, 2)
                    $script:exposureControlMs = $ecMs
                    $script:exposureControlAuto = [bool]$ec.Auto
                    $ctrlLines.Add("ExposureControl: supported, auto $($ec.Auto), exposure time $ecMs ms (range $ecMin to $ecMax ms)")
                }
                else { $ctrlLines.Add('ExposureControl: not supported by this driver (the legacy Exposure row above applies)') }
            }
            catch { $ctrlLines.Add("ExposureControl: error: $($_.Exception.Message)") }
            try {
                [Windows.Media.Capture.PowerlineFrequency,Windows.Media.Capture,ContentType=WindowsRuntime] | Out-Null
                $plf = [Windows.Media.Capture.PowerlineFrequency]::Disabled
                $gotPlf = [bool]$vdc.TryGetPowerlineFrequency([ref]$plf)
                if ($gotPlf) { $ctrlLines.Add("Powerline frequency (anti-flicker): $plf") } else { $ctrlLines.Add('Powerline frequency (anti-flicker): not reported') }
            }
            catch { $ctrlLines.Add("Powerline frequency: error: $($_.Exception.Message)") }
            $script:cameraControlsRead = $true
            $ctrlLines | Set-Content -LiteralPath (Join-Path $work 'camera-controls.txt') -Encoding UTF8
        }
        catch { Record-Error -Step 'DelanCam1 camera controls' -Err $_ }

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
        $script:streamTestSubtype = [string]$current.Subtype
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
$script:formatProbeRowResults = @()
$script:formatProbeVerdict = 'not-run'
$script:formatProbeRowText = ''
$script:reopenCycleFrames = @()
$script:reopenVerdict = 'not-run'
$script:reopenText = ''
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
    $reopenFormat = 'MJPG 640x480@60'
    $reopenCount = 3
    $plan = @()
    foreach ($w in $wanted) { $plan += [PSCustomObject]@{ Format = $w; Tag = '' } }
    for ($ci = 1; $ci -le $reopenCount; $ci++) { $plan += [PSCustomObject]@{ Format = $reopenFormat; Tag = "re-open $ci" } }
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

        foreach ($item in $plan) {
            $want = [string]$item.Format
            $tag = [string]$item.Tag
            if ($tag -eq 're-open 1') {
                $lines.Add('')
                $lines.Add("Re-open cycles: $reopenFormat opened $reopenCount more times with a stop between each, $probeSeconds s each.")
                $lines.Add('A healthy camera streams in every cycle. A camera that streamed in the stream test and now delivers one')
                $lines.Add('frame or nothing loses its stream after the first stop; only a power cut restores it.')
            }
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
            $lines.Add(('{0,-18} {1,-18} {2,-8} {3,-8} {4,6} {5,8}  {6}' -f $(if ($tag) { $tag } else { $want }), $row.Negotiated, $row.SetFmt, $row.Start, $row.Frames, $row.FirstMs, $row.Error))
            if ($tag) {
                $script:reopenCycleFrames += [int]$row.Frames
            }
            else {
                $script:formatProbeRows++
                if ($want -like 'MJPG*') { $script:formatProbeMjpgFrames += $row.Frames } else { $script:formatProbeRawFrames += $row.Frames }
                $script:formatProbeRowResults += [PSCustomObject]@{ Format = $want; Kind = $(if ($want -like 'MJPG*') { 'MJPG' } else { 'RAW' }); Frames = [int]$row.Frames; Error = [string]$row.Error }
            }
            Start-Sleep -Milliseconds 300
        }

        $lines.Add('')
        $lines.Add("MJPG frames total: $script:formatProbeMjpgFrames   NV12/YUY2 frames total: $script:formatProbeRawFrames")

        # Verdict per row, not per total. A decoder fault fails every MJPEG row and none of the raw rows;
        # anything less regular is the camera or its USB link starting erratically.
        $healthyRowFrames = 5
        $mjpgRows = @($script:formatProbeRowResults | Where-Object { $_.Kind -eq 'MJPG' })
        $rawRows = @($script:formatProbeRowResults | Where-Object { $_.Kind -eq 'RAW' })
        $mjpgAllZero = ($mjpgRows.Count -gt 0) -and (@($mjpgRows | Where-Object { $_.Frames -gt 0 }).Count -eq 0)
        $rawAllHealthy = ($rawRows.Count -gt 0) -and (@($rawRows | Where-Object { $_.Frames -lt $healthyRowFrames }).Count -eq 0)
        $rawAllZero = ($rawRows.Count -gt 0) -and (@($rawRows | Where-Object { $_.Frames -gt 0 }).Count -eq 0)
        $mjpgAllHealthy = ($mjpgRows.Count -gt 0) -and (@($mjpgRows | Where-Object { $_.Frames -lt $healthyRowFrames }).Count -eq 0)
        $weakRows = @($script:formatProbeRowResults | Where-Object { $_.Frames -lt $healthyRowFrames })
        $streamMjpgHealthy = ($script:streamTestOpened -and $script:streamTestSubtype -match '(?i)MJPG' -and $script:streamTestFramesReceived -ge $healthyRowFrames)
        $script:formatProbeRowText = (($script:formatProbeRowResults | ForEach-Object { '{0} {1}' -f $_.Format, $_.Frames }) -join ', ')

        if ($script:formatProbeRowResults.Count -eq 0) { $script:formatProbeVerdict = 'no-rows' }
        elseif ($mjpgAllHealthy -and $rawAllHealthy) { $script:formatProbeVerdict = 'healthy' }
        elseif ($script:formatProbeMjpgFrames -eq 0 -and $rawAllZero) { $script:formatProbeVerdict = 'all-zero' }
        elseif ($mjpgAllZero -and $rawAllHealthy -and (-not $streamMjpgHealthy)) { $script:formatProbeVerdict = 'mjpeg-only-fails' }
        elseif ($mjpgAllZero -and $rawAllHealthy -and $streamMjpgHealthy) { $script:formatProbeVerdict = 'intermittent-start' }
        elseif ($rawAllZero -and $mjpgAllHealthy) { $script:formatProbeVerdict = 'raw-only-fails' }
        else { $script:formatProbeVerdict = 'erratic' }

        $lines.Add("Per-row result: $script:formatProbeRowText")
        switch ($script:formatProbeVerdict) {
            'healthy' {
                $lines.Add('Reading: frames arrived in MJPEG and raw formats. The Media Foundation path to this camera is healthy.')
            }
            'all-zero' {
                $lines.Add('Reading: no format delivered frames. This points to USB, cable, driver or hardware, or to another')
                $lines.Add('application holding the camera (see camera-access-history.txt for an app with a start time and no stop).')
            }
            'mjpeg-only-fails' {
                $lines.Add('Reading: every raw row streamed normally and every MJPEG row delivered nothing, and the stream test did')
                $lines.Add('not get MJPEG frames either. That is a Windows-side MJPEG decoding problem (see media-foundation.txt),')
                $lines.Add('not a camera or USB fault. Apps that pick raw formats (Windows Camera) keep working; apps that ask for')
                $lines.Add('MJPEG (OpenTrack, AITrack) get nothing.')
            }
            'intermittent-start' {
                $lines.Add("Reading: the stream test received $script:streamTestFramesReceived MJPEG frames seconds before this probe, yet every MJPEG row")
                $lines.Add('now delivers nothing while raw rows stream. A broken decoder fails every time; this is a camera that')
                $lines.Add('starts only sometimes. Treat it as an intermittent start, not as an MJPEG decoder fault.')
            }
            'raw-only-fails' {
                $lines.Add('Reading: MJPEG delivered frames but the raw formats did not. Unusual; the raw path is not what head')
                $lines.Add('tracking uses, but an erratic camera start cannot be ruled out.')
            }
            'erratic' {
                $lines.Add('Reading: the rows are inconsistent (' + (($weakRows | ForEach-Object { '{0} {1}' -f $_.Format, $_.Frames }) -join ', ') + ' below ' + $healthyRowFrames + ' frames).')
                $lines.Add('A decoder problem fails the same format every time; a camera that streams in one row and delivers')
                $lines.Add('nothing or a single frame in the next is starting erratically. That lives in the USB isochronous')
                $lines.Add('link, the cable or the camera itself, not in Windows decoders. The same probe from this tool on a')
                $lines.Add('second computer tells whether it follows the camera.')
            }
            default {
                $lines.Add('Reading: no format could be probed. See the rows above.')
            }
        }

        # Re-open cycles: does the camera restart its stream after a stop? The stream test is cycle 0.
        $streamCycleFrames = -1
        if ($script:streamTestOpened -and $script:streamTestSubtype -match '(?i)MJPG') { $streamCycleFrames = [int]$script:streamTestFramesReceived }
        if ($script:reopenCycleFrames.Count -gt 0) {
            $cyclesHealthy = @($script:reopenCycleFrames | Where-Object { $_ -ge $healthyRowFrames }).Count
            $script:reopenText = 'stream test ' + $(if ($streamCycleFrames -ge 0) { [string]$streamCycleFrames } else { 'n/a' }) + ', then ' + ($script:reopenCycleFrames -join ', ')
            if ($cyclesHealthy -eq $script:reopenCycleFrames.Count) { $script:reopenVerdict = 'stable' }
            elseif ($cyclesHealthy -eq 0 -and $streamCycleFrames -ge $healthyRowFrames) { $script:reopenVerdict = 'dies-after-stop' }
            elseif ($cyclesHealthy -eq 0) { $script:reopenVerdict = 'dead-state' }
            else { $script:reopenVerdict = 'erratic' }
            $lines.Add('')
            $lines.Add("Re-open cycles ($reopenFormat): $script:reopenText")
            switch ($script:reopenVerdict) {
                'stable' {
                    $lines.Add('Reading: the camera restarts its stream cleanly after every stop.')
                }
                'dies-after-stop' {
                    $lines.Add('Reading: the camera streamed after power-up and lost its stream after the first stop; every re-open since')
                    $lines.Add('delivers one frame or nothing. That is the camera (firmware or sensor), not this PC. A power cut (unplug')
                    $lines.Add('for 10 minutes) restores it until the next stop.')
                }
                'dead-state' {
                    $lines.Add('Reading: the camera was already in its failed state when this tool started: one frame or nothing in the')
                    $lines.Add('stream test and in every cycle. Port tests in this state prove nothing. Unplug the camera for 10 minutes')
                    $lines.Add('with the PC left on, plug it back in and run this tool again from a fresh start.')
                }
                default {
                    $lines.Add('Reading: the re-open cycles are inconsistent; some restarts stream and some do not. USB link, cable or camera.')
                }
            }
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
$script:vfwNotShipped64 = @()
$script:vfwNotShipped32 = @()
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
        $sysDir = if ($view.Name -eq '64-bit') { Join-Path $env:windir 'System32' } else { Join-Path $env:windir 'SysWOW64' }
        $missingAll = @($expectedVfw.Keys | Where-Object { -not $present.ContainsKey($_) } | Sort-Object)
        $missing = @($missingAll | Where-Object { Test-Path -LiteralPath (Join-Path $sysDir $expectedVfw[$_]) })
        $notShipped = @($missingAll | Where-Object { -not (Test-Path -LiteralPath (Join-Path $sysDir $expectedVfw[$_])) })
        if ($missing.Count -gt 0) { $lines.Add('Missing stock entries (DLL present in ' + $sysDir + ', registration gone): ' + ($missing -join ', ')) }
        if ($notShipped.Count -gt 0) { $lines.Add('Not registered and DLL not shipped in ' + $sysDir + ' (normal on this Windows build): ' + (($notShipped | ForEach-Object { $_ + ' (' + $expectedVfw[$_] + ')' }) -join ', ')) }
        if ($view.Name -eq '64-bit') { $script:vfwMissing64 = $missing; $script:vfwNotShipped64 = $notShipped } else { $script:vfwMissing32 = $missing; $script:vfwNotShipped32 = $notShipped }
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
$script:cameraUseRecords = @()
$script:cameraHeldByOtherApp = @()
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
                if ($startNum -gt 0) {
                    $appLabel = ($displayPath -split '[\\#]')[-1]
                    $startLocal = [DateTime]::FromFileTimeUtc($startNum).ToLocalTime()
                    $stopLocal = $null
                    if ($stopNum -gt $startNum) { $stopLocal = [DateTime]::FromFileTimeUtc($stopNum).ToLocalTime() }
                    $isThisTool = ($appLabel -match '(?i)^powershell\.exe$' -and $startLocal -ge $script:toolStartTime.AddSeconds(-5))
                    if (-not $isThisTool) {
                        $script:cameraUseRecords += [PSCustomObject]@{ App = $appLabel; Start = $startLocal; Stop = $stopLocal; Path = $displayPath }
                        if ($null -eq $stopLocal -and $startLocal -lt $script:toolStartTime) {
                            $script:cameraHeldByOtherApp += ('{0} since {1}' -f $appLabel, $startLocal.ToString('yyyy-MM-dd HH:mm:ss'))
                        }
                    }
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
$script:cameraEventCountBefore = 0
$script:cameraEventCountDuring = 0
Run-Step 'Camera event logs' {
    $path = Join-Path $work 'camera-event-logs.txt'
    $start = $script:toolStartTime.AddDays(-7)
    ('Tool started: ' + $script:toolStartTime.ToString('yyyy-MM-dd HH:mm:ss zzz') + '. Each log lists events from before the tool started first, then the events this run generated itself.') | Set-Content -LiteralPath $path -Encoding UTF8
    Add-Content -LiteralPath $path -Value '' -Encoding UTF8
    $logs = @(Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | Where-Object {
        $_.LogName -match '(?i)(camera|frameserver)' -and $_.IsEnabled
    })

    if ($logs.Count -eq 0) {
        'No enabled Windows event logs with Camera or FrameServer in the log name were found.' | Set-Content -LiteralPath $path -Encoding UTF8
    }
    else {
        foreach ($log in $logs) {
            Add-Content -LiteralPath $path -Value "===== $($log.LogName) =====" -Encoding UTF8
            $sections = @(
                @{ Title = ('--- Events BEFORE the tool started (up to 200, newest first, since ' + $start.ToString('yyyy-MM-dd HH:mm') + ') ---'); Filter = @{LogName=$log.LogName; StartTime=$start; EndTime=$script:toolStartTime}; Limit = 200; Bucket = 'before' },
                @{ Title = ('--- Events DURING this diagnostic run (from ' + $script:toolStartTime.ToString('yyyy-MM-dd HH:mm:ss') + ', generated by the stream test and probe; up to 100) ---'); Filter = @{LogName=$log.LogName; StartTime=$script:toolStartTime}; Limit = 100; Bucket = 'during' }
            )
            foreach ($section in $sections) {
                Add-Content -LiteralPath $path -Value $section.Title -Encoding UTF8
                try {
                    $events = @(Get-WinEvent -FilterHashtable $section.Filter -ErrorAction Stop | Select-Object -First $section.Limit)
                    if ($section.Bucket -eq 'before') { $script:cameraEventCountBefore += $events.Count } else { $script:cameraEventCountDuring += $events.Count }
                    $script:cameraEventCount += $events.Count
                    if ($events.Count -eq 0) {
                        Add-Content -LiteralPath $path -Value 'No events in this window.' -Encoding UTF8
                    }
                    else {
                        $events |
                            Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message |
                            Format-List |
                            Out-String -Width 500 |
                            Add-Content -LiteralPath $path -Encoding UTF8
                    }
                }
                catch {
                    if ($_.Exception.Message -match '(?i)No events were found') {
                        Add-Content -LiteralPath $path -Value 'No events in this window.' -Encoding UTF8
                    }
                    else { Record-Error -Step ("Camera event log " + $log.LogName) -Err $_ }
                }
                Add-Content -LiteralPath $path -Value '' -Encoding UTF8
            }
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
    $usbOut = @(& $powercfg /query SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 2>&1 | ForEach-Object { [string]$_ })
    ($usbOut -join "`r`n") | Add-Content -LiteralPath $path -Encoding UTF8
    $settingIdx = -1
    for ($i = 0; $i -lt $usbOut.Count; $i++) { if ($usbOut[$i] -match '(?i)48e6b7a6-50f5-4782-a5d4-53bb8f07e226') { $settingIdx = $i; break } }
    if ($settingIdx -ge 0) {
        $indexValues = @()
        for ($i = $settingIdx + 1; $i -lt $usbOut.Count; $i++) {
            if ($usbOut[$i] -match '(?i):\s*0x([0-9a-f]{8})\s*$') { $indexValues += [Convert]::ToInt32($matches[1], 16) }
            if ($indexValues.Count -ge 2) { break }
        }
        if ($indexValues.Count -ge 1) { $script:usbSelectiveSuspendAc = $indexValues[0] }
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

$script:usbEventErrors = 0
$script:usbEventCameraHits = 0
$script:usbEventTop = @()
Run-Step 'USB and PnP event log' {
    $path = Join-Path $work 'usb-events.txt'
    $out = New-Object System.Collections.Generic.List[string]
    $out.Add('USB and Plug and Play events from the Windows System log, last 14 days. Only event metadata and message text')
    $out.Add('are listed. Level: 1 critical, 2 error, 3 warning, 4 information.')
    $out.Add('')
    $start = (Get-Date).AddDays(-14)
    $providers = @('Microsoft-Windows-USB-USBHUB3', 'Microsoft-Windows-USB-USBXHCI', 'Microsoft-Windows-USB-USBHUB', 'Microsoft-Windows-USB-USBPORT', 'Microsoft-Windows-Kernel-PnP', 'Microsoft-Windows-DriverFrameworks-UserMode', 'Microsoft-Windows-Kernel-Power')
    $events = @()
    try { $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = $providers; StartTime = $start } -ErrorAction Stop) }
    catch { $events = @(); $out.Add("Get-WinEvent reported: $($_.Exception.Message)") }
    $rows = @(foreach ($e in $events) {
        $msg = ''
        try { $msg = [string]$e.Message } catch {}
        if ([string]::IsNullOrWhiteSpace($msg)) { try { $msg = (($e.Properties | ForEach-Object { [string]$_.Value }) -join ' ') } catch {} }
        [PSCustomObject]@{ Time = $e.TimeCreated; Id = [int]$e.Id; Level = [int]$e.Level; Provider = ([string]$e.ProviderName -replace '^Microsoft-Windows-', ''); Text = (($msg -replace '\s+', ' ').Trim()) }
    })
    $powerIds = @(41, 42, 107, 109, 187)
    $rows = @($rows | Where-Object { $_.Provider -ne 'Kernel-Power' -or ($powerIds -contains $_.Id) })
    $out.Add("Events collected: $($rows.Count)")
    $out.Add('')
    $out.Add('--- Counts by provider, event ID and level ---')
    $groups = @($rows | Group-Object Provider, Id, Level | Sort-Object Count -Descending)
    foreach ($g in $groups) { $out.Add(('{0,6}  {1}' -f $g.Count, $g.Name)) }
    $script:usbEventTop = @($groups | Select-Object -First 5 | ForEach-Object { "$($_.Name) x$($_.Count)" })
    $bad = @($rows | Where-Object { $_.Level -ge 1 -and $_.Level -le 3 })
    $cameraHits = @($bad | Where-Object { $_.Text -match '(?i)VID_0120|DelanCam' })
    $script:usbEventErrors = $bad.Count
    $script:usbEventCameraHits = $cameraHits.Count
    $out.Add('')
    $out.Add("--- Warnings and errors naming DelanCam1: $($cameraHits.Count) ---")
    foreach ($r in ($cameraHits | Select-Object -First 40)) { $out.Add(('{0:yyyy-MM-dd HH:mm:ss}  {1,-28} {2,5} L{3}  {4}' -f $r.Time, $r.Provider, $r.Id, $r.Level, $r.Text)) }
    $out.Add('')
    $out.Add("--- Most recent warnings and errors, any USB device: $($bad.Count) total, newest 60 listed ---")
    foreach ($r in ($bad | Sort-Object Time -Descending | Select-Object -First 60)) {
        $t = [string]$r.Text
        if ($t.Length -gt 300) { $t = $t.Substring(0, 300) + '...' }
        $out.Add(('{0:yyyy-MM-dd HH:mm:ss}  {1,-28} {2,5} L{3}  {4}' -f $r.Time, $r.Provider, $r.Id, $r.Level, $t))
    }
    $out | Set-Content -LiteralPath $path -Encoding UTF8
}

$script:classFilterFindings = @()
Run-Step 'Driver stack and class filters' {
    $path = Join-Path $work 'driver-stack.txt'
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('Kernel filter drivers attached to the camera device classes and to DelanCam1, plus the driver stack Windows')
    $lines.Add('loaded for the camera. Everything listed here sits between the USB camera and the Windows camera APIs; a')
    $lines.Add('third-party filter (webcam effects, virtual cameras, security suites, some overlay tools) can stop or corrupt')
    $lines.Add('frames for every application at once. Only driver names, file paths and signers are listed.')
    $lines.Add('')

    function Get-DriverFileInfo {
        param([string]$ServiceName)
        $inbox = '(?i)^(usbvideo|usbccgp|ksthunk|WdmCompanionFilter|ks|swenum|usbhub3|USBXHCI|UCX01000|usbhub|usbport|usbehci|WUDFRd|Wdf01000|hidusb|usbaudio|stream|vhf|mshidkmdf)$'
        $svcKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\' + $ServiceName
        $img = $null
        try { $img = (Get-ItemProperty -LiteralPath $svcKey -ErrorAction Stop).ImagePath } catch {}
        $file = ''
        if ($img) {
            $file = ([string]$img).Trim().Trim('"')
            $file = $file -replace '^\\\?\?\\', ''
            $file = $file -replace '(?i)^\\SystemRoot\\', ($env:windir + '\')
            $file = $file -replace '(?i)^SystemRoot\\', ($env:windir + '\')
            $file = $file -replace '(?i)^system32\\', ($env:windir + '\System32\')
            $file = [Environment]::ExpandEnvironmentVariables($file)
            if ($file -notmatch '^[a-zA-Z]:\\') { $file = Join-Path $env:windir $file }
        }
        elseif ($ServiceName -match $inbox) { $file = Join-Path $env:windir ('System32\drivers\' + $ServiceName + '.sys') }
        if (-not $file) { return @{ File = ''; Signer = ''; State = 'no service entry' } }
        if (-not (Test-Path -LiteralPath $file)) { return @{ File = $file; Signer = ''; State = 'FILE MISSING' } }
        $signer = ''
        try {
            $sig = Get-AuthenticodeSignature -FilePath $file -ErrorAction Stop
            if ($sig.SignerCertificate) { $signer = ([string]$sig.SignerCertificate.Subject -replace '^CN=([^,]+).*$', '$1') }
            else { $signer = "unsigned ($($sig.Status))" }
        }
        catch { $signer = 'signature check failed' }
        $inWindows = ($file -match '(?i)^[a-z]:\\Windows\\System32\\drivers\\')
        $state = 'third-party'
        if ($signer -match '(?i)^Microsoft Windows( Publisher)?$|^Microsoft Corporation$' -and $inWindows) { $state = 'Windows' }
        elseif ($ServiceName -match $inbox -and $inWindows) { $state = 'Windows' }
        elseif ($signer -match '(?i)Hardware Compatibility Publisher') { $state = 'vendor (WHQL)' }
        return @{ File = $file; Signer = $signer; State = $state }
    }

    $classes = @(
        @{ Name = 'Camera class'; Guid = '{ca3e7ab9-b4c3-4ae6-8251-579ef933890f}' },
        @{ Name = 'Image class'; Guid = '{6bdd1fc6-810f-11d0-bec7-08002be2092f}' },
        @{ Name = 'USB class'; Guid = '{36fc9e60-c465-11cf-8056-444553540000}' },
        @{ Name = 'Media class'; Guid = '{4d36e96c-e325-11ce-bfc1-08002be10318}' }
    )
    foreach ($c in $classes) {
        $lines.Add("===== $($c.Name) $($c.Guid) =====")
        $p = Get-ItemProperty -LiteralPath ('HKLM:\SYSTEM\CurrentControlSet\Control\Class\' + $c.Guid) -ErrorAction SilentlyContinue
        foreach ($kind in @('UpperFilters', 'LowerFilters')) {
            $vals = @()
            if ($p -and $null -ne $p.$kind) { $vals = @($p.$kind | Where-Object { $_ }) }
            if ($vals.Count -eq 0) { $lines.Add("$kind : (none)"); continue }
            foreach ($f in $vals) {
                $info = Get-DriverFileInfo ([string]$f)
                $lines.Add(('{0,-12} : {1,-24} {2,-16} {3,-40} {4}' -f $kind, $f, $info.State, $info.Signer, $info.File))
                if ($info.State -ne 'Windows') { $script:classFilterFindings += "$f ($($c.Name) $kind, $($info.State), $($info.Signer))" }
            }
        }
        $lines.Add('')
    }
    foreach ($device in $script:delanCams) {
        $lines.Add("===== DelanCam1 device $($device.InstanceId) =====")
        $stack = @(Get-DevicePropertyData -InstanceId $device.InstanceId -KeyName 'DEVPKEY_Device_Stack')
        $stack = @($stack | Where-Object { $_ })
        $lines.Add('Driver stack (top to bottom): ' + ($stack -join ' > '))
        foreach ($kind in @('DEVPKEY_Device_UpperFilters', 'DEVPKEY_Device_LowerFilters')) {
            $vals = @(Get-DevicePropertyData -InstanceId $device.InstanceId -KeyName $kind)
            $vals = @($vals | Where-Object { $_ })
            $label = $kind -replace '^DEVPKEY_Device_', 'Device '
            if ($vals.Count -eq 0) { $lines.Add("$label : (none)"); continue }
            foreach ($f in $vals) {
                $info = Get-DriverFileInfo ([string]$f)
                $lines.Add(('{0,-20} : {1,-24} {2,-16} {3,-40} {4}' -f $label, $f, $info.State, $info.Signer, $info.File))
                if ($info.State -ne 'Windows') { $script:classFilterFindings += "$f (DelanCam1 $label, $($info.State), $($info.Signer))" }
            }
        }
        foreach ($drv in $stack) {
            $n = ([string]$drv) -replace '^\\Driver\\', ''
            $info = Get-DriverFileInfo $n
            $lines.Add(('{0,-20} : {1,-24} {2,-16} {3,-40} {4}' -f 'Stack driver', $n, $info.State, $info.Signer, $info.File))
            if ($info.State -ne 'Windows' -and $info.State -ne 'no service entry') { $script:classFilterFindings += "$n (DelanCam1 driver stack, $($info.State), $($info.Signer))" }
        }
        $lines.Add('')
    }
    $lines | Set-Content -LiteralPath $path -Encoding UTF8
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
    $summary.Add("Tool version: $script:toolVersion")
    if ($script:machineLine) {
        $summary.Add("Machine: $script:machineLine")
        $summary.Add('The machine line identifies the computer this report came from. A second-computer test must show a different machine here.')
    }
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
            if ($script:cameraHeldByOtherApp.Count -gt 0) {
                $summary.Add('REVIEW: DelanCam1 opened but delivered zero frames while another application had the camera open: ' + ($script:cameraHeldByOtherApp -join '; ') + '. Zero frames in that state do not prove a fault. Close that application and run the tool again before reading anything into this result.')
            }
            elseif ($script:formatProbePerformed -and $script:formatProbeVerdict -eq 'mjpeg-only-fails') {
                $summary.Add("REVIEW HIGH: DelanCam1 delivered zero MJPEG frames, yet every raw row of the format probe streamed normally ($script:formatProbeRowText). The camera and USB link work; MJPEG decoding inside Windows Media Foundation is broken on this PC. See FORMAT PROBE and WINDOWS VIDEO PIPELINE below.")
            }
            elseif ($script:formatProbePerformed -and $script:formatProbeVerdict -eq 'all-zero') {
                $summary.Add('REVIEW HIGH: DelanCam1 opened but delivered zero frames in the stream test and in every probed format. This points to USB, cable, driver or hardware, or to another application holding the camera, not to the application layer.')
            }
            elseif ($script:formatProbePerformed -and $script:formatProbeVerdict -eq 'erratic') {
                $summary.Add("REVIEW HIGH: DelanCam1 opened but delivered zero frames in the stream test, and the format probe rows are inconsistent ($script:formatProbeRowText). A camera that streams in one attempt and not in the next is starting erratically: USB isochronous link, cable or the camera itself. See FORMAT PROBE below.")
            }
            else {
                $summary.Add('REVIEW HIGH: DelanCam1 opened but delivered zero frames. This points to USB, driver or hardware, not the application layer. See format-probe.txt for whether the failure is format-specific.')
            }
        }
        elseif ($script:streamTestFramesReceived -lt 5) {
            if ($script:streamTestFramesReceived -le 2 -and $script:streamTestStoppedEarly) {
                $summary.Add("REVIEW HIGH: The stream delivered $script:streamTestFramesReceived frame(s) right after start (first after $script:streamTestFirstFrameDelayMs ms) and then nothing for the rest of the capture window, with no Windows error. This pattern lives below Windows Camera and OpenTrack: the USB isochronous link, the cable or the camera itself. Check CAMERA CONTROLS next (a manual long exposure looks the same), then USB TOPOLOGY. The same result from this tool on a second computer points at the camera and its cable; a clean result there points at this PC's USB path.")
            }
            else {
                $summary.Add("REVIEW HIGH: The stream delivered only $script:streamTestFramesReceived frame(s) in the capture window (first frame after $script:streamTestFirstFrameDelayMs ms). Too few to measure a working video feed. This usually points to USB, driver or hardware; extreme low light can also slow frame delivery this much on an IR camera, so check the sampled brightness below before ruling that out.")
            }
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
        if ($script:cameraControlsRead) {
            if ($script:exposureControlMs -ge 100 -and $script:exposureControlAuto -eq $false) {
                $summary.Add("REVIEW HIGH: CAMERA CONTROLS: exposure is manual with an exposure time of $script:exposureControlMs ms. That alone limits the camera to about $([math]::Round(1000 / $script:exposureControlMs, 1)) FPS and washes the picture out. Restore automatic exposure (Default in the camera properties dialog opened from OpenTrack) before suspecting USB or hardware. See camera-controls.txt.")
            }
            elseif ($script:exposureControlMs -ge 100) {
                $summary.Add("INFO: CAMERA CONTROLS: automatic exposure has stretched the exposure time to $script:exposureControlMs ms, which caps the frame rate at about $([math]::Round(1000 / $script:exposureControlMs, 1)) FPS. The scene looks dark to this IR camera; more IR light in view fixes that, not Windows. See camera-controls.txt.")
            }
            elseif ($script:exposureManual -and $script:exposureNearMax) {
                $summary.Add("REVIEW HIGH: CAMERA CONTROLS: exposure is in manual mode at or near its maximum ($script:exposureText). A long manual exposure caps the frame rate at a few FPS and washes the picture out, which looks exactly like a USB or hardware fault. Restore automatic exposure (Default in the camera properties dialog opened from OpenTrack) and re-test. See camera-controls.txt.")
            }
            elseif ($script:exposureManual) {
                $summary.Add("INFO: CAMERA CONTROLS: exposure is in manual mode ($script:exposureText). Fine for tracking when set deliberately; compare with the frame rate above. See camera-controls.txt.")
            }
            else {
                $summary.Add('CAMERA CONTROLS: exposure reported in automatic mode. See camera-controls.txt for the full list.')
            }
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
        $summary.Add("Per row: $script:formatProbeRowText.")
        switch ($script:formatProbeVerdict) {
            'mjpeg-only-fails' {
                $summary.Add('REVIEW HIGH: Every MJPEG row delivered nothing while every raw row streamed normally, and the stream test got no MJPEG frames either. The camera and USB link are fine; MJPEG decoding inside Windows Media Foundation is broken on this PC. Windows Camera (raw formats) keeps working, OpenTrack and AITrack (MJPEG) get no frames. Check WINDOWS VIDEO PIPELINE below for the decoder responsible.')
            }
            'intermittent-start' {
                $summary.Add("REVIEW HIGH: Intermittent start. The stream test received $script:streamTestFramesReceived MJPEG frames at $script:streamTestMeasuredFps FPS seconds before the probe, then every MJPEG row of the probe delivered nothing while raw rows streamed. A broken decoder fails every time, so this is not an MJPEG decoder fault: the camera starts only sometimes. That pattern lives in the USB isochronous link, the cable or the camera itself. The same tool on a second computer (different Machine line) tells whether it follows the camera.")
            }
            'erratic' {
                $summary.Add("REVIEW HIGH: Erratic start. The probe rows are inconsistent: some formats streamed, others delivered nothing or a single frame, with no Windows error. A decoder problem fails the same format every time; a camera that streams in one attempt and not in the next is failing to (re)start its USB isochronous stream. This points to the USB link, the cable or the camera itself, not to Windows decoders. The same tool on a second computer (different Machine line) tells whether it follows the camera.")
            }
            'all-zero' {
                if ($script:cameraHeldByOtherApp.Count -gt 0) {
                    $summary.Add('REVIEW: No probed format delivered frames, but another application had the camera open during this run (' + ($script:cameraHeldByOtherApp -join '; ') + '). Close it and run the tool again; this result proves nothing by itself.')
                }
                else {
                    $summary.Add('REVIEW HIGH: No probed format delivered frames. This points to USB, cable, driver or hardware, or to another application holding the camera.')
                }
            }
            'healthy' {
                $summary.Add('Every probed format delivered frames: the Media Foundation path to this camera is healthy. If OpenTrack still cannot open the camera, the fault is in the DirectShow layer it uses; see WINDOWS VIDEO PIPELINE below.')
            }
            'raw-only-fails' {
                $summary.Add('MJPEG delivered frames but the raw formats did not. Unusual; head tracking uses MJPEG, so this does not block OpenTrack by itself, but an erratic camera start cannot be ruled out. See format-probe.txt.')
            }
            default {
                $summary.Add('The probe produced no per-format rows. See format-probe.txt.')
            }
        }
        if ($script:reopenVerdict -ne 'not-run') {
            $summary.Add("Re-open cycles (MJPG 640x480@60, stop between each): $script:reopenText.")
            switch ($script:reopenVerdict) {
                'stable' { $summary.Add('The camera restarts its stream cleanly after every stop.') }
                'dies-after-stop' { $summary.Add("REVIEW HIGH: Dies after stop. The camera streamed after power-up ($script:streamTestFramesReceived frames in the stream test) and every re-open since delivers one frame or nothing. This is the camera (firmware or sensor), not this PC: a second computer shows the same once the camera has been stopped once. A power cut (unplug for 10 minutes) restores it until the next stop.") }
                'dead-state' { $summary.Add('REVIEW HIGH: Failed state. The camera delivered one frame or nothing in the stream test and in every re-open cycle, so it was already in its failed state before this tool started. See NEXT STEP below.') }
                default { $summary.Add('REVIEW: The re-open cycles are inconsistent: some restarts stream, some do not. USB link, cable or camera; see NEXT STEP below.') }
            }
        }
    }

    $nextSteps = @()
    if ($script:delanCams.Count -gt 0 -and $script:cameraHeldByOtherApp.Count -eq 0) {
        $inFailedState = ($script:reopenVerdict -eq 'dead-state') -or ($script:formatProbePerformed -and $script:streamTestOpened -and $script:streamTestFramesReceived -le 2 -and (@('erratic', 'all-zero', 'no-rows') -contains $script:formatProbeVerdict))
        if ($script:reopenVerdict -eq 'dies-after-stop') {
            $nextSteps += 'The camera loses its stream after the first stop and only a power cut brings it back. Further port or software tests on this PC will not change that. Send this report to Delanclip Support as it stands.'
        }
        elseif ($inFailedState) {
            $nextSteps += 'The camera is already in its failed state, so testing other USB ports or software settings now proves nothing: every port shows the same single frame.'
            $nextSteps += 'Unplug DelanCam1 for 10 minutes with the PC left on (no restart; a restart does not cut USB power), plug it back into the same port and run this tool again. If the first open then streams and the re-open cycles do not, the camera dies after a stop: camera fault. If it still delivers one frame, move it once to the port named under USB TOPOLOGY and run the tool a last time.'
        }
    }
    if ($nextSteps.Count -gt 0) {
        $summary.Add('')
        $summary.Add('NEXT STEP')
        foreach ($s in $nextSteps) { $summary.Add($s) }
    }

    $summary.Add('')
    $summary.Add('USB TOPOLOGY')
    if ($script:delanCams.Count -eq 0) { $summary.Add('Not analysed: DelanCam1 is not present.') }
    else {
        if ($script:usbControllerName) { $summary.Add("Host controller: $script:usbControllerName.") }
        if ($script:usbHubsInPath.Count -gt 0) {
            $summary.Add('INFO: DelanCam1 is connected behind a USB hub: ' + ($script:usbHubsInPath -join '; ') + '. Isochronous video tolerates extra hops badly. External hubs, monitor hubs and front-panel headers show up here, and so does the internal hub behind the chipset ports of some AMD boards (ASMedia ASM107x). Compare with a rear port that shows no hub, ideally one wired to the CPU. See usb-topology.txt.')
        }
        else { $summary.Add('DelanCam1 sits directly on a root hub port (no hub in between).') }
        if ($script:usbSiblingCount -ge 0) {
            $siblingLine = "Other USB devices on the same host controller: $script:usbSiblingCount"
            if ($script:usbSiblingCount -gt 0) { $siblingLine += ' (' + (($script:usbSiblingNames | Select-Object -First 6) -join '; ') + ')' }
            $summary.Add($siblingLine + '.')
            if ($script:usbSiblingCount -ge 8) { $summary.Add('INFO: Many devices share this controller. Unplugging everything except keyboard, mouse and DelanCam1 for one test is worth the minute it takes.') }
        }
        foreach ($l in $script:usbPortMapSummary) { $summary.Add($l) }
        if ($null -ne $script:usbSelectiveSuspendAc) {
            if ($script:usbSelectiveSuspendAc -eq 0) { $summary.Add('USB selective suspend (mains power): disabled.') }
            else { $summary.Add('INFO: USB selective suspend (mains power) is enabled. Windows may suspend an idle camera and some cameras do not resume cleanly; disabling it in the power plan is a harmless test.') }
        }
    }

    $summary.Add('')
    $summary.Add('WINDOWS VIDEO PIPELINE')
    $pipelineFindings = 0
    if ($script:mftVendorMjpeg.Count -gt 0) {
        $pipelineFindings++
        if ($null -eq $script:mftHardwareDecoders -or $script:mftHardwareDecoders -ne 0) {
            $mjpegDecodedHere = 0
            if ($script:streamTestOpened -and $script:streamTestSubtype -match '(?i)MJPG') { $mjpegDecodedHere += $script:streamTestFramesReceived }
            $mjpegDecodedHere += $script:formatProbeMjpgFrames
            if ($script:formatProbeVerdict -eq 'mjpeg-only-fails') {
                $summary.Add('REVIEW HIGH: A vendor MJPEG decoder is registered in Media Foundation and hardware decoders are enabled: ' + ($script:mftVendorMjpeg -join ', ') + '. The format probe shows exactly its signature: every MJPEG row empty, every raw row streaming. This is the decoder to disable (HardwareMFT EnableDecoders=0). See media-foundation.txt.')
            }
            elseif ($mjpegDecodedHere -ge 5) {
                $summary.Add('INFO: A vendor MJPEG decoder is registered in Media Foundation and hardware decoders are enabled: ' + ($script:mftVendorMjpeg -join ', ') + ". This is normal on every PC with that graphics driver. In this run $mjpegDecodedHere MJPEG frame(s) were decoded, so the decoder is not blocking MJPEG here.")
            }
            else {
                $summary.Add('REVIEW: A vendor MJPEG decoder is registered in Media Foundation and hardware decoders are enabled: ' + ($script:mftVendorMjpeg -join ', ') + '. Such decoders can swallow every MJPEG frame while raw formats keep working, but this run produced no MJPEG evidence either way. Compare with FORMAT PROBE. See media-foundation.txt.')
            }
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
        $cameraCodecs = @($script:vfwMissing64 | Where-Object { $_ -match '(?i)^vidc\.(yuy2|uyvy|yvyu|i420|iyuv)$' })
        if ($cameraCodecs.Count -gt 0) {
            $summary.Add('REVIEW HIGH: 64-bit VFW codec registrations missing from Drivers32 although Windows ships the DLL: ' + ($script:vfwMissing64 -join ', ') + '. 64-bit DirectShow apps such as OpenTrack need vidc.yuy2 (msyuv.dll) to convert camera frames to RGB; without it the capture graph fails to build even with MJPEG off.')
        }
        else {
            $summary.Add('REVIEW: 64-bit VFW codec registrations missing from Drivers32 although Windows ships the DLL: ' + ($script:vfwMissing64 -join ', ') + '. None of them is a camera pixel-format converter (yuy2, uyvy, yvyu, i420, iyuv), so this does not block OpenTrack by itself; it still shows a registry cleaner or uninstaller touched Drivers32.')
        }
    }
    if ($script:vfwNotShipped64.Count -gt 0) {
        $summary.Add('INFO: 64-bit VFW entries absent because this Windows build does not ship the codec DLL: ' + ($script:vfwNotShipped64 -join ', ') + '. Normal, not a fault.')
    }
    if ($script:vfwMissing32.Count -gt 0) {
        $pipelineFindings++
        $summary.Add('REVIEW: 32-bit VFW codec registrations missing from Drivers32: ' + ($script:vfwMissing32 -join ', ') + '.')
    }
    if ($script:classFilterFindings.Count -gt 0) {
        $pipelineFindings++
        $summary.Add('REVIEW HIGH: Non-Microsoft filter driver(s) attached to the camera classes or to DelanCam1: ' + (($script:classFilterFindings | Select-Object -Unique) -join '; ') + '. A third-party kernel filter in the camera path affects every application at once, Windows Camera included. See driver-stack.txt.')
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
    $recentUses = @($script:cameraUseRecords | Where-Object { $_.Start -lt $script:toolStartTime } | Sort-Object Start -Descending | Select-Object -First 3)
    if ($recentUses.Count -gt 0) {
        $last = $recentUses[0]
        $ageMin = [math]::Round(($script:toolStartTime - $last.Start).TotalMinutes, 1)
        if ($null -ne $last.Stop) {
            $durS = [math]::Round(($last.Stop - $last.Start).TotalSeconds, 0)
            $line = 'Most recent camera use before this run: {0} from {1} to {2} ({3} s), {4} min before the tool started.' -f $last.App, $last.Start.ToString('yyyy-MM-dd HH:mm:ss'), $last.Stop.ToString('HH:mm:ss'), $durS, $ageMin
            if ($ageMin -le 30 -and $durS -le 15 -and $last.App -match '(?i)opentrack|aitrack|facetrack|eyeware|trackir|camera') {
                $line += ' A session of a few seconds right before a report is typically a failed start; this report was taken in the state that produced it.'
            }
            $summary.Add($line)
        }
        else {
            $summary.Add(('Most recent camera use before this run: {0} opened the camera at {1} and had not released it when the tool started ({2} min earlier).' -f $last.App, $last.Start.ToString('yyyy-MM-dd HH:mm:ss'), $ageMin))
        }
    }
    if ($script:cameraHeldByOtherApp.Count -gt 0) {
        $summary.Add('REVIEW: Another application held the camera while this tool ran: ' + ($script:cameraHeldByOtherApp -join '; ') + '. The stream test and format probe then share the camera with it, and zero frames in that state prove nothing. Close it and run the tool again.')
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
        $summary.Add("INFO: Collected $script:cameraEventCountBefore camera-log event(s) from the 7 days before the tool started and $script:cameraEventCountDuring generated during this run. See camera-event-logs.txt.")
    }
    if ($script:usbEventCameraHits -gt 0) {
        $summary.Add("REVIEW: $script:usbEventCameraHits USB/PnP warning or error event(s) in the last 14 days name DelanCam1 (resets, failed requests, surprise removals). See usb-events.txt.")
    }
    elseif ($script:usbEventErrors -gt 0) {
        $summary.Add("INFO: $script:usbEventErrors USB/PnP warning or error event(s) in the last 14 days, none naming DelanCam1. See usb-events.txt.")
    }
    if ($script:uptimeDays -ge 7) {
        $summary.Add("INFO: $script:uptimeDays day(s) since the last full restart (Fast Startup = $script:fastStartup). Ask for Restart, not Shut down, before drawing conclusions from driver behaviour.")
    }
    if ($script:pendingReboot) {
        $summary.Add('INFO: Windows reports a pending reboot (servicing not finished). Restart before judging driver or codec state.')
    }

    $summary.Add('')
    $summary.Add('LIMITATION')
    $summary.Add('This version opens DelanCam1, measures whether its video stream delivers frames at a steady rate, checksums frames in memory to detect a frozen stream, reads the camera exposure and image controls, probes MJPG, NV12 and YUY2 separately, maps the USB path (hub, host controller, neighbouring devices), collects USB and PnP events, lists kernel filter drivers in the camera path, inspects the Windows video-pipeline registrations (Media Foundation decoders, DirectShow filters, VFW codecs) and the installed-program list, and identifies the machine the report came from.')
    $summary.Add('Content analysis cannot judge whether a varying image is visually correct, and registry findings are review flags for Delanclip Support, not proof of the cause.')
    $summary | Set-Content -LiteralPath (Join-Path $work 'SUMMARY.txt') -Encoding UTF8
}
}

# ------------------------------------------------------------------- main

try {
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        throw 'This tool must run in 64-bit PowerShell on 64-bit Windows; the 32-bit PowerShell sees a redirected registry.'
    }

    Write-ToolLog ('Delanclip DelanCam1 Fix Tool v' + $toolVersion)
    Write-ToolLog ('Started: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz') + '   Mode: ' + $mode + '   Administrator: ' + $isAdmin + '   User: ' + [Environment]::UserName)
    Write-ToolLog ('Windows build: ' + [Environment]::OSVersion.Version.ToString() + '   64-bit OS: ' + [Environment]::Is64BitOperatingSystem)
    Write-ToolLog ('Log: ' + $script:LogPath)
    Write-Host ('Delanclip DelanCam1 Fix Tool v' + $toolVersion) -ForegroundColor Cyan
    if (-not $isAdmin -and $mode -ne 'check') {
        Write-Screen 'Administrator permission was not given, so the tool can only check, not change anything.' 'Yellow'
        $mode = 'check'
    }

    # ---- undo of an earlier repair -----------------------------------------
    $latestBackup = Get-LatestBackup
    if ($mode -eq 'undo') {
        if (-not $latestBackup) { Write-Screen 'No earlier repair by this tool was found on the Desktop, so there is nothing to undo.' 'Yellow'; exit 2 }
        $code = Invoke-UndoFlow $latestBackup
        Open-OutputFolder
        if ($code -eq 0) { exit 0 } else { exit 2 }
    }
    if ($latestBackup -and $isAdmin -and $mode -eq 'check') {
        $whenText = Split-Path $latestBackup -Leaf
        if ($whenText -match '(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})\d{2}$') { $whenText = $Matches[1] + '-' + $Matches[2] + '-' + $Matches[3] + ' at ' + $Matches[4] + ':' + $Matches[5] }
        Write-Screen ''
        Write-Screen ('This tool already repaired this PC on ' + $whenText + '.')
        $choice = Read-Choice 'Press U to undo that repair, or any other key to check the PC again:'
        if ($choice -eq 'U') {
            $code = Invoke-UndoFlow $latestBackup
            Open-OutputFolder
            if ($code -eq 0) { exit 0 } else { exit 2 }
        }
    }

    # ---- diagnostics -------------------------------------------------------
    Write-Host ''
    Write-Host 'Step 1 of 2: collecting information about your PC and the camera (1 to 2 minutes)...'
    Write-Section 'DIAGNOSTICS'
    Invoke-DiagnosticsCollection $runDir
    $script:DiagCollected = $true
    Write-ToolLog ('  report files written to ' + $runDir)
    if ($script:machineLine) { Write-ToolLog ('  Machine: ' + $script:machineLine) }

    # ---- check -------------------------------------------------------------
    Write-Host ''
    Write-Host 'Step 2 of 2: checking the Windows video setup...'
    Invoke-Detection 'before'
    $screen = Get-ScreenFindings
    $fixes = @($script:Findings | Where-Object { $_.Severity -eq 'FIX' })
    $verdict = Get-ProbeVerdict $script:Probe

    Write-Screen ''
    if ($fixes.Count -eq 0) {
        if ($screen.Manual.Count -gt 0) {
            Write-Screen 'RESULT: nothing for this tool to repair, but something needs your attention:' 'Yellow'
            foreach ($m in $screen.Manual) { Write-Screen ('  - ' + $m.Human) }
            Complete-Run 'nothing to repair; manual attention needed'
            exit 2
        }
        Write-Screen 'RESULT: everything this tool checks is in order. Nothing to repair.' 'Green'
        if ($verdict -eq 'dead') {
            Write-Screen 'The camera gave no picture in any format. That points to USB, cable or driver, which this tool does not repair.'
        }
        elseif ($verdict -eq 'erratic') {
            Write-Screen 'The camera gave a picture only now and then, in every format, even on a second try. That points to the camera, its cable or the USB port, or to another program grabbing the camera, which this tool does not repair.'
        }
        elseif ($verdict -eq 'intermittent') {
            Write-Screen 'The camera streamed in one test and gave nothing in another. That points to the camera, its cable or the USB port, not to a Windows setting this tool repairs.'
        }
        if ($verdict -eq 'dead' -or $verdict -eq 'erratic' -or $verdict -eq 'intermittent') {
            Write-Screen 'Before testing other USB ports: unplug the camera for 10 minutes with the PC left on (a restart does not cut USB power), plug it back in and run this check again. A camera that then streams once and fails again after the first stop is a camera fault, not this PC.'
        }
        Write-Screen 'If OpenTrack still cannot open DelanCam1, send the report ZIP named below to Delanclip Support.'
        Complete-Run 'nothing to repair'
        exit 0
    }

    $n = $screen.Fixes.Count
    Write-Screen ('RESULT: ' + $n + ' problem' + $(if ($n -eq 1) { '' } else { 's' }) + ' found that can stop OpenTrack or AITrack from opening DelanCam1.') 'Yellow'
    $k = 0
    foreach ($f in $screen.Fixes) {
        $k++
        Write-Screen ('  ' + $k + '. ' + $f.Human)
        if ($f.Fix) { Write-Screen ('     Repair: ' + $f.Fix) }
    }
    if ($screen.Manual.Count -gt 0) {
        Write-Screen ''
        Write-Screen 'Also needs your attention (the tool cannot change this):'
        foreach ($m in $screen.Manual) { Write-Screen ('  - ' + $m.Human) }
    }
    Write-Screen ''
    Write-Screen 'Before any change, a backup with an UNDO script is saved in the DELANCLIP folder on your Desktop.'
    Write-Screen 'Running this tool again later also offers to undo the repair.'
    Write-Section 'CHANGES THE REPAIR WOULD MAKE (technical)'
    foreach ($f in $fixes) {
        Write-ToolLog ('  ' + $f.Id + ': ' + $f.Text)
        foreach ($p in $f.Plan) { Write-ToolLog ('      - ' + $p) }
    }

    if ($mode -ne 'apply') {
        if (-not $isAdmin) {
            Write-Screen ''
            Write-Screen 'To repair, run the tool again and answer Yes when Windows asks for permission.' 'Yellow'
            Complete-Run 'problems found; not repaired (no administrator permission)'
            exit 2
        }
        Write-Host ''
        $answer = Read-Choice 'Repair now? Press Y for yes or N for no:'
        if ($answer -ne 'Y') {
            Write-Screen ''
            Write-Screen 'Nothing was changed. Run the tool again whenever you want to repair.' 'Yellow'
            Complete-Run 'problems found; repair declined'
            exit 2
        }
        $mode = 'apply'
    }

    # ---- apply -------------------------------------------------------------
    Write-Section 'APPLYING REPAIRS'
    Write-ToolLog ('  Backup folder: ' + $backupDir)
    Write-Host ''
    Write-Host 'Repairing...'
    $k = 0
    foreach ($f in $fixes) {
        Write-ToolLog ('  ' + $f.Id + ': ' + $f.Text)
        $showLine = [bool]$f.Human
        if ($showLine) { $k++; Write-Host ('  ' + $k + '. ' + $f.Fix + ' ... ') -NoNewline }
        try {
            & $f.Action $f.Context
            if ($showLine) { Write-Host 'done' -ForegroundColor Green }
            Write-ToolLog ('>> ' + $f.Id + ': done')
        }
        catch {
            $script:ApplyErrors++
            if ($showLine) { Write-Host 'FAILED' -ForegroundColor Red }
            Write-ToolLog ('    FAILED: ' + $_.Exception.Message)
        }
    }
    Write-UndoScript

    Write-Host ''
    Write-Host 'Checking again ... ' -NoNewline
    Invoke-Detection 'after' -Quiet
    $after = Get-ScreenFindings
    $remaining = @($script:Findings | Where-Object { $_.Severity -eq 'FIX' })
    if ($remaining.Count -eq 0 -and $script:ApplyErrors -eq 0) {
        Write-Host 'all clear.' -ForegroundColor Green
        Write-ToolLog '>> Verification: all clear'
        if ((Get-ProbeVerdict $script:Probe) -eq 'healthy' -and $verdict -eq 'broken') { Write-Screen 'The camera now delivers an MJPEG picture.' 'Green' }
    }
    else {
        Write-Host 'some problems remain.' -ForegroundColor Yellow
        foreach ($f in $after.Fixes) { Write-Screen ('  - still present: ' + $f.Human) 'Yellow' }
        if ($script:ApplyErrors -gt 0) { Write-Screen ('  - ' + $script:ApplyErrors + ' repair step(s) failed. Please send the backup folder to Delanclip Support.') 'Yellow' }
    }
    if ($after.Manual.Count -gt 0) {
        Write-Screen ''
        Write-Screen 'Still needs your attention:'
        foreach ($m in $after.Manual) { Write-Screen ('  - ' + $m.Human) }
    }

    $needRestart = ($script:AppliedAreas.ContainsKey('B') -or $script:AppliedAreas.ContainsKey('C') -or $script:AppliedAreas.ContainsKey('D') -or $script:AppliedAreas.ContainsKey('E'))
    Write-NextSteps $needRestart
    Write-Screen ''
    Write-Screen ('Backup, UNDO.cmd and the full log are in: ' + $backupDir)
    Write-Screen 'To undo: run UNDO.cmd in that folder as administrator, or run this tool again and press U.'
    $outcome = 'repaired and verified'
    if ($remaining.Count -gt 0 -or $script:ApplyErrors -gt 0) { $outcome = 'repaired, but problems remain (' + $remaining.Count + ' finding(s), ' + $script:ApplyErrors + ' failed step(s))' }
    Complete-Run $outcome

    if ($needRestart -and $script:ApplyErrors -eq 0) {
        Write-Host ''
        $r = Read-Choice 'Restart Windows now? Press R to restart in 30 seconds (save your work first), or any other key to restart later:'
        if ($r -eq 'R') {
            $rc = Request-DelayedRestart 30
            if ($rc -eq 0) { Write-Screen 'Windows will restart in 30 seconds. You can close this window.' 'Green' }
            else { Write-Screen 'Windows did not accept the restart request. Please restart it yourself.' 'Yellow' }
        }
    }

    if ($remaining.Count -gt 0 -or $script:ApplyErrors -gt 0) { exit 2 }
    exit 0
}
catch {
    $msg = $_.Exception.Message
    Write-Host ''
    Write-Host ('Something went wrong: ' + $msg) -ForegroundColor Red
    try { Write-ToolLog ('ERROR: ' + $msg + ' at ' + $_.InvocationInfo.PositionMessage) } catch {}
    try { Complete-Run ('the tool failed: ' + $msg) } catch {}
    exit 1
}
