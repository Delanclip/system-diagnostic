Delanclip DelanCam1 Diagnostics

PURPOSE
This tool collects Windows device, driver, PnP and USB-path information needed by Delanclip Support when DelanCam1 is not behaving correctly.

USAGE
1. Keep DelanCam1 connected.
2. Unzip the downloaded package.
3. Run Delanclip-DelanCam1-Diagnostics.cmd.
4. Read the notice and press a key to continue.
5. Wait until the ZIP report appears on your Desktop.
6. Attach that ZIP to your reply to Delanclip Support.

PRIVACY
The tool does not collect camera images or video, personal documents, browser history, passwords, emails, photos or unrelated personal files.

It does not install software, replace drivers, make network connections, send telemetry, upload reports or download code.

It does collect the names and identifiers of present camera-class devices so support can see whether DelanCam1 appears under an unexpected name.

OUTPUT
The ZIP contains:
- SUMMARY.txt - short diagnostic result and review flags
- windows.txt - Windows version/build and computer model
- camera-devices.txt - present camera-class devices
- delancam-properties.txt - DelanCam1 PnP properties and hardware IDs
- delancam-driver.txt - driver provider, version, date, INF and signature
- delancam-pnp.txt - Device Manager/PnP status and error code
- usb-path.txt - USB parent chain and location paths
- recent-device-events.txt - recent matching Windows PnP events
- setupapi-delancam.txt - matching SetupAPI installation-log excerpts
- errors.txt - collection steps that failed, if any

Version 1 does not open or record the camera stream and does not change anything in Windows.
