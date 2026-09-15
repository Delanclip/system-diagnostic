@echo off
setlocal
set "DELAN_VERSION=1.1.1"
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
echo This tool repairs the Windows settings that can stop OpenTrack or
echo AITrack from opening DelanCam1 while the Windows Camera app still works.
echo.
echo How it works:
echo  1. It checks your PC and tells you in plain words what it found.
echo  2. Nothing is changed until you answer Y to "Repair now?".
echo  3. Before any change, a backup with an UNDO script is saved in the
echo     DELANCLIP folder on your Desktop, so everything can be put back
echo     with one click. That folder opens by itself when the tool finishes.
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
    echo Permission was not given. The tool will only check your PC now.
    echo To repair, run it again and answer Yes to the Windows question.
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
#   DELAN_SKIPPROBE=1     do not open the camera for the MJPG/NV12/YUY2 probe
#
# The screen shows plain-language results only. Every technical detail goes
# to the log file (the check report on the Desktop, or LOG.txt in the backup
# folder once a repair starts).
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
# Everything the tool writes goes into one folder on the Desktop, so it can be
# found on a cluttered Desktop and sent to support as a whole.
$outRoot = Join-Path $desktop 'DELANCLIP'
if (-not (Test-Path -LiteralPath $outRoot)) { New-Item -ItemType Directory -Force -Path $outRoot | Out-Null }
$backupPrefix = 'DelanCam1-FixTool-backup-'
$backupDir = Join-Path $outRoot ($backupPrefix + $stamp)
$script:LogPath = Join-Path $outRoot ("DelanCam1-FixTool-check-" + $stamp + ".txt")
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

function Get-ProbeVerdict {
    # 'broken' (MJPEG dead, raw alive), 'healthy', 'dead' (nothing), 'none' (no probe)
    param($Probe)
    if (-not $Probe.Performed) { return 'none' }
    if ($Probe.MjpgRows -gt 0 -and $Probe.MjpgFrames -eq 0 -and $Probe.RawFrames -gt 0) { return 'broken' }
    if ($Probe.MjpgFrames -eq 0 -and $Probe.RawFrames -eq 0) { return 'dead' }
    return 'healthy'
}

function Get-ProbeSentence {
    param($Probe)
    if ($Probe.Skipped) {
        if ($Probe.Skipped -like 'skipped by*') { return 'skipped' }
        return 'DelanCam1 was not found, camera test skipped'
    }
    if (-not $Probe.Performed) { return 'could not run (' + $Probe.Error + ')' }
    switch (Get-ProbeVerdict $Probe) {
        'broken' { return 'MJPEG gives no picture, other formats work' }
        'dead' { return 'no picture in any format (USB, cable or driver, not something this tool repairs)' }
        default { return 'all formats deliver a picture' }
    }
}

function Write-ProbeLog {
    param($Probe, [string]$Title)
    Write-ToolLog ('  Camera probe (' + $Title + '): opens DelanCam1 per format for 2 seconds and counts frames')
    if ($Probe.Skipped) { Write-ToolLog ('    ' + $Probe.Skipped); return }
    if (-not $Probe.Performed) { Write-ToolLog ('    probe could not run: ' + $Probe.Error); return }
    foreach ($row in $Probe.Rows) {
        $extra = ''
        if ($row.Negotiated -and $row.Negotiated -ne $row.Requested) { $extra += '  negotiated ' + $row.Negotiated }
        if ($row.Start -and $row.Start -ne 'Success') { $extra += '  start=' + $row.Start }
        if ($row.Error) { $extra += '  ' + $row.Error }
        Write-ToolLog ('    {0,-16} {1,4} frames{2}' -f $row.Requested, $row.Frames, $extra)
    }
    if ($Probe.Error) { Write-ToolLog ('    probe error: ' + $Probe.Error) }
    Write-ToolLog ('    Reading: ' + (Get-ProbeSentence $Probe))
}

# ------------------------------------------------------------- detection

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
    elseif ($vendorMjpeg.Count -gt 0 -and -not $mjpgHealthy) { $reason = 'a vendor MJPEG decoder is registered and the probe could not confirm MJPEG works' }

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
        @{ Label = 'Camera test'; Run = { $script:Probe = Invoke-FormatProbe } },
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
    # The most recent backup folder (DELANCLIP folder first, then the Desktop
    # itself for folders written by older versions) that still has an unused
    # UNDO.cmd. A used one is renamed to UNDO-done.cmd and is never offered again.
    $dirs = @()
    foreach ($root in @($outRoot, $desktop)) {
        try { $dirs += @(Get-ChildItem -LiteralPath $root -Directory -Filter ($backupPrefix + '*') -ErrorAction Stop) } catch {}
    }
    foreach ($d in ($dirs | Sort-Object Name -Descending)) {
        $undo = Join-Path $d.FullName 'UNDO.cmd'
        if (Test-Path -LiteralPath $undo) { return $d.FullName }
    }
    return $null
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
        Write-Screen '  2. After the restart, run the DelanCam1 Diagnostics tool again and send the new report to Delanclip Support.'
        Write-Screen '  3. Start OpenTrack, pick DelanCam1 again in the camera list and press Start.'
    }
    else {
        Write-Screen '  1. Close and reopen OpenTrack or AITrack, pick DelanCam1 again in the camera list and press Start.'
        Write-Screen '  2. If it still does not work, restart Windows, run the DelanCam1 Diagnostics tool again and send the report to Delanclip Support.'
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
        $when = (Split-Path $latestBackup -Leaf).Substring($backupPrefix.Length)
        $whenText = $when
        if ($when -match '^(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})') { $whenText = $Matches[1] + '-' + $Matches[2] + '-' + $Matches[3] + ' at ' + $Matches[4] + ':' + $Matches[5] }
        Write-Screen ''
        Write-Screen ('This tool already repaired this PC on ' + $whenText + '.')
        $choice = Read-Choice 'Press U to undo that repair, or any other key to check the PC again:'
        if ($choice -eq 'U') {
            $code = Invoke-UndoFlow $latestBackup
            Open-OutputFolder
            if ($code -eq 0) { exit 0 } else { exit 2 }
        }
    }

    # ---- check -------------------------------------------------------------
    Write-Host ''
    Write-Host 'Checking your Windows video setup (about 15 seconds)...'
    Invoke-Detection 'before'
    $screen = Get-ScreenFindings
    $fixes = @($script:Findings | Where-Object { $_.Severity -eq 'FIX' })
    $verdict = Get-ProbeVerdict $script:Probe

    Write-Screen ''
    if ($fixes.Count -eq 0) {
        if ($screen.Manual.Count -gt 0) {
            Write-Screen 'RESULT: nothing for this tool to repair, but something needs your attention:' 'Yellow'
            foreach ($m in $screen.Manual) { Write-Screen ('  - ' + $m.Human) }
            Write-Screen ''
            Write-Screen ('The details of this check were saved to: ' + $script:LogPath)
            Open-OutputFolder
            exit 2
        }
        Write-Screen 'RESULT: everything this tool checks is in order. Nothing to repair.' 'Green'
        if ($verdict -eq 'dead') {
            Write-Screen 'The camera gave no picture in any format. That points to USB, cable or driver, which this tool does not repair.'
        }
        Write-Screen 'If OpenTrack still cannot open DelanCam1, run the DelanCam1 Diagnostics tool and send its report to Delanclip Support.'
        Write-Screen ('The details of this check were saved to: ' + $script:LogPath)
        Open-OutputFolder
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
            Write-Screen ('The details of this check were saved to: ' + $script:LogPath)
            Open-OutputFolder
            exit 2
        }
        Write-Host ''
        $answer = Read-Choice 'Repair now? Press Y for yes or N for no:'
        if ($answer -ne 'Y') {
            Write-Screen ''
            Write-Screen 'Nothing was changed. Run the tool again whenever you want to repair.' 'Yellow'
            Write-Screen ('The details of this check were saved to: ' + $script:LogPath)
            Open-OutputFolder
            exit 2
        }
        $mode = 'apply'
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
    Write-Screen 'If Delanclip Support asks for the results, send them the whole DELANCLIP folder from your Desktop.'
    Write-ToolLog ('Finished: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'))
    Open-OutputFolder

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
    exit 1
}
