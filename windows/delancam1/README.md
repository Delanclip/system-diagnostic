# DelanCam1 Diagnostic Tool (Windows)

`Delanclip-DelanCam1-Diagnostics.cmd` collects the Windows device, driver, PnP
and USB-path information that Delanclip Support needs when DelanCam1 is detected
incorrectly or produces a corrupted image.

The tool writes a ZIP file to the Desktop and does nothing else with it.

## Purpose

Use this tool when screenshots are no longer enough to explain a DelanCam1
problem, especially when:

- Windows or OpenTrack sees DelanCam1, but the image is corrupted;
- Device Manager shows a warning or unexpected status;
- support needs to confirm which driver and INF Windows actually loaded;
- the camera behaves differently across USB ports or computers;
- support needs the USB parent path and recent PnP errors.

DelanCam1 is designed to use the native Windows camera driver. This tool does
not assume that a non-Microsoft provider is automatically the cause, but it
flags that result for support review.

Version 1 deliberately does not open or record the camera stream. Detection and
driver diagnosis come first. A later version can add a local stream test if
real support cases show that it is needed.

## Usage

1. Keep DelanCam1 connected while the tool runs.
2. Download `Delanclip-DelanCam1-Diagnostics.zip` from the latest release and
   unzip it. Do not run the tool from inside the ZIP.
3. Run `Delanclip-DelanCam1-Diagnostics.cmd`.
4. Read the privacy notice shown in the window, then press a key to continue.
5. Wait for the tool to finish. It creates a ZIP on the Desktop and selects it
   in File Explorer.
6. Reply to Delanclip Support and attach that ZIP.

Administrator rights are not required. Some Windows information can be more
complete when the tool is run as administrator, but the script records failures
instead of stopping the whole diagnostic run.

The tool also runs if DelanCam1 is absent. In that case the report records that
no matching present device was found and lists other present camera devices for
context.

## Privacy

The tool does not collect:

- camera images or video;
- personal documents;
- browser history;
- passwords;
- emails;
- photos;
- unrelated personal files.

It does not install software, replace drivers, modify Device Manager settings,
make network connections, send telemetry, upload reports or download code.

The report stays on the Desktop until the customer chooses to send it.

The report does include the names and device identifiers of present camera
class devices. This is necessary so support can see whether Windows has exposed
DelanCam1 under an unexpected camera name.

`setupapi-delancam.txt` contains only matching excerpts from the Windows
SetupAPI device-installation log, rather than a copy of the complete system log.
`recent-device-events.txt` is likewise limited to PnP events matching the
current DelanCam1 device identifiers.

## Output

The report is saved to the Desktop as:

`Delanclip-DelanCam1-Diagnostics-YYYYMMDD-HHMMSS.zip`

It contains:

| File | Contents |
| --- | --- |
| `SUMMARY.txt` | Short support-facing result: detected device, PnP status, Device Manager error code, service, driver provider, version, INF and review flags |
| `README.txt` | What the run collected, when it ran and whether it had administrator rights |
| `windows.txt` | Windows edition, build, architecture, last boot time and computer manufacturer/model |
| `camera-devices.txt` | Present Camera/Image devices plus DelanCam matches: status, class, friendly name and instance ID |
| `delancam-properties.txt` | PnP properties of matching DelanCam1 devices, including hardware IDs and location information exposed by Windows |
| `delancam-driver.txt` | Bound signed-driver data: provider, version, date, INF, signature and signer |
| `delancam-pnp.txt` | Device Manager/PnP entity status, service and `ConfigManagerErrorCode` |
| `usb-path.txt` | DelanCam1 parent-device chain, bus description and location paths up through the USB stack |
| `recent-device-events.txt` | Matching Kernel-PnP, UserPnp and DriverFrameworks events from the previous 14 days |
| `setupapi-delancam.txt` | Matching excerpts from `setupapi.dev.log` for DelanCam1 and its current hardware identifier |
| `errors.txt` | Any collection step that failed, including the reason |

Each collection step catches its own failure. One unavailable Windows API or
permission therefore produces a gap in the report instead of losing the whole
run.

## How it works

The `.cmd` file contains its PowerShell implementation after a marker at the end
of the same file. It reads that local section and executes it with Windows
PowerShell, so there is nothing else to install or download.

The script uses Windows PnP and CIM interfaces already present in supported
Windows installations. It enumerates camera-class devices, narrows the detailed
collection to DelanCam1 matches, reads the bound signed-driver record, checks the
PnP entity status, walks the parent device path and extracts matching diagnostic
events.

The summary is intentionally conservative. It reports facts and marks unusual
results for review, but it does not automatically replace drivers or declare a
camera faulty.
