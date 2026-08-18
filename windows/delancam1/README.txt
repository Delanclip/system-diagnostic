Delanclip DelanCam1 Diagnostics

PURPOSE
This tool collects Windows evidence that can explain DelanCam1 detection, driver, USB, privacy, security-software and application conflicts.

USAGE
1. Keep DelanCam1 connected.
2. Unzip RUN-THIS-DelanCam1-Diagnostics.zip.
3. Run RUN-THIS-DelanCam1-Diagnostics.cmd.
4. Read the notice and press a key to continue.
5. Wait until the report appears on your Desktop.
6. Send Delanclip Support the ZIP whose name starts SEND-TO-DELANCLIP-DelanCam1-Report-.

PRIVACY
The tool does not collect camera images or video, command lines of running processes, browser history, passwords, emails, personal documents, photos or their contents.

It does not collect Microsoft Defender threat history or antivirus scan contents.

It does not install software, replace drivers, stop applications, alter privacy settings, make network connections, send telemetry, upload reports or download code.

It does collect system-wide names and process IDs of running applications, names/statuses of Windows problem devices, registered antivirus product names, selected Defender status and camera privacy/access records. These are needed to identify software, security, privacy and hardware conflicts that may affect camera access.

OUTPUT
The report ZIP contains:
- SUMMARY.txt - short diagnostic result and review flags
- README.txt - what was collected and privacy limits
- windows.txt - Windows version/build and computer model
- camera-devices.txt - present camera-class devices, hardware IDs and bus descriptions
- delancam-properties.txt - DelanCam1 PnP properties
- delancam-driver.txt - driver provider, version, date, INF and signature
- delancam-pnp.txt - Device Manager/PnP status and error code
- usb-path.txt - USB parent chain and location paths
- problem-devices.txt - system-wide PnP devices with non-zero Windows error codes
- security-products.txt - antivirus products registered with Windows Security Center
- defender-status.txt - selected Microsoft Defender protection status
- camera-policy.txt - Windows camera-access policy values
- camera-privacy.txt - camera consent values exposed by Windows
- camera-access-history.txt - recent per-application camera access records, with user profile names redacted
- running-processes.txt - system-wide process names and process IDs only
- potential-camera-apps.txt - process names matching camera, tracking or virtual-camera review terms
- camera-services.txt - camera-related Windows services and status
- camera-event-logs.txt - recent events from enabled Windows camera/FrameServer logs
- application-camera-errors.txt - recent Application log warnings/errors matching camera/OpenTrack terms
- power-usb.txt - active power scheme and USB power-policy output
- recent-device-events.txt - recent matching Windows PnP events
- setupapi-delancam.txt - matching SetupAPI installation-log excerpts
- driver-conflict-hints.txt - present driver records matching libusb, Zadig, WinUSB or APP Mode review terms
- errors.txt - collection steps that failed, if any

This version detects evidence of likely blockers and conflicts. It does not yet prove image-stream health by opening or recording DelanCam1.
