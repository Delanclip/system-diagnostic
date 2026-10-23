# DelanCam1 Fix Tool (Windows)

Current version: **2.0.0**. The version number is shown in the title bar and
the banner of the tool window and is written into `LOG.txt`, `README.txt` and
`SUMMARY.txt` of every report, so a report can always be matched to the
version that produced it.

`DelanCam1-FixTool.cmd` is the one tool Delanclip Support asks a customer to
run when DelanCam1 does not work in OpenTrack, AITrack or similar camera
software. In a single run it:

1. collects the same Windows, camera and USB evidence the former
   [DelanCam1 Diagnostic Tool](../delancam1/) collected (the diagnostic
   collector is embedded unchanged, so the report files are the ones support
   already knows);
2. detects the known Windows video-pipeline damage that stops OpenTrack while
   the Windows Camera app still shows a picture;
3. repairs it, only after showing in plain words what it found and only after
   the customer presses `Y`, with a registry backup and a ready-made undo
   script written first;
4. checks again, tells the customer what to do next, and zips the whole run
   into a report for support.

The standalone diagnostic tool is kept as a finished project and is no longer
developed; everything it did now happens inside this tool.

## Purpose

The tool checks and, in apply mode, repairs:

| Area | What it checks | What apply mode does |
| --- | --- | --- |
| A | A vendor (NVIDIA, AMD, Intel) hardware MJPEG decoder registered in Media Foundation while the `HardwareMFT` switch leaves hardware decoders enabled; confirmed by the camera test of the diagnostics pass (stream test, per-format probe in MJPG, NV12 and YUY2, re-open cycles). The repair is offered only when every MJPG sample gives nothing while every raw format streams; a camera that also stalls in a raw format, or that streams in one sample and not in another, is reported as erratic or intermittent and left alone, because the decoder cannot be what stops it | Sets `EnableDecoders = 0` under `HKLM\SOFTWARE\Microsoft\Windows Media Foundation\HardwareMFT` and stops the Frame Server service so the change takes effect, then opens the camera again to verify |
| B | The nine stock `vidc.*` entries in `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Drivers32` (64-bit) and the same key under `WOW6432Node` (32-bit) | Re-adds the missing entries, only when the codec DLL exists in `System32` or `SysWOW64`. Entries that point at an existing non-stock DLL are reported and left alone. A legacy codec whose DLL is not shipped by that Windows version at all (Windows 11 has no 64-bit `iccvid.dll`) is logged, not flagged; only a missing `msyuv.dll` or `iyuv_32.dll` is reported as damage |
| C | Entries in the DirectShow "Video Input Devices" and "DirectShow Filters" categories whose DLL no longer exists or which have no `InprocServer32` at all (ghost virtual cameras, dead codec-pack filters), plus the registration of the DirectShow core components | Deletes the dead `Instance` entry and its `CLSID` key, then clears every logged-on user's `ActiveMovie\devenum` cache and re-registers `quartz.dll`, `qcap.dll`, `qedit.dll`, `qdv.dll`, `devenum.dll` and `ksproxy.ax` with `regsvr32 /s` in both views. Virtual cameras whose DLL still exists are listed and never removed |
| D | `HKLM\SOFTWARE\Microsoft\DirectShow\Preferred` (the MJPG entry must point at the Windows MJPEG Decompressor; other entries must point at decoders that exist), the `DoNotUse` list and `TreatAs` redirections on core filters, in both views | Restores the MJPG entry, deletes dangling `Preferred` values, clears `DoNotUse` values and removes `TreatAs` keys |
| E | Camera privacy consent for the machine and each logged-on user, camera policies, the Windows Camera Frame Server service and Fast Startup | Only the Frame Server start type is repaired (Disabled back to Manual). Consent and policy problems are reported with the Settings path to fix them; the tool never changes privacy settings |

Two situations are reported instead of repaired, because no registry change
helps: DelanCam1 is not among the cameras Windows sees (check the cable and
the USB port), or another program is holding the camera (the report names it;
close it and run the tool again).

The stock entries in `Line 21 Decoder`, `Overlay Mixer`, `Overlay Mixer2` and
`VBI Surface Allocator` have no `InprocServer32` on a normal Windows 10 or 11
installation and are never touched.

## What the diagnostics pass collects

The first pass is the complete DelanCam1 Diagnostics collector (last
standalone version 1.4.3) and writes the same files: Windows version and
machine identity, camera devices and DelanCam1 PnP, driver and USB path, the
USB topology and port map, the stream test, the per-format probe and re-open
cycles, Media Foundation decoders, DirectShow registrations and VFW codecs,
installed programs, restart state, problem devices, security products,
camera privacy and access history, running processes, camera services,
camera and USB event logs, driver stack and class filters, and the
`SUMMARY.txt` with review flags. The full list, file by file, is in the
[diagnostic tool's README](../delancam1/README.md); the `README.txt` inside
every report repeats it.

The camera is opened by the diagnostics pass only. The detection pass reads
those counts: for MJPG 640x480@60 it keeps every sample (stream test,
per-format probe, three re-open cycles), the best one counts, and samples
that disagree mark the camera start as intermittent. After a repair of area A
the camera is opened once more to verify.

## Usage

1. Keep DelanCam1 connected. Close apps that may use the camera (Windows
   Camera, OBS, Teams, Discord, OpenTrack, AITrack).
2. Download `DelanCam1-FixTool.zip` from the latest release and unzip it. Do
   not run the tool from inside the ZIP.
3. Run `DelanCam1-FixTool.cmd`. Read the notice and press a key. Windows then
   shows a User Account Control prompt, because every repair is in `HKLM`.
   Accept it. If it is declined, the tool still collects the report and
   checks the PC, but cannot repair anything.
   If Windows answers the double-click with "Smart App Control blocked a
   file that may be unsafe", close that message, right-click the file and
   choose "Run as administrator". Smart App Control blocks script files
   downloaded from the internet before they start, so nothing inside the tool
   can prevent that message; running as administrator is the documented way
   around it.
4. Step 1 of 2 collects the report (1 to 2 minutes, every step shown on
   screen). Step 2 of 2 checks the Windows video setup on that data and then
   explains in plain words what it found and what it would repair. Nothing
   has been changed at this point.
5. To repair, press `Y`. Press `N` to leave the system as it is.
6. After the repairs the tool checks everything again and says whether the
   PC is now clean and what to do next.
7. If the tool asks, press `R` to restart Windows in 30 seconds, or restart
   yourself later with "Restart" (not "Shut down"; with Fast Startup on,
   "Shut down" keeps the old driver state). Then start OpenTrack, pick
   DelanCam1 again in the camera list and press Start.
8. Only if the camera still does not work: send the report ZIP named on the
   last screen to Delanclip Support.

Everything the tool writes lands in a `DELANCLIP` folder on the Desktop, and
that folder opens in File Explorer when the tool finishes, so the results can
be found on a cluttered Desktop.

The screen shows only plain-language results. Every technical detail (registry
paths, identifiers, probe frame counts, each backup and change) goes to
`LOG.txt` in the run folder.

Switches, for Delanclip Support:

| Switch | Effect |
| --- | --- |
| `/apply` | Repair without asking `Repair now?` (the UAC prompt still appears) |
| `/undo` | Undo the most recent repair found on the Desktop, without collecting or checking first |
| `/skipprobe` | Do not open the camera at all (no stream test, probe or re-open cycles); area A is then repaired on the registry evidence alone |

Running the tool a second time on a repaired system changes nothing and
reports that everything is in order. A second-computer test is the same run
on the other PC with `N` at the question; without administrator permission it
only collects and reports.

## Undo

Before the first change, every registry key the tool is about to change is
exported with `reg export` into the run folder
`DELANCLIP\DelanCam1-FixTool-YYYYMMDD-HHMMSS`. The folder also gets
`UNDO.cmd`, a script that re-imports those exports and deletes the values the
tool added, in reverse order.

There are two ways to undo, both one click:

- run `UNDO.cmd` in that folder as administrator (right-click, "Run as
  administrator"), or
- run the tool again: when it finds an earlier repair on the Desktop it
  offers `Press U to undo that repair` before collecting anything.

Either way the registry goes back exactly to the state before the repair.
After a successful undo the folder's `UNDO.cmd` is renamed to `UNDO-done.cmd`
and an `UNDONE.txt` note is added, so the same backup is never offered twice.
`UNDO.cmd` itself can be run more than once: a value that is already gone is
skipped instead of counted as a failure. Repairs made by versions 1.x (folders
named `DelanCam1-FixTool-backup-...`) are found and offered the same way.

## Privacy

The tool does not collect:

- camera images or video;
- personal documents, photos, emails, passwords or browser history;
- command lines of running processes;
- Microsoft Defender threat history or antivirus scan contents.

It does not delete files, install software, replace drivers, alter camera
privacy settings, make network connections, send telemetry, upload anything or
download code.

The camera tests open DelanCam1 with Windows's own camera API and keep only
frame counts, timestamps and in-memory checksums per format. No frame content
is saved.

The only writes it performs are the registry changes listed under Purpose, the
`regsvr32 /s` re-registration of six Windows DirectShow components, stopping
the Frame Server service (it restarts on demand) and, if it was disabled,
setting that service's start type back to Manual. Every registry write is
preceded by an export to the run folder. A restart of Windows happens only
when the person presses `R` at the final question, with a 30-second delay.

The report records what the diagnostic collector always recorded (see the
[diagnostic tool's README](../delancam1/README.md)) plus the Fix Tool's own
log: Windows build, whether the run was elevated, the local user name, the
profile names of logged-on users, registry names, identifiers and file paths
of decoders, filters and virtual cameras, per-format frame counts, service
state, restart state, every backup and every change. It stays on the Desktop
until the customer chooses to send it.

## Output

Every run creates, inside the `DELANCLIP` folder on the Desktop:

| Item | Contents |
| --- | --- |
| `DelanCam1-FixTool-YYYYMMDD-HHMMSS\` | The run folder: every diagnostic report file (`SUMMARY.txt`, `README.txt`, `stream-test.txt`, `format-probe.txt`, `directshow.txt` and the rest), `LOG.txt` with everything shown on screen plus the technical detail, and, once a repair was made, the `*.reg` exports and `UNDO.cmd` |
| `SEND-TO-DELANCLIP-DelanCam1-Report-YYYYMMDD-HHMMSS.zip` | The run folder zipped: the report for Delanclip Support |

`SUMMARY.txt` ends with a `FIX TOOL` section: the outcome, the camera probe
verdict, the findings of the last detection pass and the repaired areas.

Exit codes: 0 when the system is clean or the repairs were applied and
verified; 2 when findings remain (not applied, or a manual step is needed);
1 when the tool itself failed.

## How it works

The `.cmd` file contains its PowerShell implementation after a marker at the
end of the same file. It first shows the notice, then relaunches itself
elevated through the standard Windows prompt, and the elevated copy reads its
own embedded PowerShell section and runs it with the 64-bit Windows
PowerShell 5.1 that ships with Windows 10 and 11. Nothing is installed or
downloaded.

Inside, the diagnostic collector runs first as one function and writes its
files into the run folder. The detection pass then reads the registry with
the same rules the collector uses and takes the camera counts from the
collector's files, so the report and the repair never disagree. Each finding
carries its own repair action; the check pass lists them, the apply pass runs
them one by one (backup, change, log), and a second detection pass verifies
the result. The source is in this folder in the same form it ships in, so it
can be read before it is run.
