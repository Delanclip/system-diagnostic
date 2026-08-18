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
- present driver records matching libusb, Zadig, WinUSB or APP Mode review terms;
- a native stream test: opens DelanCam1 with Windows's own camera APIs, requests
  the 640x480 @ 60 FPS format head tracking uses when the camera offers it, and
  reads live frames for a few seconds to measure whether frames arrive, how
  fast, whether the stream stalls, and whether frame content changes between
  captures.

The summary is intentionally conservative. A running application or installed
security product is not automatically declared to be the cause. The report
marks evidence that Delanclip Support should review together.

This version also opens DelanCam1 for a few seconds and measures whether its
video stream delivers frames at a steady rate and whether frames change between
captures (a frozen-stream check). It does not save any image or video data, and
it cannot judge whether a changing image looks correct, so a clean stream test
does not by itself prove that the picture is right.

## Usage

1. Keep DelanCam1 connected while the tool runs.
2. Close other apps that may use a camera, such as Windows Camera, OBS, Teams,
   Discord or OpenTrack, so the stream test can open DelanCam1 without another
   app already holding it.
3. Download `RUN-THIS-DelanCam1-Diagnostics.zip` from the latest release and
   unzip it. Do not run the tool from inside the ZIP.
4. Run `RUN-THIS-DelanCam1-Diagnostics.cmd`.
5. Read the privacy notice shown in the window, then press a key to continue.
6. Wait for the tool to finish. The stream test briefly opens DelanCam1 and
   takes a few seconds.
7. Send Delanclip Support the Desktop ZIP whose name begins
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

The stream test briefly opens DelanCam1 using Windows's own camera APIs, but it
does not save any image, video frame or frame content. It derives only counts,
sizes, timestamps, checksums and basic brightness statistics in memory and
discards the underlying frame data immediately. The checksums exist to detect a
frozen stream (frames that never change) and the brightness statistics tell a
genuinely dark scene apart from a frozen detailed image; neither can be turned
back into a picture.

The report stays on the Desktop until the customer chooses to send it.

The diagnostic does collect some system-wide technical metadata because camera
conflicts are not always caused by the camera itself. This includes:

- names and process IDs of running applications, but not their command lines;
- names, identifiers and Windows error codes of PnP devices reporting problems;
- names of antivirus products registered with Windows Security Center;
- selected Microsoft Defender protection-status fields;
- camera privacy/access records exposed by Windows;
- camera-related Windows services and event-log entries;
- a technical summary of the DelanCam1 video stream obtained by briefly opening
  the camera: frame counts, measured frame rate, frame sizes, timestamps, frame
  checksums and basic brightness statistics.

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
| `stream-test.txt` | Result of briefly opening DelanCam1 and reading live frames: whether it opened, negotiated format (the test requests 640x480 @ 60 FPS when available), frame count, measured FPS, zero-length frames, timestamp errors, stream stalls, frozen-frame checksum results and basic brightness statistics, or the exact Windows error if it could not be opened |
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

The stream test uses Windows's built-in Windows Runtime camera APIs
(`Windows.Media.Capture` / `MediaFrameReader`), the same OS-level interfaces
used by the Windows Camera app. Nothing is downloaded or installed to run it.
It selects DelanCam1 by matching its known VID/PID first, and falls back to a
name match if that identifier is not present, so a device renamed by an
unexpected driver can still be tested. Before starting the stream it asks the
camera for 640x480 at 60 FPS - the settings head-tracking software uses - and
falls back to the camera's default format if that request fails. Every Windows
Runtime call is bounded by a timeout, so a stalled or unresponsive camera
cannot hang the rest of the diagnostic run; a timeout is recorded as an error
in `stream-test.txt` like any other failure.

During capture each frame is checksummed in memory (MD5 over the raw pixel
buffer) solely to count how many distinct frame contents arrived, and a small
sample of pixel bytes is periodically reduced to min/max/mean brightness. A
healthy live sensor normally produces a different checksum for every frame, but
an IR tracking camera looking at a scene with nothing bright in it can
legitimately produce identical, essentially black frames - the brightness
statistics let the report tell that apart from a stream frozen on a detailed
image. The pixel data itself is discarded immediately after these numbers are
computed.

Windows can deny camera access through privacy settings or policy, and Microsoft
Defender exposes protection status through Windows PowerShell. Those system
states are therefore included alongside device and application evidence rather
than treating every corrupted image as a camera hardware fault.
