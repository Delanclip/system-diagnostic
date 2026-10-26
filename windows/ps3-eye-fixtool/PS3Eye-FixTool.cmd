@echo off
setlocal
set "DELAN_VERSION=1.0.0"
title Delanclip PS3 Eye Fix Tool v%DELAN_VERSION%
set "DELAN_SCRIPT=%~f0"
set "DELAN_MODE=check"
set "DELAN_ELEVATED=0"

:parse_args
if "%~1"=="" goto args_done
if /i "%~1"=="/apply" set "DELAN_MODE=apply"
if /i "%~1"=="/check" set "DELAN_MODE=check"
if /i "%~1"=="/undo" set "DELAN_MODE=undo"
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
echo        Delanclip PS3 Eye Fix Tool v%DELAN_VERSION%
echo ============================================================
echo.
echo This tool checks which driver Windows has given your PS3 Eye camera and
echo clears the old driver that keeps coming back, so the camera is ready for
echo the libusbK step of the Delanclip PS3 Eye manual.
echo.
echo How it works:
echo  1. It collects the Windows device and driver information Delanclip
echo     Support needs (about a minute). No camera picture is taken.
echo  2. It tells you in plain words what it found. Nothing is changed
echo     until you answer Y to "Repair now?".
echo  3. Before any change, the old driver packages are backed up and an
echo     UNDO script is saved, so everything can be put back with one click.
echo  4. Everything, including a report ZIP for Delanclip Support, lands in
echo     the DELANCLIP folder on your Desktop, which opens by itself at
echo     the end.
echo.
echo Good to know: the PS3 Eye shows up twice in Device Manager, both times
echo as "USB Camera-B4.09.24.1". One entry is the picture, the other is the
echo camera's microphone. The microphone is fine as it is. This tool never
echo touches it, and you do not need to uninstall it.
echo.
echo It deletes no personal files, installs nothing and never connects to
echo the internet.
echo.
echo If Windows shows "Smart App Control blocked a file", close that message,
echo right-click PS3Eye-FixTool.cmd and choose "Run as administrator".
echo.
echo Before you continue: keep the PS3 Eye connected, if possible straight
echo into a USB port at the back of the PC, and close OpenTrack.
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
# Delanclip PS3 Eye Fix Tool - embedded Windows PowerShell 5.1 implementation
#
# Modes (set by the .cmd wrapper through environment variables):
#   DELAN_MODE=check      check, explain, then offer to repair (default)
#   DELAN_MODE=apply      repair without asking
#   DELAN_MODE=undo       undo the most recent repair found on the Desktop
#
# The PS3 Eye is a composite USB device, USB\VID_1415&PID_2000: interface
# MI_00 is the picture, interface MI_01 is the microphone, and Windows calls
# both "USB Camera-B4.09.24.1". Head tracking needs MI_00 on the libusbK
# driver. The repeating failure in support cases is an old driver package
# (CL-Eye, libusb-win32, a Zadig WinUSB package or a stale libusbK copy)
# left in the Windows driver store: uninstalling the device changes nothing,
# because Windows installs the stored package again as soon as the camera is
# plugged in. Customers then uninstall MI_01, the microphone, twenty times
# over, thinking it is the driver.
#
# This tool runs the PS3 Eye Diagnostics collector first (the report files
# support already knows), then reads the driver state of MI_00 and the
# driver store, says in plain words what it found, and after Y backs up and
# removes the stored packages that would come back, removes leftover MI_00
# entries, rescans and checks again. The goal state is the one the
# Delanclip manual asks for before its libusbK step: MI_00 without a driver,
# listed under Other devices with an exclamation mark. MI_01 is never
# touched. Nothing is installed and nothing is downloaded.
#
# Exit codes: 0 = clean (nothing to do, or repairs applied and verified),
#             2 = findings remain (not applied, or a manual step is needed),
#             1 = the tool itself failed.
# ---------------------------------------------------------------------------

$toolVersion = if ($env:DELAN_VERSION) { $env:DELAN_VERSION } else { 'unknown' }
$mode = 'check'
if ($env:DELAN_MODE -eq 'apply') { $mode = 'apply' }
if ($env:DELAN_MODE -eq 'undo') { $mode = 'undo' }

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
# its own folder with the diagnostic report files, LOG.txt, the exported
# driver packages and UNDO.cmd; a ZIP of that folder is the report for support.
$outRoot = Join-Path $desktop 'DELANCLIP'
if (-not (Test-Path -LiteralPath $outRoot)) { New-Item -ItemType Directory -Force -Path $outRoot | Out-Null }
$runPrefix = 'PS3Eye-FixTool-'
$runDir = Join-Path $outRoot ($runPrefix + $stamp)
if (-not (Test-Path -LiteralPath $runDir)) { New-Item -ItemType Directory -Force -Path $runDir | Out-Null }
$backupDir = $runDir
$driverBackupName = 'driver-backup'
$driverBackupDir = Join-Path $runDir $driverBackupName
$zipPath = Join-Path $outRoot ('SEND-TO-DELANCLIP-PS3Eye-Report-' + $stamp + '.zip')
$script:LogPath = Join-Path $runDir 'LOG.txt'
$script:LogLines = New-Object System.Collections.Generic.List[string]
$script:Findings = New-Object System.Collections.Generic.List[object]
$script:Undo = New-Object System.Collections.Generic.List[string]
$script:AppliedAreas = @{}
$script:ApplyErrors = 0
$script:Pass = ''
$script:DiagCollected = $false
$script:RunCompleted = $false
$script:State = $null
$script:StateBefore = $null
$script:StateAfter = $null
$script:Topology = $null

$cameraDisplayName = 'USB Camera-B4.09.24.1'
$manualUrl = 'https://delanclip.com/manuals/ps3-eye-camera-head-tracking/'
$rxDevice = '(?i)^USB\\VID_1415&PID_2000'
$rxImage = '(?i)^USB\\VID_1415&PID_2000&MI_00\\'
$rxAudio = '(?i)^USB\\VID_1415&PID_2000&MI_01\\'
$rxComposite = '(?i)^USB\\VID_1415&PID_2000\\'
$pnputilExe = Join-Path $env:SystemRoot 'System32\pnputil.exe'
$osBuild = 0
try { $osBuild = [Environment]::OSVersion.Version.Build } catch {}
# pnputil grew its commands over time: /add-driver, /delete-driver and
# /export-driver need Windows 10 version 1607 (build 14393); /remove-device
# and /scan-devices need version 2004 (build 19041).
$canManagePackages = ($osBuild -ge 14393)
$canScan = ($osBuild -ge 19041)

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
    # Severity: FIX (applied in apply mode), MANUAL (needs a person), WARN,
    # NOTE (always shown, nothing to do), INFO (log only).
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

# ------------------------------------------------------------------ pnputil

function Invoke-PnpUtil {
    # Runs pnputil with the given arguments and returns @{ ExitCode; Output }.
    # Output is captured through files rather than the pipeline, so a line
    # pnputil writes to stderr cannot turn into a terminating error here.
    # Arguments that contain spaces must arrive already quoted. Quiet logs
    # only the exit code and line count: the enumeration commands produce
    # hundreds of kilobytes that already go to their own report files.
    param([string[]]$Arguments, [switch]$Quiet)
    $outFile = Join-Path $env:TEMP ('delanclip-pnputil-' + [guid]::NewGuid().ToString('N') + '.txt')
    $errFile = $outFile + '.err'
    $code = -1
    $text = ''
    try {
        $p = Start-Process -FilePath $pnputilExe -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $outFile -RedirectStandardError $errFile -ErrorAction Stop
        $code = $p.ExitCode
        if (Test-Path -LiteralPath $outFile) { $text = [System.IO.File]::ReadAllText($outFile) }
        if (Test-Path -LiteralPath $errFile) {
            $e = [System.IO.File]::ReadAllText($errFile)
            if ($e.Trim()) { $text = $text + "`r`n" + $e }
        }
    }
    catch { $text = $_.Exception.Message }
    finally {
        foreach ($f in @($outFile, $errFile)) { try { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } } catch {} }
    }
    $lines = @($text -split "`r?`n" | Where-Object { $_.Trim() })
    if ($Quiet) {
        Write-ToolLog ('    pnputil ' + ($Arguments -join ' ') + ' -> exit code ' + $code + ', ' + $lines.Count + ' lines (in the report file)')
    }
    else {
        Write-ToolLog ('    pnputil ' + ($Arguments -join ' ') + ' -> exit code ' + $code)
        foreach ($line in $lines) { Write-ToolLog ('      | ' + $line.TrimEnd()) }
    }
    return @{ ExitCode = $code; Output = $text }
}

function Test-PnpUtilSuccess {
    # 0 = done, 3010 = done but a restart is pending, 259 = nothing matched
    # (no device to install on), which is fine for /add-driver and /scan-devices.
    param([int]$Code, [switch]$AllowNoMoreItems)
    if ($Code -eq 0 -or $Code -eq 3010) { return $true }
    if ($AllowNoMoreItems -and $Code -eq 259) { return $true }
    return $false
}

# ----------------------------------------------------------- device state

function Get-DevProp {
    param([string]$InstanceId, [string]$KeyName)
    try { return (Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName $KeyName -ErrorAction Stop).Data } catch { return $null }
}

function Get-KindLabel {
    # Plain-language name of a driver package kind, for the screen and SUMMARY.
    param([string]$Kind)
    switch ($Kind) {
        'cl-eye' { return 'the old CL-Eye driver (Code Laboratories)' }
        'libusbk' { return 'a libusbK driver package' }
        'libusb0' { return 'a libusb-win32 driver' }
        'winusb-zadig' { return 'a WinUSB driver installed with Zadig' }
        'winusb' { return 'a generic WinUSB driver' }
        'inbox-audio' { return 'the Windows audio driver' }
        'inbox-composite' { return 'the Windows composite-device driver' }
        'none' { return 'no driver' }
    }
    return 'another driver'
}

function Get-InfValue {
    # Reads "Key = value" from an INF and resolves a %token% through [Strings].
    param([string]$Text, [string]$Key)
    $value = ''
    if ($Text -match ('(?im)^\s*' + [regex]::Escape($Key) + '\s*=\s*([^\r\n;]+)')) { $value = $Matches[1].Trim() }
    if ($value -match '^%([^%]+)%$') {
        $token = $Matches[1]
        if ($Text -match ('(?im)^\s*' + [regex]::Escape($token) + '\s*=\s*"?([^"\r\n]+?)"?\s*$')) { $value = $Matches[1].Trim() }
    }
    return $value.Trim('"').Trim()
}

function Get-PackageKind {
    # Which driver a stored package carries. Decided from the INF contents
    # (service, binaries, publisher strings), never from the oem file name.
    param([string]$Text, [string]$Service)
    if ($Text -match '(?i)Code Laboratories|CL-?Eye|ps3eyecamera') { return 'cl-eye' }
    if ($Service -match '(?i)^libusbK$' -or $Text -match '(?i)libusbK\.sys') { return 'libusbk' }
    if ($Service -match '(?i)^libusb0$' -or $Text -match '(?i)libusb0\.sys|libusb-win32') { return 'libusb0' }
    if ($Text -match '(?i)libwdi|Zadig|akeo') { return 'winusb-zadig' }
    if ($Service -match '(?i)^WinUSB$' -or $Text -match '(?i)WinUSB\.sys') { return 'winusb' }
    return 'other'
}

function Get-Ps3EyePackages {
    # Every third-party package in the driver store whose INF names the PS3
    # Eye hardware ID. C:\Windows\INF\oemNN.inf is the published copy of each
    # stored package, which is the name pnputil uses to delete it.
    $infDir = Join-Path $env:SystemRoot 'INF'
    $files = @()
    try { $files = @(Get-ChildItem -LiteralPath $infDir -Filter 'oem*.inf' -File -ErrorAction Stop) } catch { Write-ToolLog ('  could not list ' + $infDir + ': ' + $_.Exception.Message) }
    $packages = @()
    foreach ($f in $files) {
        $text = ''
        try { $text = [System.IO.File]::ReadAllText($f.FullName) } catch { continue }
        if ($text -notmatch '(?i)VID_1415&PID_2000') { continue }
        $image = ($text -match '(?i)USB\\VID_1415&PID_2000&MI_00')
        $audio = ($text -match '(?i)USB\\VID_1415&PID_2000&MI_01')
        $whole = ($text -match '(?i)USB\\VID_1415&PID_2000(?!&MI_0)')
        $service = ''
        if ($text -match '(?im)^\s*AddService\s*=\s*([^,\s;]+)') { $service = $Matches[1].Trim() }
        $driverVer = ''
        if ($text -match '(?im)^\s*DriverVer\s*=\s*([^\r\n;]+)') { $driverVer = $Matches[1].Trim() }
        $catalog = ''
        if ($text -match '(?im)^\s*CatalogFile(\.NT\w*)?\s*=\s*([^\r\n;\s]+)') { $catalog = $Matches[2].Trim() }
        $provider = Get-InfValue $text 'Provider'
        $kind = Get-PackageKind $text $service
        $packages += [pscustomobject]@{
            PublishedName = $f.Name.ToLowerInvariant()
            Path = $f.FullName
            Provider = $provider
            DriverVer = $driverVer
            Service = $service
            Catalog = $catalog
            Kind = $kind
            Image = $image
            Audio = $audio
            Whole = $whole
            OriginalName = ''
            Signer = ''
        }
    }
    # pnputil /enum-drivers adds the original INF name and the signer. Its
    # labels are localised, so the fields are read by their position in each
    # block (published name, original name, provider, class, class GUID,
    # version, signer), which is the same in every language.
    if ($packages.Count -gt 0) {
        try {
            $r = Invoke-PnpUtil @('/enum-drivers') -Quiet
            $block = @()
            $blocks = @()
            foreach ($line in ($r.Output -split "`r?`n")) {
                if ($line.Trim()) { $block += $line.Trim() }
                elseif ($block.Count -gt 0) { $blocks += , $block; $block = @() }
            }
            if ($block.Count -gt 0) { $blocks += , $block }
            foreach ($b in $blocks) {
                $values = @()
                foreach ($line in $b) {
                    $i = $line.IndexOf(':')
                    if ($i -gt 0) { $values += $line.Substring($i + 1).Trim() } else { $values += $line }
                }
                if ($values.Count -lt 2 -or $values[0] -notmatch '(?i)^oem\d+\.inf$') { continue }
                $name = $values[0].ToLowerInvariant()
                foreach ($p in $packages) {
                    if ($p.PublishedName -ne $name) { continue }
                    $p.OriginalName = $values[1]
                    if ($values.Count -ge 7) { $p.Signer = $values[6] }
                }
            }
        }
        catch { Write-ToolLog ('  pnputil /enum-drivers could not be read: ' + $_.Exception.Message) }
    }
    return @($packages)
}

function Get-Ps3EyeNodes {
    # Every device node Windows knows for the PS3 Eye, present or not. A node
    # that is not present is a leftover from an earlier connection (another
    # port, an older driver) and still carries a driver binding.
    $all = @()
    try { $all = @(Get-PnpDevice -ErrorAction Stop | Where-Object { [string]$_.InstanceId -match $rxDevice }) }
    catch { Write-ToolLog ('  Get-PnpDevice failed: ' + $_.Exception.Message); return @() }
    $nodes = @()
    foreach ($d in $all) {
        $id = [string]$d.InstanceId
        $role = 'other'
        if ($id -match $rxImage) { $role = 'image' }
        elseif ($id -match $rxAudio) { $role = 'audio' }
        elseif ($id -match $rxComposite) { $role = 'composite' }
        $status = [string]$d.Status
        $present = $false
        try { if ($d.Present -eq $true) { $present = $true } } catch {}
        if (-not $present) {
            $isPresent = Get-DevProp $id 'DEVPKEY_Device_IsPresent'
            if ($isPresent -eq $true) { $present = $true }
        }
        if (-not $present -and ($status -eq 'OK' -or $status -eq 'Error' -or $status -eq 'Degraded')) { $present = $true }
        # A missing property must not read as "no problem": [int]$null is 0.
        $problem = -1
        try { if ($null -ne $d.ConfigManagerErrorCode) { $problem = [int]$d.ConfigManagerErrorCode } } catch {}
        if ($problem -lt 0) { try { if ($null -ne $d.Problem) { $problem = [int]$d.Problem } } catch {} }
        if ($problem -lt 0) {
            $pc = Get-DevProp $id 'DEVPKEY_Device_ProblemCode'
            if ($null -ne $pc) { try { $problem = [int]$pc } catch {} }
        }
        $service = [string]$d.Service
        if (-not $service) { $service = [string](Get-DevProp $id 'DEVPKEY_Device_Service') }
        $inf = ([string](Get-DevProp $id 'DEVPKEY_Device_DriverInfPath')).Trim().ToLowerInvariant()
        $provider = [string](Get-DevProp $id 'DEVPKEY_Device_DriverProvider')
        $version = [string](Get-DevProp $id 'DEVPKEY_Device_DriverVersion')
        $kind = 'none'
        if ($inf -or $service) {
            $kind = 'other'
            if ($service -match '(?i)^libusbK$') { $kind = 'libusbk' }
            elseif ($service -match '(?i)^libusb0$') { $kind = 'libusb0' }
            elseif ($service -match '(?i)^usbaudio$') { $kind = 'inbox-audio' }
            elseif ($service -match '(?i)^usbccgp$') { $kind = 'inbox-composite' }
            elseif ($service -match '(?i)^WinUSB$') { $kind = 'winusb' }
        }
        $nodes += [pscustomobject]@{
            InstanceId = $id; Role = $role; Present = $present; Status = $status; Problem = $problem
            Class = [string]$d.Class; FriendlyName = [string]$d.FriendlyName
            Service = $service; Inf = $inf; Provider = $provider; DriverVersion = $version; DriverKind = $kind
        }
    }
    return @($nodes)
}

function Get-ClEyeProgram {
    # The CL-Eye Platform software, if still installed. Its own uninstaller
    # must run first; this tool does not run somebody else's uninstaller.
    $hits = @()
    foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
        $keys = @()
        try { $keys = @(Get-ChildItem -Path $root -ErrorAction Stop) } catch { continue }
        foreach ($k in $keys) {
            $props = $null
            try { $props = Get-ItemProperty -Path $k.PSPath -ErrorAction Stop } catch { continue }
            $name = [string]$props.DisplayName
            $publisher = [string]$props.Publisher
            if ($name -match '(?i)CL-?Eye' -or $publisher -match '(?i)Code Laboratories') {
                $hits += [pscustomobject]@{ Name = $name; Publisher = $publisher; Version = [string]$props.DisplayVersion; Key = $k.PSChildName }
            }
        }
    }
    return @($hits)
}

function Get-UsbTopology {
    # Where the camera hangs on the USB tree: external hub or not, and the
    # host controller type. Information for support, never repaired.
    param([object[]]$Nodes)
    $start = @($Nodes | Where-Object { $_.Present -and $_.Role -eq 'image' } | Select-Object -First 1)
    if ($start.Count -eq 0) { $start = @($Nodes | Where-Object { $_.Present -and $_.Role -eq 'composite' } | Select-Object -First 1) }
    if ($start.Count -eq 0) { return $null }
    $chain = New-Object System.Collections.Generic.List[string]
    $externalHubs = 0
    $controller = ''
    $location = ''
    $current = $start[0].InstanceId
    $seen = @{}
    for ($depth = 0; $depth -lt 12; $depth++) {
        if ([string]::IsNullOrWhiteSpace($current) -or $seen.ContainsKey($current)) { break }
        $seen[$current] = $true
        $name = ''
        $svc = ''
        try { $dev = Get-PnpDevice -InstanceId $current -ErrorAction Stop; $name = [string]$dev.FriendlyName; $svc = [string]$dev.Service } catch {}
        if (-not $svc) { $svc = [string](Get-DevProp $current 'DEVPKEY_Device_Service') }
        if ($depth -eq 0) {
            $loc = Get-DevProp $current 'DEVPKEY_Device_LocationPaths'
            if ($loc) { $location = (@($loc) -join '; ') }
        }
        $chain.Add($current + ' [' + $svc + '] ' + $name)
        if ($current -match '(?i)^USB\\VID_' -and $svc -match '(?i)usbhub') { $externalHubs++ }
        if ($svc -match '(?i)^USBXHCI$') { $controller = 'USB 3.x host controller (xHCI)'; break }
        if ($svc -match '(?i)^USBEHCI$') { $controller = 'USB 2.0 host controller (EHCI)'; break }
        if ($svc -match '(?i)^(usbuhci|usbohci)$') { $controller = 'USB 1.1 host controller'; break }
        if ($current -match '(?i)^PCI\\') { $controller = 'host controller ' + $svc; break }
        $parent = Get-DevProp $current 'DEVPKEY_Device_Parent'
        if ([string]::IsNullOrWhiteSpace([string]$parent)) { break }
        $current = [string]$parent
    }
    return [pscustomobject]@{ ExternalHubs = $externalHubs; Controller = $controller; Location = $location; Chain = @($chain) }
}

function Get-Ps3EyeState {
    # One read of everything the verdict depends on.
    $nodes = Get-Ps3EyeNodes
    $packages = Get-Ps3EyePackages
    # @( ) on every function result: a single returned object is not an array,
    # and .Count on a PSCustomObject is empty in Windows PowerShell 5.1.
    $clEye = @(Get-ClEyeProgram)
    $image = @($nodes | Where-Object { $_.Role -eq 'image' -and $_.Present })
    $imageNode = $null
    if ($image.Count -gt 0) { $imageNode = $image[0] }
    $phantoms = @($nodes | Where-Object { $_.Role -eq 'image' -and -not $_.Present })
    $audio = @($nodes | Where-Object { $_.Role -eq 'audio' -and $_.Present })
    # Packages that bind to the picture interface or to the whole device. A
    # package that names only MI_01 is logged and left alone.
    $relevant = @($packages | Where-Object { $_.Image -or $_.Whole })
    $audioOnly = @($packages | Where-Object { $_.Audio -and -not $_.Image -and -not $_.Whole })
    # The one package allowed to stay: the libusbK package MI_00 is on right
    # now, when MI_00 works on it. Every other stored package that names the
    # camera is what Windows would put back, so it goes.
    $keep = $null
    if ($imageNode -and $imageNode.DriverKind -eq 'libusbk' -and $imageNode.Problem -eq 0 -and $imageNode.Inf) {
        $keep = @($relevant | Where-Object { $_.Kind -eq 'libusbk' -and $_.PublishedName -eq $imageNode.Inf } | Select-Object -First 1)
        if ($keep.Count -gt 0) { $keep = $keep[0] } else { $keep = $null }
    }
    # With the camera not connected there is no way to tell a working libusbK
    # package from a stale one, so libusbK packages are left alone until the
    # camera is back; foreign packages go either way.
    $remove = @($relevant | Where-Object { -not ($keep -and $_.PublishedName -eq $keep.PublishedName) -and -not ($null -eq $imageNode -and $_.Kind -eq 'libusbk') })
    $verdict = 'blocked'
    if ($clEye.Count -gt 0) { $verdict = 'cl-eye-installed' }
    elseif ($null -eq $imageNode) { $verdict = 'missing' }
    elseif ($imageNode.DriverKind -eq 'libusbk' -and $imageNode.Problem -eq 0 -and $remove.Count -eq 0 -and $phantoms.Count -eq 0) { $verdict = 'healthy' }
    # Code 28 (no driver installed) or 1 (not configured); code 0 with no driver
    # is the same interface a moment before Windows has settled it.
    elseif ($imageNode.DriverKind -eq 'none' -and ($imageNode.Problem -eq 28 -or $imageNode.Problem -eq 1 -or $imageNode.Problem -eq 0) -and $remove.Count -eq 0 -and $phantoms.Count -eq 0) { $verdict = 'ready' }
    return [pscustomobject]@{
        Nodes = @($nodes); Packages = @($packages); ClEye = @($clEye)
        ImageNode = $imageNode; Phantoms = @($phantoms); AudioNodes = @($audio)
        Relevant = @($relevant); AudioOnly = @($audioOnly); Keep = $keep; Remove = @($remove)
        Verdict = $verdict
    }
}

function Write-StateLog {
    param([object]$State, [string]$Label)
    Write-Section ('PS3 EYE STATE (' + $Label + ')')
    Write-ToolLog ('  verdict: ' + $State.Verdict)
    Write-ToolLog ('  device nodes: ' + $State.Nodes.Count)
    foreach ($n in $State.Nodes) {
        Write-ToolLog ('    ' + $n.Role.PadRight(9) + ' present=' + $n.Present + ' status=' + $n.Status + ' problem=' + $n.Problem + ' class=' + $n.Class + ' service=' + $n.Service + ' inf=' + $n.Inf + ' provider=' + $n.Provider + ' version=' + $n.DriverVersion + ' kind=' + $n.DriverKind)
        Write-ToolLog ('      ' + $n.InstanceId + ' (' + $n.FriendlyName + ')')
    }
    Write-ToolLog ('  stored packages naming the camera: ' + $State.Packages.Count)
    foreach ($p in $State.Packages) {
        $scope = @()
        if ($p.Whole) { $scope += 'whole device' }
        if ($p.Image) { $scope += 'MI_00' }
        if ($p.Audio) { $scope += 'MI_01' }
        Write-ToolLog ('    ' + $p.PublishedName + ' kind=' + $p.Kind + ' provider=' + $p.Provider + ' original=' + $p.OriginalName + ' service=' + $p.Service + ' version=' + $p.DriverVer + ' signer=' + $p.Signer + ' catalog=' + $p.Catalog + ' binds=' + ($scope -join '+'))
    }
    if ($State.Keep) { Write-ToolLog ('  kept: ' + $State.Keep.PublishedName + ' (MI_00 works on it)') }
    Write-ToolLog ('  would remove: ' + (@($State.Remove | ForEach-Object { $_.PublishedName }) -join ', '))
    Write-ToolLog ('  leftover MI_00 entries: ' + (@($State.Phantoms | ForEach-Object { $_.InstanceId }) -join ', '))
    foreach ($c in $State.ClEye) { Write-ToolLog ('  CL-Eye program installed: ' + $c.Name + ' ' + $c.Version + ' (' + $c.Publisher + ', key ' + $c.Key + ')') }
}

# ------------------------------------------------------------- detection

function Invoke-Detection {
    # Reads the state and turns it into findings with their repair actions.
    param([string]$Pass, [switch]$Quiet)
    $script:Pass = $Pass
    $script:Findings.Clear()
    if (-not $Quiet) { Write-Host '  [1/3] Camera entries in Windows ... ' -NoNewline }
    $state = Get-Ps3EyeState
    $script:State = $state
    if ($Pass -eq 'before') { $script:StateBefore = $state } else { $script:StateAfter = $state }
    Write-StateLog $state $Pass
    if (-not $Quiet) {
        $n = @($state.Nodes | Where-Object { $_.Present }).Count
        if ($null -eq $state.ImageNode) { Write-Host 'camera not found' -ForegroundColor Yellow } else { Write-Host ('found (' + $n + ' present)') -ForegroundColor Green }
        Write-Host '  [2/3] Stored driver packages ... ' -NoNewline
        if ($state.Remove.Count -gt 0) { Write-Host ($state.Remove.Count.ToString() + ' to remove') -ForegroundColor Yellow } else { Write-Host 'OK' -ForegroundColor Green }
        Write-Host '  [3/3] CL-Eye software, USB connection ... ' -NoNewline
    }
    if ($Pass -eq 'before') {
        try { $script:Topology = Get-UsbTopology $state.Nodes } catch { Write-ToolLog ('  topology read failed: ' + $_.Exception.Message) }
        if ($script:Topology) {
            Write-Section 'USB CONNECTION'
            Write-ToolLog ('  external hubs between camera and PC: ' + $script:Topology.ExternalHubs)
            Write-ToolLog ('  controller: ' + $script:Topology.Controller)
            Write-ToolLog ('  location: ' + $script:Topology.Location)
            foreach ($c in $script:Topology.Chain) { Write-ToolLog ('    ' + $c) }
        }
    }
    if (-not $Quiet) {
        if ($state.ClEye.Count -gt 0) { Write-Host 'CL-Eye still installed' -ForegroundColor Yellow } else { Write-Host 'OK' -ForegroundColor Green }
    }

    # CL-Eye program: a person has to uninstall it; the tool only says so.
    foreach ($c in $state.ClEye) {
        Add-Finding 'CLEYE' 'MANUAL' ('CL-Eye software is installed: ' + $c.Name + ' ' + $c.Version + ' (' + $c.Publisher + ')') -Human ('The CL-Eye program ("' + $c.Name + '") is still installed. Its driver takes the camera over every time it is connected. Uninstall it from Windows Settings, Apps, restart Windows, then run this tool again.')
    }

    # Stored packages that Windows would put back on the camera.
    foreach ($p in $state.Remove) {
        $label = Get-KindLabel $p.Kind
        $boundNow = ($null -ne $state.ImageNode -and $state.ImageNode.Inf -eq $p.PublishedName)
        $human = 'Windows has ' + $label + ' stored for the PS3 Eye (' + $p.PublishedName
        if ($p.OriginalName) { $human += ', ' + $p.OriginalName }
        if ($p.Provider) { $human += ', ' + $p.Provider }
        $human += ').'
        if ($boundNow) { $human += ' The camera''s picture interface is using it right now.' }
        elseif ($p.Kind -eq 'libusbk') { $human += ' It is a stale copy the camera is not using.' }
        else { $human += ' Windows installs it again every time the camera is plugged in.' }
        $fix = 'Back the package up to the run folder, then remove it from the Windows driver store'
        if ($boundNow) { $fix += ' and from the camera' }
        $fix += '.'
        $plan = @(
            ('pnputil /export-driver ' + $p.PublishedName + ' "' + (Join-Path $driverBackupDir ($p.PublishedName -replace '\.inf$', '')) + '"'),
            ('pnputil /delete-driver ' + $p.PublishedName + ' /uninstall /force')
        )
        if (-not $canManagePackages) {
            Add-Finding ('PKG-' + $p.PublishedName) 'MANUAL' ('stored package ' + $p.PublishedName + ' (' + $p.Kind + ') cannot be removed: pnputil on this Windows build has no /delete-driver') -Human ($human + ' This Windows version is too old for the tool to remove it; please send the report to Delanclip Support.')
            continue
        }
        Add-Finding ('PKG-' + $p.PublishedName) 'FIX' ('stored package ' + $p.PublishedName + ' (' + $p.Kind + ', ' + $p.Provider + ', ' + $p.DriverVer + ')' + $(if ($boundNow) { ', bound to MI_00 now' } else { '' })) -Plan $plan -Context @{ Package = $p } -Human $human -Fix $fix -Action {
            param($ctx)
            $pkg = $ctx.Package
            $folder = Join-Path $driverBackupDir ($pkg.PublishedName -replace '\.inf$', '')
            if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Force -Path $folder | Out-Null }
            $r = Invoke-PnpUtil @('/export-driver', $pkg.PublishedName, ('"' + $folder + '"'))
            $exported = @(Get-ChildItem -LiteralPath $folder -Filter '*.inf' -File -ErrorAction SilentlyContinue)
            if (-not (Test-PnpUtilSuccess $r.ExitCode) -or $exported.Count -eq 0) { throw ('backup of ' + $pkg.PublishedName + ' failed (pnputil exit code ' + $r.ExitCode + '); the package was left in place') }
            Write-ToolLog ('    backup: ' + $pkg.PublishedName + ' -> ' + $folder)
            $r = Invoke-PnpUtil @('/delete-driver', $pkg.PublishedName, '/uninstall', '/force')
            if (-not (Test-PnpUtilSuccess $r.ExitCode)) { throw ('removing ' + $pkg.PublishedName + ' failed (pnputil exit code ' + $r.ExitCode + ')') }
            Add-Undo ('pnputil /add-driver "%~dp0' + $driverBackupName + '\' + ($pkg.PublishedName -replace '\.inf$', '') + '\*.inf" /install')
            $script:AppliedAreas['packages'] = $true
            Write-ToolLog ('    removed from the driver store: ' + $pkg.PublishedName)
        }
    }

    # The picture interface is on a foreign driver whose package is not in the
    # store (nothing to delete) - say so rather than guess.
    if ($state.ImageNode -and $state.ImageNode.DriverKind -notin @('none', 'libusbk') -and $state.Remove.Count -eq 0) {
        Add-Finding 'BOUND' 'MANUAL' ('MI_00 is bound to ' + $state.ImageNode.DriverKind + ' via ' + $state.ImageNode.Inf + ' but no stored package names the camera') -Human ('The camera''s picture interface is using ' + (Get-KindLabel $state.ImageNode.DriverKind) + ' that this tool cannot trace to a stored package. Please send the report to Delanclip Support.')
    }
    if ($state.ImageNode -and $state.ImageNode.DriverKind -eq 'libusbk' -and $state.ImageNode.Problem -ne 0 -and $state.Remove.Count -eq 0) {
        Add-Finding 'LIBK-ERR' 'MANUAL' ('MI_00 is on libusbK but reports problem code ' + $state.ImageNode.Problem) -Human ('The camera''s picture interface is on the libusbK driver, but Windows reports error code ' + $state.ImageNode.Problem + ' for it, and the package behind it could not be found in the driver store. Please send the report to Delanclip Support.')
    }

    # Leftover MI_00 entries from earlier connections.
    foreach ($ph in $state.Phantoms) {
        $human = 'Windows keeps an old entry for the camera''s picture interface from an earlier connection (' + $ph.InstanceId + ', ' + (Get-KindLabel $ph.DriverKind) + ').'
        if (-not $canScan) {
            Add-Finding ('NODE-' + $ph.InstanceId) 'MANUAL' ('leftover MI_00 node ' + $ph.InstanceId + ' cannot be removed: pnputil on this Windows build has no /remove-device') -Human ($human + ' This Windows version is too old for the tool to remove it; it does no harm on its own.')
            continue
        }
        Add-Finding ('NODE-' + $ph.InstanceId) 'FIX' ('leftover MI_00 node ' + $ph.InstanceId + ' (not present, ' + $ph.DriverKind + ', ' + $ph.Inf + ')') -Plan @('pnputil /remove-device "' + $ph.InstanceId + '"') -Context @{ Node = $ph } -Human $human -Fix 'Remove the leftover entry. Windows recreates it cleanly the next time the camera is connected there.' -Action {
            param($ctx)
            $node = $ctx.Node
            $r = Invoke-PnpUtil @('/remove-device', ('"' + $node.InstanceId + '"'))
            if (-not (Test-PnpUtilSuccess $r.ExitCode)) { throw ('removing the leftover entry ' + $node.InstanceId + ' failed (pnputil exit code ' + $r.ExitCode + ')') }
            Add-Undo ('rem leftover device entry ' + $node.InstanceId + ' was removed; Windows recreates it on the next connection, there is nothing to put back')
            $script:AppliedAreas['nodes'] = $true
            Write-ToolLog ('    removed leftover node: ' + $node.InstanceId)
        }
    }

    # The microphone: always named, never touched.
    if ($state.AudioNodes.Count -gt 0) {
        $a = $state.AudioNodes[0]
        # The microphone often shows error code 10 (its driver does not start): it
        # is irrelevant for head tracking and must not be read as the camera fault.
        $micHuman = 'The second "' + $cameraDisplayName + '" entry in Device Manager is the camera''s microphone. It does not need to be uninstalled; this tool leaves it alone.'
        if ($a.Problem -ne 0) { $micHuman += ' Windows may show an error on it; that has no effect on head tracking.' } else { $micHuman += ' It is correct as it is.' }
        Add-Finding 'MIC' 'NOTE' ('MI_01 (microphone) present: status ' + $a.Status + ', problem ' + $a.Problem + ', service ' + $a.Service + ', ' + $a.Inf) -Human $micHuman
    }
    foreach ($p in $state.AudioOnly) {
        Add-Finding ('AUDIO-' + $p.PublishedName) 'INFO' ('stored package ' + $p.PublishedName + ' names only MI_01 (' + $p.Kind + ', ' + $p.Provider + '); left alone')
    }

    # USB path, for the person and for support.
    if ($Pass -eq 'before' -and $script:Topology) {
        if ($script:Topology.ExternalHubs -gt 0) {
            Add-Finding 'USB' 'WARN' ('camera connected through ' + $script:Topology.ExternalHubs + ' external hub(s); ' + $script:Topology.Controller) -Human 'The camera is connected through a USB hub. For the driver steps, plug it straight into a USB port at the back of the PC.'
        }
        else {
            Add-Finding 'USB' 'INFO' ('camera connected directly; ' + $script:Topology.Controller)
        }
    }
}

function Get-ScreenFindings {
    $fixes = @($script:Findings | Where-Object { $_.Severity -eq 'FIX' -and $_.Human })
    $manual = @($script:Findings | Where-Object { ($_.Severity -eq 'MANUAL' -or $_.Severity -eq 'WARN') -and $_.Human })
    $notes = @($script:Findings | Where-Object { $_.Severity -eq 'NOTE' -and $_.Human })
    return @{ Fixes = $fixes; Manual = $manual; Notes = $notes }
}

function Wait-ForRescan {
    # After packages are removed, /scan-devices makes Windows enumerate the
    # camera again. The picture interface disappears and comes back within a
    # few seconds; wait for it before judging the result.
    if ($canScan) {
        $r = Invoke-PnpUtil @('/scan-devices')
        if (-not (Test-PnpUtilSuccess $r.ExitCode -AllowNoMoreItems)) { Write-ToolLog ('    scan-devices returned ' + $r.ExitCode) }
    }
    # Right after /delete-driver /uninstall the interface is still listed with
    # no driver and no problem code; within seconds Windows settles it to code
    # 28, or installs another stored package. Only the settled state is judged.
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Seconds 1
        $nodes = @()
        try { $nodes = Get-Ps3EyeNodes } catch {}
        $img = @($nodes | Where-Object { $_.Role -eq 'image' -and $_.Present })
        if ($img.Count -gt 0 -and ($img[0].DriverKind -ne 'none' -or $img[0].Problem -ne 0)) { break }
    }
}

# ------------------------------------------------------------------ undo

function Write-UndoScript {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('@echo off')
    $lines.Add('setlocal')
    $lines.Add('title Delanclip PS3 Eye Fix Tool - UNDO')
    $lines.Add('set "QUIET=0"')
    $lines.Add('if /i "%~1"=="/quiet" set "QUIET=1"')
    $lines.Add('echo This puts the PS3 Eye driver packages back exactly as they were before')
    $lines.Add('echo the PS3 Eye Fix Tool removed them on ' + (Get-Date -Format 'yyyy-MM-dd HH:mm') + '.')
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
        $lines.Add($cmd + ' >nul 2>&1 || set "FAILED=1"')
    }
    if ($canScan) { $lines.Add('pnputil /scan-devices >nul 2>&1') }
    $lines.Add('echo.')
    $lines.Add('if "%FAILED%"=="1" (')
    $lines.Add('    echo Some packages could not be put back. Please send this folder to Delanclip Support.')
    $lines.Add(') else (')
    $lines.Add('    echo Done. The previous driver packages are back. Unplug the camera and plug it in again.')
    $lines.Add(')')
    $lines.Add('if "%QUIET%"=="0" pause')
    $lines.Add('exit /b %FAILED%')
    $path = Join-Path $backupDir 'UNDO.cmd'
    [System.IO.File]::WriteAllText($path, (($lines -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
    Write-ToolLog ('  UNDO.cmd written: ' + $path)
}

function Get-LatestBackup {
    # The most recent run folder in DELANCLIP that still has an unused
    # UNDO.cmd. A used one is renamed to UNDO-done.cmd and never offered again.
    $dirs = @()
    try { $dirs = @(Get-ChildItem -LiteralPath $outRoot -Directory -Filter ($runPrefix + '*') -ErrorAction Stop) } catch {}
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

function Invoke-UndoScript {
    # Runs a previously written UNDO.cmd without its pauses. Returns its exit code.
    param([string]$UndoPath)
    $p = Start-Process -FilePath 'cmd.exe' -ArgumentList ('/c ""' + $UndoPath + '" /quiet"') -WorkingDirectory (Split-Path -Parent $UndoPath) -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
    return $p.ExitCode
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
        Write-Screen 'Done. The previous driver packages are back.' 'Green'
        Write-Screen 'Unplug the PS3 Eye and plug it in again so Windows installs them.'
    }
    else {
        Write-Screen 'Some packages could not be put back. Please send that folder to Delanclip Support.' 'Red'
    }
    return $code
}

# --------------------------------------------------------------- reporting

function Get-VerdictSentence {
    param([string]$Verdict)
    switch ($Verdict) {
        'healthy' { return 'the picture interface is on the libusbK driver and Windows reports it as working' }
        'ready' { return 'the picture interface has no driver, exactly the state the manual needs before its libusbK step' }
        'blocked' { return 'an old driver or stored driver package is in the way' }
        'missing' { return 'Windows does not see the camera''s picture interface' }
        'cl-eye-installed' { return 'the CL-Eye software is still installed' }
    }
    return $Verdict
}

function Write-StateTable {
    param([System.Collections.Generic.List[string]]$Lines, [object]$State, [string]$Label)
    $Lines.Add('')
    $Lines.Add('DEVICE ENTRIES (' + $Label + ')')
    if ($State.Nodes.Count -eq 0) { $Lines.Add('  none: Windows has never seen a PS3 Eye on this PC, or the camera is not connected') }
    foreach ($n in $State.Nodes) {
        $what = 'other'
        if ($n.Role -eq 'image') { $what = 'MI_00 picture   ' }
        elseif ($n.Role -eq 'audio') { $what = 'MI_01 microphone' }
        elseif ($n.Role -eq 'composite') { $what = 'composite parent' }
        $presence = 'present'
        if (-not $n.Present) { $presence = 'LEFTOVER (not present)' }
        $Lines.Add('  ' + $what + '  ' + $presence + '  status=' + $n.Status + '  problem=' + $n.Problem + '  driver=' + $n.DriverKind + ' (' + $n.Service + ', ' + $n.Inf + ', ' + $n.Provider + ' ' + $n.DriverVersion + ')')
        $Lines.Add('      ' + $n.InstanceId)
    }
    $Lines.Add('STORED DRIVER PACKAGES NAMING THE CAMERA (' + $Label + ')')
    if ($State.Packages.Count -eq 0) { $Lines.Add('  none') }
    foreach ($p in $State.Packages) {
        $scope = @()
        if ($p.Whole) { $scope += 'whole device' }
        if ($p.Image) { $scope += 'MI_00' }
        if ($p.Audio) { $scope += 'MI_01' }
        $flag = 'remove'
        if ($State.Keep -and $p.PublishedName -eq $State.Keep.PublishedName) { $flag = 'KEEP (MI_00 works on it)' }
        elseif ($p.Audio -and -not $p.Image -and -not $p.Whole) { $flag = 'leave (microphone only)' }
        $Lines.Add('  ' + $p.PublishedName + '  ' + $p.Kind + '  ' + $p.Provider + '  ' + $p.DriverVer + '  original=' + $p.OriginalName + '  service=' + $p.Service + '  signer=' + $p.Signer + '  binds=' + ($scope -join '+') + '  -> ' + $flag)
    }
}

function Write-FixToolSummary {
    # SUMMARY.txt: the one file support reads first.
    param([string]$Outcome)
    $path = Join-Path $runDir 'SUMMARY.txt'
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('Delanclip PS3 Eye Fix Tool - summary')
    $lines.Add('Fix Tool version: ' + $toolVersion + '   Administrator: ' + $isAdmin + '   Mode: ' + $mode + '   Windows build: ' + $osBuild)
    $lines.Add('Generated: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'))
    $lines.Add('Outcome: ' + $Outcome)
    if ($script:StateBefore) { $lines.Add('Verdict before: ' + $script:StateBefore.Verdict + ' (' + (Get-VerdictSentence $script:StateBefore.Verdict) + ')') }
    if ($script:StateAfter) { $lines.Add('Verdict after:  ' + $script:StateAfter.Verdict + ' (' + (Get-VerdictSentence $script:StateAfter.Verdict) + ')') }
    $lines.Add('')
    $lines.Add('VERDICTS: healthy = MI_00 on libusbK, OK, nothing else stored; ready = MI_00 without a driver (code 28), nothing else stored; blocked = foreign driver on MI_00, foreign or stale packages in the store, or leftover MI_00 entries; missing = no present MI_00; cl-eye-installed = the CL-Eye program must be uninstalled first.')
    if ($script:Topology) {
        $lines.Add('')
        $lines.Add('USB CONNECTION')
        $lines.Add('  external hubs between camera and PC: ' + $script:Topology.ExternalHubs + '   controller: ' + $script:Topology.Controller)
        if ($script:Topology.Location) { $lines.Add('  location: ' + $script:Topology.Location) }
    }
    if ($script:StateBefore) {
        foreach ($c in $script:StateBefore.ClEye) { $lines.Add(''); $lines.Add('CL-EYE SOFTWARE INSTALLED: ' + $c.Name + ' ' + $c.Version + ' (' + $c.Publisher + ')') }
        Write-StateTable $lines $script:StateBefore 'before'
    }
    if ($script:StateAfter) { Write-StateTable $lines $script:StateAfter 'after' }
    $lines.Add('')
    $lines.Add('FIX TOOL FINDINGS (last pass: ' + $script:Pass + ')')
    $shown = 0
    foreach ($f in $script:Findings) {
        if ($f.Severity -eq 'INFO') { continue }
        $lines.Add('  [' + $f.Severity + '] ' + $f.Id + ': ' + $f.Text)
        $shown++
    }
    if ($shown -eq 0) { $lines.Add('  No findings in the last detection pass.') }
    if ($script:AppliedAreas.Count -gt 0) { $lines.Add('Repaired: ' + ((@($script:AppliedAreas.Keys) | Sort-Object) -join ', ') + '. The exported packages and UNDO.cmd are in this folder.') }
    $lines.Add('')
    $lines.Add('Full detail: LOG.txt in this folder. Device and driver evidence: the diagnostic report files next to this file.')
    try { [System.IO.File]::WriteAllText($path, (($lines -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($false))) } catch {}
}

function Complete-Run {
    # Writes SUMMARY.txt, zips the run folder into the report for support and
    # opens the DELANCLIP folder. Runs once per run.
    param([string]$Outcome)
    if ($script:RunCompleted) { return }
    $script:RunCompleted = $true
    Write-FixToolSummary $Outcome
    Write-ToolLog ('Outcome: ' + $Outcome)
    Write-ToolLog ('Finished: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'))
    $zipOk = $false
    try {
        if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
        Compress-Archive -Path (Join-Path $runDir '*') -DestinationPath $zipPath -CompressionLevel Optimal -Force
        $zipOk = (Test-Path -LiteralPath $zipPath)
    }
    catch { Write-ToolLog ('  ZIP failed: ' + $_.Exception.Message) }
    Write-Screen ''
    if ($zipOk) { Write-Screen ('Report for Delanclip Support (send it only if the camera still does not work): ' + (Split-Path $zipPath -Leaf) + ' in the DELANCLIP folder on your Desktop.') }
    else { Write-Screen ('The report could not be zipped. If Delanclip Support asks for it, send them this folder: ' + $runDir) 'Yellow' }
    Open-OutputFolder
}

function Open-OutputFolder {
    try { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $outRoot + '"') -ErrorAction Stop | Out-Null } catch {}
}

function Write-NextSteps {
    param([string]$Verdict)
    Write-Screen ''
    Write-Screen 'WHAT TO DO NEXT' 'Cyan'
    switch ($Verdict) {
        'ready' {
            Write-Screen ('  The camera is now in the state the Delanclip manual needs: "' + $cameraDisplayName + '" with an exclamation mark under Other devices in Device Manager.')
            Write-Screen ('  1. Continue with Step 2 of the PS3 Eye manual, the libusbK installer: ' + $manualUrl)
            Write-Screen '  2. In the libusbK wizard (Step 3) the camera should now appear in the device list.'
            Write-Screen ('  3. Do not uninstall anything else. The second "' + $cameraDisplayName + '" entry is the microphone and is correct as it is.')
        }
        'healthy' {
            Write-Screen '  1. Start OpenTrack, choose the PS3 Eye camera input and press Start.'
            Write-Screen '  2. If OpenTrack still cannot open the camera, send the report ZIP from the DELANCLIP folder on your Desktop to Delanclip Support.'
        }
        'missing' {
            Write-Screen '  1. Plug the PS3 Eye straight into a USB port at the back of the PC: not a hub, not the front panel.'
            Write-Screen '  2. Wait ten seconds, then run this tool again.'
            Write-Screen '  3. If it still is not found, try another rear port and another cable, then send the report ZIP to Delanclip Support.'
        }
        'cl-eye-installed' {
            Write-Screen '  1. Uninstall the CL-Eye program from Windows Settings, Apps.'
            Write-Screen '  2. Restart Windows.'
            Write-Screen '  3. Run this tool again; it will then clear the stored CL-Eye driver package.'
        }
        default {
            Write-Screen '  1. Unplug the PS3 Eye, wait ten seconds, plug it into a rear USB port and run this tool again.'
            Write-Screen '  2. If the result is the same, send the report ZIP from the DELANCLIP folder on your Desktop to Delanclip Support.'
        }
    }
}

# ------------------------------------------------------- diagnostics module
# The complete PS3 Eye Diagnostics collector (standalone version 1.0.0) runs
# as the first pass of this tool and writes the same report files into the
# run folder. The steps are unchanged apart from the report README, the
# ZIP step (the whole run is zipped at the end instead) and the log lines.

function Invoke-DiagnosticsCollection {
    param([string]$Work)
    $work = $Work
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
$script:stepTotal = 10

function Run-Step {
    param([string]$Name, [scriptblock]$Action)
    $script:stepIndex++
    $label = "[{0,2}/{1}] {2}" -f $script:stepIndex, $script:stepTotal, $Name
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

Run-Step 'README' {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    @"
Delanclip PS3 Eye Fix Tool - report
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
Administrator: $isAdmin
Tool version: $script:toolVersion

Purpose:
Collect Windows device and driver information needed to diagnose PS3 Eye camera problems, then clear the stored driver packages and leftover device entries that keep an old driver on the camera's picture interface (MI_00). What the Fix Tool found and changed is in SUMMARY.txt and LOG.txt; the exported driver packages and UNDO.cmd sit next to this file.

Collected:
- Windows version/build
- matching camera/PnP devices
- device properties and hardware IDs
- installed driver information
- PnPUtil device/driver output (every connected device, every stored third-party package)
- Windows SetupAPI device installation log
- recent Kernel-PnP, UserPnp and DriverFrameworks events
- the PS3 Eye device entries (present and leftover), the stored packages naming the camera, whether the CL-Eye program is installed, and the USB path

Not collected:
- camera pictures or sound
- personal documents
- browser history
- passwords
- emails
- photos
- unrelated personal files

The tool makes no network connections. Its only changes are the removal of stored driver packages that name the PS3 Eye (each exported to this folder first) and of leftover device entries for the camera's picture interface, after confirmation. The microphone interface (MI_01) is never touched.
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
        ($_.FriendlyName -match '(?i)PS3|Eye|USB Camera') -or
        ([string]$_.InstanceId -match '(?i)^USB\\VID_1415&PID_2000')
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
            $matched = @($allDrivers | Where-Object { $_.DeviceID -eq $device.InstanceId })
            if ($matched.Count -eq 0) {
                'No Win32_PnPSignedDriver match found.' | Add-Content -LiteralPath $driverPath -Encoding UTF8
            }
            else {
                $matched |
                    Select-Object DeviceName, DeviceClass, Manufacturer, DriverProviderName, DriverVersion, DriverDate, InfName, IsSigned, Signer, DeviceID |
                    Format-List |
                    Out-String -Width 500 |
                    Add-Content -LiteralPath $driverPath -Encoding UTF8
            }
        }
    }
}

Run-Step 'PnP entity information' {
    $entities = @(Get-CimInstance Win32_PnPEntity |
        Where-Object {
            ($_.PNPClass -eq 'Camera') -or
            ($_.PNPClass -eq 'Image') -or
            ($_.Name -match '(?i)PS3|Eye|USB Camera') -or
            ([string]$_.PNPDeviceID -match '(?i)^USB\\VID_1415&PID_2000')
        })
    $entityPath = Join-Path $work 'camera-pnp-entities.txt'
    if ($entities.Count -eq 0) {
        'No matching PnP entities were found.' | Set-Content -LiteralPath $entityPath -Encoding UTF8
    }
    else {
        $entities |
            Select-Object Name, Status, Manufacturer, PNPClass, Service, ClassGuid, ConfigManagerErrorCode, PNPDeviceID |
            Format-List |
            Out-String -Width 500 |
            Set-Content -LiteralPath $entityPath -Encoding UTF8
    }
}

Run-Step 'PnPUtil connected devices' {
    $r = Invoke-PnpUtil @('/enum-devices', '/connected', '/deviceids', '/drivers') -Quiet
    $r.Output | Set-Content -LiteralPath (Join-Path $work 'connected-devices.txt') -Encoding UTF8
    "PnPUtil exit code: $($r.ExitCode)" | Add-Content -LiteralPath (Join-Path $work 'connected-devices.txt') -Encoding UTF8
}

Run-Step 'PnPUtil driver store' {
    $r = Invoke-PnpUtil @('/enum-drivers') -Quiet
    $r.Output | Set-Content -LiteralPath (Join-Path $work 'driver-store.txt') -Encoding UTF8
    "PnPUtil exit code: $($r.ExitCode)" | Add-Content -LiteralPath (Join-Path $work 'driver-store.txt') -Encoding UTF8
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
}

# ------------------------------------------------------------------- main

try {
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        throw 'This tool must run in 64-bit PowerShell on 64-bit Windows; the 32-bit PowerShell sees a redirected registry.'
    }

    Write-ToolLog ('Delanclip PS3 Eye Fix Tool v' + $toolVersion)
    Write-ToolLog ('Started: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz') + '   Mode: ' + $mode + '   Administrator: ' + $isAdmin + '   User: ' + [Environment]::UserName)
    Write-ToolLog ('Windows build: ' + [Environment]::OSVersion.Version.ToString() + '   64-bit OS: ' + [Environment]::Is64BitOperatingSystem + '   pnputil package commands: ' + $canManagePackages + '   pnputil scan/remove-device: ' + $canScan)
    Write-ToolLog ('Log: ' + $script:LogPath)
    Write-Host ('Delanclip PS3 Eye Fix Tool v' + $toolVersion) -ForegroundColor Cyan
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
    Write-Host 'Step 1 of 2: collecting information about your PC and the camera (about a minute)...'
    Write-Section 'DIAGNOSTICS'
    Invoke-DiagnosticsCollection $runDir
    $script:DiagCollected = $true
    Write-ToolLog ('  report files written to ' + $runDir)

    # ---- check -------------------------------------------------------------
    Write-Host ''
    Write-Host 'Step 2 of 2: checking the PS3 Eye driver state...'
    Invoke-Detection 'before'
    $screen = Get-ScreenFindings
    $fixes = @($script:Findings | Where-Object { $_.Severity -eq 'FIX' })
    $verdict = $script:State.Verdict

    Write-Screen ''
    Write-Screen ('Camera state: ' + (Get-VerdictSentence $verdict) + '.')
    foreach ($note in $screen.Notes) { Write-Screen ('  Note: ' + $note.Human) }

    if ($fixes.Count -eq 0) {
        if ($screen.Manual.Count -gt 0) {
            Write-Screen ''
            Write-Screen 'RESULT: nothing for this tool to repair, but something needs your attention:' 'Yellow'
            foreach ($m in $screen.Manual) { Write-Screen ('  - ' + $m.Human) }
            Write-NextSteps $verdict
            Complete-Run ('nothing to repair; manual attention needed (' + $verdict + ')')
            exit 2
        }
        Write-Screen ''
        if ($verdict -eq 'missing') {
            Write-Screen 'RESULT: no old PS3 Eye driver is stored on this PC, but the camera itself was not found, so there is nothing to repair yet.' 'Yellow'
        }
        else {
            Write-Screen 'RESULT: everything this tool checks is in order. Nothing to repair.' 'Green'
        }
        Write-NextSteps $verdict
        Complete-Run ('nothing to repair (' + $verdict + ')')
        exit 0
    }

    Write-Screen ''
    $n = $screen.Fixes.Count
    Write-Screen ('RESULT: ' + $n + ' problem' + $(if ($n -eq 1) { '' } else { 's' }) + ' found that can keep an old driver on the PS3 Eye.') 'Yellow'
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
    Write-Screen 'Before any change, the packages are exported to the DELANCLIP folder on your Desktop, next to an UNDO script.'
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
            Complete-Run ('problems found; not repaired (no administrator permission) (' + $verdict + ')')
            exit 2
        }
        Write-Host ''
        $answer = Read-Choice 'Repair now? Press Y for yes or N for no:'
        if ($answer -ne 'Y') {
            Write-Screen ''
            Write-Screen 'Nothing was changed. Run the tool again whenever you want to repair.' 'Yellow'
            Complete-Run ('problems found; repair declined (' + $verdict + ')')
            exit 2
        }
        $mode = 'apply'
    }

    # ---- apply -------------------------------------------------------------
    Write-Section 'APPLYING REPAIRS'
    Write-ToolLog ('  Backup folder: ' + $driverBackupDir)
    if (-not (Test-Path -LiteralPath $driverBackupDir)) { New-Item -ItemType Directory -Force -Path $driverBackupDir | Out-Null }
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
    Write-Host 'Asking Windows to look at the camera again ... ' -NoNewline
    Wait-ForRescan
    Write-Host 'done' -ForegroundColor Green
    if (-not $canScan) { Write-Screen 'This Windows version cannot rescan devices on request: unplug the PS3 Eye and plug it in again now, then wait ten seconds.' 'Yellow'; Start-Sleep -Seconds 10 }

    Write-Host 'Checking again ... ' -NoNewline
    Invoke-Detection 'after' -Quiet
    $after = Get-ScreenFindings
    $remaining = @($script:Findings | Where-Object { $_.Severity -eq 'FIX' })
    $verdictAfter = $script:State.Verdict
    if ($remaining.Count -eq 0 -and $script:ApplyErrors -eq 0) {
        Write-Host 'all clear.' -ForegroundColor Green
        Write-ToolLog '>> Verification: all clear'
    }
    else {
        Write-Host 'some problems remain.' -ForegroundColor Yellow
        foreach ($f in $after.Fixes) { Write-Screen ('  - still present: ' + $f.Human) 'Yellow' }
        if ($script:ApplyErrors -gt 0) { Write-Screen ('  - ' + $script:ApplyErrors + ' repair step(s) failed. Please send the report ZIP to Delanclip Support.') 'Yellow' }
    }
    Write-Screen ''
    Write-Screen ('Camera state now: ' + (Get-VerdictSentence $verdictAfter) + '.')
    if ($after.Manual.Count -gt 0) {
        Write-Screen ''
        Write-Screen 'Still needs your attention:'
        foreach ($m in $after.Manual) { Write-Screen ('  - ' + $m.Human) }
    }

    Write-NextSteps $verdictAfter
    Write-Screen ''
    Write-Screen ('Exported packages, UNDO.cmd and the full log are in: ' + $backupDir)
    Write-Screen 'To undo: run UNDO.cmd in that folder as administrator, or run this tool again and press U.'
    $outcome = 'repaired and verified (' + $verdictAfter + ')'
    if ($after.Manual.Count -gt 0) { $outcome = 'repaired; a manual step remains (' + $verdictAfter + ')' }
    if ($remaining.Count -gt 0 -or $script:ApplyErrors -gt 0) { $outcome = 'repaired, but problems remain (' + $remaining.Count + ' finding(s), ' + $script:ApplyErrors + ' failed step(s), ' + $verdictAfter + ')' }
    Complete-Run $outcome

    if ($remaining.Count -gt 0 -or $script:ApplyErrors -gt 0) { exit 2 }
    if ($verdictAfter -eq 'blocked' -or $verdictAfter -eq 'cl-eye-installed') { exit 2 }
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
