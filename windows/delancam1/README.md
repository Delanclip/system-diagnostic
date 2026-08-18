# DelanCam1 Diagnostic Tool (Windows)

`RUN-THIS-DelanCam1-Diagnostics.cmd` collects Windows evidence that can explain
why DelanCam1 is detected incorrectly, produces a corrupted image, or cannot be
used normally by camera software.

The tool writes a report ZIP to the Desktop and does nothing else with it.

## Purpose

Use this tool when screenshots are no longer enough to explain a DelanCam1
problem. It checks several layers that can affect a USB camera:

- DelanCam1 detection, PnP status, driver, INF and USB parent path;
- other Windows devices currently reporting PnP errors;
- registered antivirus products and selected Microsoft Defender status;
- Windows camera privacy consent and camera-access policy values;
- running application names that may use cameras, tracking or virtual cameras;
- camera-related Windows services;
- recent camera-access records exposed by Windows;
- camera-related Windows event logs and matching Application log errors;
- USB power-policy output;
- present driver records matching libusb, Zadig, WinUSB or APP Mode review terms.

The summary is intentionally conservative. A running application or installed
security product is not automatically declared to be the cause. The report
marks evidence that Delanclip Support should review together.

This version does not open or record the DelanCam1 image stream. It can identify
many likely blockers and conflicts, but a clean report does not by itself prove
that the image stream is healthy.

## Usage

1. Keep DelanCam1 connected while the tool runs.
2. Download `RUN-THIS-DelanCam1-Diagnostics.zip` from the latest release and
   unzip it. Do not run the tool from inside the ZIP.
3. Run `RUN-THIS-DelanCam1-Diagnostics.cmd`.
4. Read the privacy notice shown in the window, then press a key to continue.
5. Wait for the tool to finish.
6. Send Delanclip Support the Desktop ZIP whose name begins
   `SEND-TO-DELANCLIP-DelanCam1-Report-`.

Administrator rights are not required. Some Windows information can be more
complete when the tool is run as administrator, but individual collection
failures are recorded instead of stopping the whole diagnostic run.

The tool also runs if DelanCam1 is absent. In that case it records other present
camera devices, including their hardware IDs and bus-reported descriptions, so
support can review whether the camera appeared under an unexpected name.

## Privacy

The tool does not collect:

- camera images or video;
- command lines of running processes;
- browser history;
- passwords;
- emails;
- personal documents, photos or their contents;
- Microsoft Defender threat history or antivirus scan contents.

It does not install software, replace drivers, stop applications, modify Device
Manager, alter camera privacy settings, make network connections, send
telemetry, upload reports or download code.

The report stays on the Desktop until the customer chooses to send it.

The diagnostic does collect some system-wide technical metadata because camera
conflicts are not always caused by the camera itself. This includes:

- names and process IDs of running applications, but not their command lines;
- names, identifiers and Windows error codes of PnP devices reporting problems;
- names of antivirus products registered with Windows Security Center;
- selected Microsoft Defender protection-status fields;
- camera privacy/access records exposed by Windows;
- camera-related Windows services and event-log entries.

Per-application camera access registry paths can contain a Windows user profile
name. The tool redacts that profile component before writing the report.

`setupapi-delancam.txt` contains matching excerpts from the Windows SetupAPI
device-installation log rather than the complete log. `recent-device-events.txt`
is likewise limited to PnP events matching the current DelanCam1 identifiers.

## Output

The report is saved to the Desktop as:

`SEND-TO-DELANCLIP-DelanCam1-Report-YYYYMMDD-HHMMSS.zip`

It contains:

| File | Contents |
| --- | --- |
| `SUMMARY.txt` | Support-facing result and review flags across camera, privacy, security software, applications and PnP |
| `README.txt` | What the run collected and its privacy limits |
| `windows.txt` | Windows edition, build, architecture, last boot time and computer manufacturer/model |
| `camera-devices.txt` | Present camera-class devices, bus descriptions, hardware IDs and instance IDs |
| `delancam-properties.txt` | PnP properties of matching DelanCam1 devices |
| `delancam-driver.txt` | Bound driver provider, version, date, INF, signature and signer |
| `delancam-pnp.txt` | Device Manager/PnP status, service and `ConfigManagerErrorCode` |
| `usb-path.txt` | DelanCam1 parent-device chain and USB location paths |
| `problem-devices.txt` | System-wide PnP devices with non-zero Windows error codes |
| `security-products.txt` | Antivirus products registered with Windows Security Center |
| `defender-status.txt` | Selected Microsoft Defender protection-status fields |
| `camera-policy.txt` | Windows AppPrivacy camera policy values |
| `camera-privacy.txt` | Camera consent values exposed by Windows |
| `camera-access-history.txt` | Per-application camera access records with user profile names redacted |
| `running-processes.txt` | System-wide running process names and process IDs only |
| `potential-camera-apps.txt` | Running process names matching camera, tracking or virtual-camera review terms |
| `camera-services.txt` | Camera-related Windows services and states |
| `camera-event-logs.txt` | Recent entries from enabled Windows Camera/FrameServer event logs |
| `application-camera-errors.txt` | Recent Application log warnings/errors matching camera or OpenTrack terms |
| `power-usb.txt` | Active power scheme and USB power-policy output when available |
| `recent-device-events.txt` | Matching Kernel-PnP, UserPnp and DriverFrameworks events |
| `setupapi-delancam.txt` | Matching excerpts from `setupapi.dev.log` |
| `driver-conflict-hints.txt` | Present driver records matching libusb, Zadig, WinUSB or APP Mode review terms |
| `errors.txt` | Any collection step that failed, including the reason |

Each collection step catches its own failure. One unavailable Windows API or
permission therefore produces a gap in the report instead of losing the whole
run.

## How it works

The `.cmd` file contains its PowerShell implementation after a marker at the end
of the same file. It reads that local section and executes it with Windows
PowerShell, so there is nothing else to install or download.

The script uses Windows PnP, CIM, Security Center, Defender, registry and event
log interfaces already present in Windows. It does not change the state it
reads.

Windows can deny camera access through privacy settings or policy, and Microsoft
Defender exposes protection status through Windows PowerShell. Those system
states are therefore included alongside device and application evidence rather
than treating every corrupted image as a camera hardware fault.
