Delanclip DelanCam1 Diagnostics
Version 1.4.2

The version number is shown in the title bar and the banner of the tool window and is written into every report (SUMMARY.txt and README.txt inside the ZIP).

PURPOSE
This tool collects Windows evidence that can explain DelanCam1 detection, driver, USB, privacy, security-software and application conflicts. It also briefly opens DelanCam1 to test its live video stream and read its exposure and image-control values, probes MJPG, NV12 and YUY2 separately, maps the USB path the camera is connected through (host controller, hubs, neighbouring devices), collects USB and Plug and Play events, lists kernel filter drivers in the camera path, and inspects the Windows video-decoder registrations (Media Foundation, DirectShow, VFW) and the installed-program list that camera software depends on. The summary names the machine the report came from, so a test on a second computer proves itself.

USAGE
1. Keep DelanCam1 connected.
2. Unzip DelanCam1-Diagnostics.zip.
3. Run DelanCam1-Diagnostics.cmd.
4. Read the notice and press a key to continue.
5. Wait until the report appears on your Desktop. The window shows each step as it runs (step number, name, result and time); a full run usually takes one to two minutes. When the report is ready, a File Explorer window opens by itself with the ZIP selected.
6. Send Delanclip Support the ZIP whose name starts SEND-TO-DELANCLIP-DelanCam1-Report-.

Close other apps that may use a camera (Windows Camera, OBS, Teams, Discord, OpenTrack) before step 3, so the stream test can open DelanCam1 without another app already holding it.

PRIVACY
In short: the tool reads technical device information and Windows settings. It does not read, copy or send any of your private data.

Camera privacy check: Windows has a switch in Settings > Privacy & security > Camera that decides whether apps may use the camera at all, and under it a list of which apps used the camera and when. The tool only reads the state of that switch and that list, because a camera blocked there looks exactly like a broken one. It does not change these settings and it never looks at pictures, videos, documents, messages or accounts.

The tool does not collect camera images or video, command lines of running processes, browser history, passwords, emails, personal documents, photos or their contents.

It does not collect Microsoft Defender threat history or antivirus scan contents.

It does not install software, replace drivers, stop applications, alter privacy settings, make network connections, send telemetry, upload reports or download code.

It does not save any image, video frame or frame content from the camera. The stream test derives only counts, sizes, timestamps, checksums and basic brightness statistics in memory (these detect a frozen or black stream and cannot be turned back into an image) and discards the underlying frame data immediately.

It does collect the computer name, manufacturer, model, mainboard, a masked BIOS serial number and the Windows installation date (to tie a report to the machine it came from), the camera's control values as numbers (exposure, brightness, contrast and similar), the names and hardware identifiers of USB devices sharing the camera's host controller, USB and Plug and Play event-log entries, names, file paths and signers of kernel filter drivers in the camera path, system-wide names and process IDs of running applications, names/statuses of Windows problem devices, registered antivirus product names, selected Defender status, camera privacy/access records, a technical summary of the DelanCam1 video stream (frame counts, measured frame rate, frame sizes, timestamps, frame checksums and basic brightness statistics, plus per-format frame counts), names/versions/publishers/install dates of installed programs, and registry registrations of Media Foundation video decoders, DirectShow filters and virtual cameras and VFW codecs (names, identifiers and file paths only). These are needed to identify software, security, privacy and hardware conflicts that may affect camera access.

WHEN THE REPORT FLAGS THE WINDOWS VIDEO PIPELINE
If SUMMARY.txt shows REVIEW HIGH lines under WINDOWS VIDEO PIPELINE (MJPEG delivers no frames while NV12/YUY2 stream, VFW codec entries are missing, dead DirectShow filters or ghost virtual cameras are registered, or the preferred MJPG decoder is not the Windows default), this tool only reports the problem. Delanclip Support may then send the companion DelanCam1 Fix Tool (DelanCam1-FixTool.zip), which checks first, lists the changes, applies them only after you type APPLY and exports a backup with an undo script before the first change. Run it only when Support asks; afterwards restart Windows and run this diagnostic tool again.

OUTPUT
The report ZIP contains:
- SUMMARY.txt - short diagnostic result and review flags
- README.txt - what was collected and privacy limits
- windows.txt - Windows version/build, installation date, computer name, model, mainboard, masked BIOS serial and machine fingerprint
- camera-devices.txt - present camera-class devices, hardware IDs and bus descriptions
- delancam-properties.txt - DelanCam1 PnP properties
- delancam-driver.txt - driver provider, version, date, INF and signature
- delancam-pnp.txt - Device Manager/PnP status and error code
- usb-path.txt - USB parent chain and location paths
- usb-topology.txt - host controller, hub(s) between DelanCam1 and the root hub, other USB devices on the same controller
- camera-controls.txt - exposure, brightness, contrast, white balance and other camera controls (supported, auto, value, range)
- stream-test.txt - result of briefly opening DelanCam1 and reading live frames: whether it opened, negotiated format (the test requests 640x480 @ 60 FPS, the settings head tracking uses, when available), frame count, measured FPS, zero-length frames, timestamp errors, stream stalls, frozen-frame checksum results and basic brightness statistics, or the exact Windows error if it could not be opened
- format-probe.txt - frames received in two seconds for each of MJPG 640x480 @ 60 and 30, NV12 640x480 @ 60 and 30 and YUY2 640x480 @ 30, with a verdict read per row: healthy, all zero, MJPEG-only failure (every MJPEG row empty, every raw row streaming, no MJPEG frames in the stream test either), intermittent start (MJPEG streamed in the stream test but not in the probe) or erratic start (rows inconsistent)
- media-foundation.txt - Windows hardware-decoder switch, Frame Server state and every registered Media Foundation video decoder (name, identifier, DLL path, Windows or vendor)
- directshow.txt - DirectShow core components, software/virtual cameras, filters with missing files or third-party locations, preferred MJPG decoder, DoNotUse list and VFW codec entries (64-bit and 32-bit views)
- installed-software.txt - installed programs (name, version, publisher, install date), camera/codec/tracking/security/cleaner-related entries first
- restart-state.txt - time since last boot, Fast Startup setting and pending-reboot indicators
- problem-devices.txt - system-wide PnP devices with non-zero Windows error codes
- security-products.txt - antivirus products registered with Windows Security Center
- defender-status.txt - selected Microsoft Defender protection status
- camera-policy.txt - Windows camera-access policy values
- camera-privacy.txt - camera consent values exposed by Windows
- camera-access-history.txt - recent per-application camera access records, with user profile names redacted; SUMMARY.txt names the most recent use before the run and any application that still held the camera while the tool ran
- running-processes.txt - system-wide process names and process IDs only
- potential-camera-apps.txt - process names matching camera, tracking or virtual-camera review terms
- camera-services.txt - camera-related Windows services and status
- camera-event-logs.txt - events from enabled Windows camera/FrameServer logs, in two parts per log: up to 200 events from the 7 days before the tool started, then up to 100 events the run itself generated
- application-camera-errors.txt - recent Application log warnings/errors matching camera/OpenTrack terms
- power-usb.txt - active power scheme and USB power-policy output
- usb-events.txt - USB hub/controller, Kernel-PnP and power events from the System log (14 days), with the ones naming DelanCam1 listed separately
- driver-stack.txt - filter drivers on the camera-related device classes and on DelanCam1, plus the camera's driver stack, with file paths and signers
- recent-device-events.txt - recent matching Windows PnP events
- setupapi-delancam.txt - matching SetupAPI installation-log excerpts
- driver-conflict-hints.txt - present driver records matching libusb, Zadig, WinUSB or APP Mode review terms
- errors.txt - collection steps that failed, if any

This version detects evidence of likely blockers and conflicts, opens DelanCam1 to measure whether its video stream delivers frames at a steady rate and whether frame content changes between captures, reads the camera's exposure and image controls, probes MJPG, NV12 and YUY2 separately, maps the USB path and collects USB events, lists kernel filter drivers in the camera path, inspects the Windows video-decoder registrations, and identifies the machine the report came from. It cannot judge whether a changing image looks correct, so a clean stream test does not by itself prove the picture is right, and registry findings are review flags for Delanclip Support rather than proof of a cause.
