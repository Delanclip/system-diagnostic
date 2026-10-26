Delanclip PS3 Eye Fix Tool

PURPOSE
This is the tool Delanclip Support asks you to run when your PS3 Eye camera will not take the libusbK driver from the Delanclip manual, or keeps going back to an old driver. In a single run it collects the Windows device and driver information support needs, reads which driver Windows has given the camera, clears the old driver packages that keep coming back (only after you confirm), checks again and zips a report for support.

Good to know: the PS3 Eye shows up twice in Device Manager, both times as "USB Camera-B4.09.24.1". One entry is the picture, the other is the camera's microphone. The microphone is fine as it is. This tool never touches it, and you do not need to uninstall it.

What it does after you press Y:
- backs up every old driver package stored for the camera into the run folder, then removes it from Windows and from the camera (CL-Eye, libusb-win32, a WinUSB package made with Zadig, or a stale libusbK copy)
- removes leftover entries for the camera's picture interface from earlier connections
- asks Windows to look at the camera again and checks the result

The goal is the state the manual needs before its libusbK step: "USB Camera-B4.09.24.1" with an exclamation mark under Other devices. The tool does not install libusbK itself; the manual's Step 2 does that.

Reported, not repaired: the CL-Eye program is still installed (uninstall it from Windows Settings, Apps, restart, run the tool again), or Windows does not see the camera at all (plug it straight into a USB port at the back of the PC and run the tool again).

USAGE
1. Keep the PS3 Eye connected, if possible straight into a rear USB port, and close OpenTrack.
2. Unzip PS3Eye-FixTool.zip.
3. Run PS3Eye-FixTool.cmd. Read the notice and press a key.
   If Windows shows "Smart App Control blocked a file that may be unsafe", close it, right-click PS3Eye-FixTool.cmd and choose "Run as administrator".
4. Accept the Windows administrator prompt (User Account Control). Without it the tool only collects the report and checks; it cannot repair.
5. Step 1 of 2 collects the report (about a minute). Step 2 of 2 checks the driver state. The tool then explains in plain words what it found and what it would remove. Nothing has been changed yet.
6. Press Y to repair, or N to leave everything as it is.
7. The tool checks again and tells you what to do next. Usually: continue with Step 2 of the PS3 Eye manual (the libusbK installer), where the camera will now appear in the list:
   https://delanclip.com/manuals/ps3-eye-camera-head-tracking/
8. Only if the camera still does not work after the manual's steps: send the report ZIP named on the last screen to Delanclip Support.

Everything the tool writes goes into the DELANCLIP folder on your Desktop, which opens by itself when the tool finishes.

Switches: /apply repairs without asking, /undo undoes the most recent repair.
Running the tool again on a repaired system changes nothing and reports the state as ready or healthy.

UNDO
Before a package is removed it is exported into the run folder DELANCLIP\PS3Eye-FixTool-<date-time>\driver-backup on your Desktop, next to UNDO.cmd. To put everything back: run UNDO.cmd in that folder as administrator, or run the tool again and press U when it offers to undo the earlier repair. Then unplug the camera and plug it in again. A backup that has been undone is marked (UNDO-done.cmd, UNDONE.txt) and is not offered again.

PRIVACY
The tool does not collect camera pictures or sound, personal documents, photos, emails, passwords, browser history or any other unrelated personal file.

It does not install software, does not install or download any driver, makes no network connections, sends no telemetry, uploads nothing and downloads no code. It never runs another program's uninstaller.

The only changes it makes, and only after you press Y, are: removing stored driver packages that name the PS3 Eye (each backed up first), removing leftover entries for the camera's picture interface, and a device rescan. The microphone interface is never touched.

The report records your Windows version and computer model, the camera and imaging devices Windows can see with their properties, hardware IDs and drivers, every connected device and every stored third-party driver package (as pnputil lists them), the Windows device installation log, device events from the last 14 days, the camera entries and packages the Fix Tool found with the decision taken on each, whether the run was elevated and the local user name, and every pnputil command with its output. The README.txt inside every report lists it file by file. It stays on your Desktop until you choose to send it.

OUTPUT
Every run creates inside DELANCLIP on the Desktop:
- the run folder PS3Eye-FixTool-<date-time> with every diagnostic report file, SUMMARY.txt (verdict before and after, every camera entry and stored package), LOG.txt (everything shown on screen plus the technical detail), and after a repair the driver-backup folder and UNDO.cmd
- SEND-TO-DELANCLIP-PS3Eye-Report-<date-time>.zip, the run folder zipped: the report for Delanclip Support
