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
echo This tool collects Windows camera, driver, USB, privacy,
echo security-product and running-application information.
echo It does NOT change drivers, install software, record camera images,
echo upload anything, or make network connections.
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
    $summary.Add('This version detects evidence of likely blockers and conflicts but does not yet prove stream health by opening DelanCam1 itself.')
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