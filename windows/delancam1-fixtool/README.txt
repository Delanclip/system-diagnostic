Delanclip DelanCam1 Fix Tool

PURPOSE
This is the one tool Delanclip Support asks you to run when DelanCam1 does not work in OpenTrack, AITrack or similar camera software. In a single run it collects the Windows, camera and USB information support needs, checks the Windows video pipeline that camera software depends on, repairs the known damage (only after you confirm), checks again and zips a report for support.

It checks and can repair:
A. a vendor hardware MJPEG decoder (NVIDIA, AMD, Intel) intercepting Media Foundation - repair: EnableDecoders=0 in HKLM\SOFTWARE\Microsoft\Windows Media Foundation\HardwareMFT, Frame Server service restarted. Offered only when every MJPEG sample of the camera test gives nothing while every raw format streams; a camera that also stalls in a raw format, or streams in one test and not in another, is reported as erratic or intermittent (camera, cable or USB port) and left alone
B. missing 64-bit or 32-bit VFW codec entries (Drivers32 vidc.*) - repair: the stock entries are re-added when the codec DLL exists in Windows; a legacy codec that this Windows version does not ship at all is only logged
C. dead DirectShow registrations: ghost virtual cameras and filters whose DLL no longer exists - repair: the dead entries are deleted, the per-user DirectShow device cache is cleared and the Windows DirectShow core is re-registered with regsvr32
D. DirectShow decoder preferences pointing at removed codecs (Preferred, DoNotUse, TreatAs) - repair: stock values restored, dangling values deleted
E. camera privacy consent, camera policies, the Frame Server service and Fast Startup - only a disabled Frame Server service is repaired; consent and policy problems are reported with instructions

Reported, not repaired: DelanCam1 not among the cameras Windows sees (check the cable and the USB port), or another program holding the camera (close it and run the tool again). Virtual cameras whose program is still installed are listed and never removed.

USAGE
1. Keep DelanCam1 connected. Close Windows Camera, OBS, Teams, Discord, OpenTrack and AITrack.
2. Unzip DelanCam1-FixTool.zip.
3. Run DelanCam1-FixTool.cmd. Read the notice and press a key.
   If Windows shows "Smart App Control blocked a file that may be unsafe", close it, right-click DelanCam1-FixTool.cmd and choose "Run as administrator".
4. Accept the Windows administrator prompt (User Account Control). Without it the tool only collects the report and checks; it cannot repair.
5. Step 1 of 2 collects the report (1 to 2 minutes). Step 2 of 2 checks the Windows video setup. The tool then explains in plain words what it found and what it would repair. Nothing has been changed yet.
6. Press Y to repair, or N to leave everything as it is.
7. After the repairs the tool checks again and tells you what to do next.
8. Press R to restart Windows in 30 seconds, or restart yourself later with "Restart" (not "Shut down"). Then start OpenTrack, pick DelanCam1 again in the camera list and press Start.
9. Only if the camera still does not work: send the report ZIP named on the last screen to Delanclip Support.

Everything the tool writes goes into the DELANCLIP folder on your Desktop, which opens by itself when the tool finishes.

Switches: /apply repairs without asking, /undo undoes the most recent repair, /skipprobe does not open the camera at all.
Running the tool again on a repaired system changes nothing and reports that everything is in order.

UNDO
Before the first change every registry key the tool changes is exported into the run folder DELANCLIP\DelanCam1-FixTool-<date-time> on your Desktop, next to UNDO.cmd. To put everything back: run UNDO.cmd in that folder as administrator, or run the tool again and press U when it offers to undo the earlier repair. A backup that has been undone is marked (UNDO-done.cmd, UNDONE.txt) and is not offered again.

PRIVACY
The tool does not collect camera images or video, personal documents, photos, emails, passwords, browser history, command lines of running processes, or antivirus scan contents.

It does not delete files, install software, replace drivers, alter camera privacy settings, make network connections, send telemetry, upload anything or download code.

The camera tests briefly open DelanCam1 with Windows's own camera API and keep only frame counts, timestamps and in-memory checksums per format.

The only writes it performs are the registry changes listed above, the regsvr32 re-registration of six Windows DirectShow components, stopping the Frame Server service (it restarts on demand) and, if it was disabled, setting that service back to Manual. Every registry change is preceded by an export to the run folder.

The report records the Windows build and machine identity, camera devices, DelanCam1 driver and USB path, USB topology, camera test results (counts only), Media Foundation, DirectShow and VFW registrations, installed program names and versions, running process names, camera privacy and access history with user profile names redacted, camera and USB event logs, services, restart state, whether the run was elevated and the local user name, plus every backup and change the Fix Tool made. The README.txt inside every report lists it file by file. It stays on your Desktop until you choose to send it.

OUTPUT
Every run creates inside DELANCLIP on the Desktop:
- the run folder DelanCam1-FixTool-<date-time> with every diagnostic report file (SUMMARY.txt, README.txt, stream-test.txt, format-probe.txt, directshow.txt and the rest), LOG.txt (everything shown on screen plus the technical detail), and after a repair the *.reg exports and UNDO.cmd
- SEND-TO-DELANCLIP-DelanCam1-Report-<date-time>.zip, the run folder zipped: the report for Delanclip Support

SUMMARY.txt ends with a FIX TOOL section: outcome, camera probe verdict, findings of the last check and repaired areas.
