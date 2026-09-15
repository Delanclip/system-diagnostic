Delanclip DelanCam1 Fix Tool

PURPOSE
This tool checks the Windows video pipeline that OpenTrack, AITrack and similar camera software depend on, and repairs the known damage that stops them from opening DelanCam1 while the Windows Camera app still shows a picture. Run it only when Delanclip Support asks for it, after they have read your DelanCam1 Diagnostics report.

It checks and can repair:
A. a vendor hardware MJPEG decoder (NVIDIA, AMD, Intel) intercepting Media Foundation - repair: EnableDecoders=0 in HKLM\SOFTWARE\Microsoft\Windows Media Foundation\HardwareMFT, Frame Server service restarted
B. missing 64-bit or 32-bit VFW codec entries (Drivers32 vidc.*) - repair: the stock entries are re-added when the codec DLL exists in Windows; a legacy codec that this Windows version does not ship at all is only logged
C. dead DirectShow registrations: ghost virtual cameras and filters whose DLL no longer exists - repair: the dead entries are deleted, the per-user DirectShow device cache is cleared and the Windows DirectShow core is re-registered with regsvr32
D. DirectShow decoder preferences pointing at removed codecs (Preferred, DoNotUse, TreatAs) - repair: stock values restored, dangling values deleted
E. camera privacy consent, camera policies, the Frame Server service and Fast Startup - only a disabled Frame Server service is repaired; consent and policy problems are reported with instructions

Virtual cameras whose program is still installed are listed and never removed.

USAGE
1. Keep DelanCam1 connected. Close Windows Camera, OBS, Teams, Discord, OpenTrack and AITrack.
2. Unzip DelanCam1-FixTool.zip.
3. Run DelanCam1-FixTool.cmd. Read the notice and press a key.
   If Windows shows "Smart App Control blocked a file that may be unsafe", close it, right-click DelanCam1-FixTool.cmd and choose "Run as administrator".
4. Accept the Windows administrator prompt (User Account Control). Without it the tool can only check, not repair.
5. Read the result. The tool explains in plain words what it found and what it would repair. Nothing has been changed yet.
6. Press Y to repair, or N to leave everything as it is.
7. After the repairs the tool checks again and tells you what to do next.
8. Press R to restart Windows in 30 seconds, or restart yourself later with "Restart" (not "Shut down"). Then run the DelanCam1 Diagnostics tool again and send the new report to Delanclip Support.

Everything the tool writes goes into the DELANCLIP folder on your Desktop, which opens by itself when the tool finishes.

Switches: /apply repairs without asking, /undo undoes the most recent repair, /skipprobe skips opening the camera.
Running the tool again on a repaired system changes nothing and reports that everything is in order.

UNDO
Before the first change the tool creates the folder DelanCam1-FixTool-backup-<date-time> inside DELANCLIP on your Desktop. Every registry key it changes is exported there first. To put everything back: run UNDO.cmd in that folder as administrator, or run the tool again and press U when it offers to undo the earlier repair. A backup that has been undone is marked (UNDO-done.cmd, UNDONE.txt) and is not offered again.

PRIVACY
The tool does not collect camera images or video, personal documents, photos, emails, passwords, browser history, command lines of running processes, the installed-program list or the running-process list.

It does not delete files, install software, replace drivers, alter camera privacy settings, make network connections, send telemetry, upload anything or download code.

The camera probe briefly opens DelanCam1 with Windows's own camera API and keeps only frame counts per format.

The only writes it performs are the registry changes listed above, the regsvr32 re-registration of six Windows DirectShow components, stopping the Frame Server service (it restarts on demand) and, if it was disabled, setting that service back to Manual. Every registry change is preceded by an export to the backup folder.

The log records the Windows build, whether the run was elevated, the local user name, profile names of logged-on users, registry names, identifiers and file paths of decoders, filters and virtual cameras, per-format frame counts, service state and restart state. It stays on your Desktop until you choose to send it.

OUTPUT
Check only: DELANCLIP\DelanCam1-FixTool-check-<date-time>.txt on the Desktop, the complete output of the run.
After a repair: the folder DELANCLIP\DelanCam1-FixTool-backup-<date-time> on the Desktop with:
- LOG.txt - everything shown on screen plus the technical detail: each check, planned changes, every backup and change, verification, next steps
- *.reg - reg export of every registry key before it was changed
- UNDO.cmd - restores the previous state; run as administrator

If Delanclip Support asks for it, send them the whole DELANCLIP folder from your Desktop.
