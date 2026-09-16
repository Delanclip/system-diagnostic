# DelanCam1 Fix Tool (Windows)

`DelanCam1-FixTool.cmd` checks the Windows video pipeline that OpenTrack,
AITrack and similar camera software depend on, and repairs the known damage
that stops them from opening DelanCam1 while the Windows Camera app still
shows a picture.

It is the companion of the [DelanCam1 Diagnostic Tool](../delancam1/). The
diagnostic tool only reads and reports. This tool changes registry settings,
but only after showing exactly what it would change, only after the customer
confirms, and only after exporting a backup with a ready-made undo script.

## Purpose

Delanclip Support asks a customer to run this tool after a diagnostic report
shows `WINDOWS VIDEO PIPELINE` flags: MJPEG delivering no frames while raw
formats work, missing VFW codec entries, dead DirectShow registrations, or a
preferred decoder that no longer exists. Those are the confirmed causes of
"Failed to open camera" in OpenTrack on a PC where the camera itself is fine.

The tool checks and, in apply mode, repairs:

| Area | What it checks | What apply mode does |
| --- | --- | --- |
| A | A vendor (NVIDIA, AMD, Intel) hardware MJPEG decoder registered in Media Foundation while the `HardwareMFT` switch leaves hardware decoders enabled; confirmed by a per-format probe that opens DelanCam1 in MJPG, NV12 and YUY2. The repair is offered only when every MJPG format gives nothing while every raw format streams (at least 5 frames in 2 seconds); a camera that also stalls in a raw format is reported as erratic and left alone, because the decoder cannot be what stops it | Sets `EnableDecoders = 0` under `HKLM\SOFTWARE\Microsoft\Windows Media Foundation\HardwareMFT` and stops the Frame Server service so the change takes effect, then probes MJPG again |
| B | The nine stock `vidc.*` entries in `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Drivers32` (64-bit) and the same key under `WOW6432Node` (32-bit) | Re-adds the missing entries, only when the codec DLL exists in `System32` or `SysWOW64`. Entries that point at an existing non-stock DLL are reported and left alone. A legacy codec whose DLL is not shipped by that Windows version at all (Windows 11 has no 64-bit `iccvid.dll`) is logged, not flagged; only a missing `msyuv.dll` or `iyuv_32.dll` is reported as damage |
| C | Entries in the DirectShow "Video Input Devices" and "DirectShow Filters" categories whose DLL no longer exists or which have no `InprocServer32` at all (ghost virtual cameras, dead codec-pack filters), plus the registration of the DirectShow core components | Deletes the dead `Instance` entry and its `CLSID` key, then clears every logged-on user's `ActiveMovie\devenum` cache and re-registers `quartz.dll`, `qcap.dll`, `qedit.dll`, `qdv.dll`, `devenum.dll` and `ksproxy.ax` with `regsvr32 /s` in both views. Virtual cameras whose DLL still exists are listed and never removed |
| D | `HKLM\SOFTWARE\Microsoft\DirectShow\Preferred` (the MJPG entry must point at the Windows MJPEG Decompressor; other entries must point at decoders that exist), the `DoNotUse` list and `TreatAs` redirections on core filters, in both views | Restores the MJPG entry, deletes dangling `Preferred` values, clears `DoNotUse` values and removes `TreatAs` keys |
| E | Camera privacy consent for the machine and each logged-on user, camera policies, the Windows Camera Frame Server service and Fast Startup | Only the Frame Server start type is repaired (Disabled back to Manual). Consent and policy problems are reported with the Settings path to fix them; the tool never changes privacy settings |

The stock entries in `Line 21 Decoder`, `Overlay Mixer`, `Overlay Mixer2` and
`VBI Surface Allocator` have no `InprocServer32` on a normal Windows 10 or 11
installation and are never touched.

## Usage

1. Run the [DelanCam1 Diagnostic Tool](../delancam1/) first and send the
   report to Delanclip Support. Support decides whether this tool is needed.
2. Keep DelanCam1 connected. Close apps that may use the camera (Windows
   Camera, OBS, Teams, Discord, OpenTrack, AITrack).
3. Download `DelanCam1-FixTool.zip` from the latest release and unzip it. Do
   not run the tool from inside the ZIP.
4. Run `DelanCam1-FixTool.cmd`. Read the notice and press a key. Windows then
   shows a User Account Control prompt, because every repair is in `HKLM`.
   Accept it. If it is declined, the tool still runs the check and reports,
   but cannot repair anything.
   If Windows answers the double-click with "Smart App Control blocked a
   file that may be unsafe", close that message, right-click the file and
   choose "Run as administrator". Smart App Control blocks script files
   downloaded from the internet before they start, so nothing inside the tool
   can prevent that message; running as administrator is the documented way
   around it.
5. The tool checks the PC (about 15 seconds, five steps shown on screen)
   and then explains in plain words what it found and what it would repair.
   Nothing has been changed at this point.
6. To repair, press `Y`. Press `N` to leave the system as it is.
7. After the repairs the tool checks everything again and says whether the
   PC is now clean and what to do next.
8. If the tool asks, press `R` to restart Windows in 30 seconds, or restart
   yourself later with "Restart" (not "Shut down"; with Fast Startup on,
   "Shut down" keeps the old driver state). Then run the diagnostic tool once
   more and send the new report to Delanclip Support.

Everything the tool writes lands in a `DELANCLIP` folder on the Desktop, and
that folder opens in File Explorer when the tool finishes, so the results can
be found on a cluttered Desktop and sent to support as a whole.

The screen shows only plain-language results. Every technical detail (registry
paths, identifiers, probe frame counts, each backup and change) goes to the
log file described under Output.

Switches, for Delanclip Support:

| Switch | Effect |
| --- | --- |
| `/apply` | Repair without asking `Repair now?` (the UAC prompt still appears) |
| `/undo` | Undo the most recent repair found on the Desktop, without checking first |
| `/skipprobe` | Do not open the camera for the MJPG/NV12/YUY2 probe |

Running the tool a second time on a repaired system changes nothing and
reports that everything is in order.

## Undo

Before the first change, the tool creates
`DelanCam1-FixTool-backup-YYYYMMDD-HHMMSS` inside the `DELANCLIP` folder on
the Desktop. Every registry key
it is about to change is exported there with `reg export` first. The folder
also gets `UNDO.cmd`, a script that re-imports those exports and deletes the
values the tool added, in reverse order, and `LOG.txt` with the full run.

There are two ways to undo, both one click:

- run `UNDO.cmd` in that folder as administrator (right-click, "Run as
  administrator"), or
- run the tool again: when it finds an earlier repair on the Desktop it
  offers `Press U to undo that repair` before checking anything.

Either way the registry goes back exactly to the state before the repair.
After a successful undo the folder's `UNDO.cmd` is renamed to `UNDO-done.cmd`
and an `UNDONE.txt` note is added, so the same backup is never offered twice.
`UNDO.cmd` itself can be run more than once: a value that is already gone is
skipped instead of counted as a failure.

## Privacy

The tool does not collect:

- camera images or video;
- personal documents, photos, emails, passwords or browser history;
- command lines of running processes;
- the installed-program list or running-process list.

It does not delete files, install software, replace drivers, alter camera
privacy settings, make network connections, send telemetry, upload anything or
download code.

The camera probe briefly opens DelanCam1 with Windows's own camera API and
keeps only frame counts per format. No frame content is saved. When the first
pass does not show MJPEG working, the probe runs a second pass after a one
second pause and keeps the better count per format, so a camera that starts
only now and then is not mistaken for a decoder problem; both counts go to the
log.

The only writes it performs are the registry changes listed under Purpose, the
`regsvr32 /s` re-registration of six Windows DirectShow components, stopping
the Frame Server service (it restarts on demand) and, if it was disabled,
setting that service's start type back to Manual. Every registry write is
preceded by an export to the backup folder. A restart of Windows happens only
when the person presses `R` at the final question, with a 30-second delay.

The log records: Windows build, whether the run was elevated, the local user
name, the profile names of logged-on users (for the per-user consent and
device-cache checks), registry names, identifiers and file paths of decoders,
filters and virtual cameras, per-format frame counts, service state and
restart state. It stays on the Desktop until the customer chooses to send it.

## Output

Check mode writes one file into the `DELANCLIP` folder on the Desktop:

`DelanCam1-FixTool-check-YYYYMMDD-HHMMSS.txt`: every check with its technical
detail, every finding and the exact list of changes a repair would make.

Apply mode creates a folder inside `DELANCLIP` instead:

`DelanCam1-FixTool-backup-YYYYMMDD-HHMMSS`

| File | Contents |
| --- | --- |
| `LOG.txt` | Everything shown on screen plus the technical detail: each check, planned changes, every backup and change made, the verification pass and the next steps |
| `*.reg` | `reg export` of every registry key before it was changed; the name says which area and key |
| `UNDO.cmd` | Restores the exported keys and removes the values the tool added; run as administrator |

Exit codes: 0 when the system is clean or the repairs were applied and
verified; 2 when findings remain (not applied, or a manual step is needed);
1 when the tool itself failed.

The tool prints its version in the window title and on the first line of the
screen and log, the same way the diagnostic tool does.

## How it works

The `.cmd` file contains its PowerShell implementation after a marker at the
end of the same file, exactly like the diagnostic tool. It first shows the
notice, then relaunches itself elevated through the standard Windows prompt,
and the elevated copy reads its own embedded PowerShell section and runs it
with the 64-bit Windows PowerShell 5.1 that ships with Windows 10 and 11.
Nothing is installed or downloaded.

Every check reads the registry with the same rules the diagnostic tool uses,
so a report that shows a flag and this tool agree on what is wrong. Each
finding carries its own repair action; the check pass lists them, the apply
pass runs them one by one (backup, change, log), and a second detection pass
verifies the result. The source is in this folder in the same form it ships
in, so it can be read before it is run.
