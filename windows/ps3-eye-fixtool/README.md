# PS3 Eye Fix Tool (Windows)

Current version: **1.0.0**. The version number is shown in the title bar and
the banner of the tool window and is written into `LOG.txt`, `README.txt` and
`SUMMARY.txt` of every report, so a report can always be matched to the
version that produced it.

`PS3Eye-FixTool.cmd` is the tool Delanclip Support asks a customer to run when
a PS3 Eye camera will not take the libusbK driver the Delanclip manual
installs, or keeps falling back to an old driver. In a single run it:

1. collects the same Windows device and driver evidence the
   [PS3 Eye Diagnostic Tool](../ps3-eye/) collects (that collector is embedded
   unchanged, so the report files are the ones support already knows);
2. reads which driver Windows has given the camera's picture interface and
   which driver packages for the camera Windows keeps in its driver store;
3. after showing in plain words what it found, and only after the customer
   presses `Y`, exports those stored packages to the run folder, removes them
   from the driver store and from the camera, removes leftover device
   entries, and asks Windows to look at the camera again;
4. checks again, says what to do next, and zips the whole run into a report
   for support.

The goal state is the one the manual needs before its libusbK step: the
picture interface with no driver, listed under **Other devices** in Device
Manager as `USB Camera-B4.09.24.1` with an exclamation mark. The tool does not
install libusbK itself.

## Purpose

The PS3 Eye is a composite USB device (`USB\VID_1415&PID_2000`) with two
interfaces. `MI_00` is the picture; `MI_01` is the camera's microphone. Windows
names both `USB Camera-B4.09.24.1`, which is the root of the most common
support case:

- the customer uninstalls the second entry, the microphone, again and again,
  thinking it is the driver (one report showed about twenty such uninstalls in
  the Windows installation log), while the picture interface stays on the old
  driver;
- the old driver package (`ps3eyecamera.inf` from CL-Eye, a libusb-win32
  package, a WinUSB package made with Zadig, or a stale libusbK copy) stays in
  the Windows driver store even after its program is uninstalled, so Windows
  installs it again the moment the camera is plugged in;
- the libusbK wizard then does not list the camera at all, because the
  interface is already taken.

The tool reads, without changing anything:

| Area | What it reads |
| --- | --- |
| Device entries | Every entry Windows holds for `USB\VID_1415&PID_2000`, present or not: status, Device Manager error code, service, INF file, provider, version; which is the picture interface, which the microphone |
| Stored packages | Every third-party package in the driver store whose INF names the camera's hardware ID, recognised from the INF contents (service, binaries, publisher strings), never from the file name: CL-Eye (Code Laboratories), libusb-win32, Zadig WinUSB, libusbK, other |
| CL-Eye program | Whether the CL-Eye software is still installed (Uninstall keys, 64-bit and 32-bit) |
| USB path | Whether the camera sits behind an external hub, and the host controller type, as information for support |

and gives one of five verdicts: **healthy** (picture interface on libusbK,
working, nothing else stored), **ready** (picture interface with no driver,
nothing else stored), **blocked** (an old driver on the picture interface,
foreign or stale packages in the store, or leftover entries), **missing**
(Windows does not see the picture interface) or **cl-eye-installed**.

In apply mode it repairs **blocked**:

| Finding | What apply mode does |
| --- | --- |
| A stored package that names the camera and is not the libusbK package the picture interface is working on right now | `pnputil /export-driver` into the run folder, then `pnputil /delete-driver <oem.inf> /uninstall /force`, so the package is gone from the store and from the camera |
| A leftover entry for the picture interface from an earlier connection (not present) | `pnputil /remove-device <instance id>` |
| After the above | `pnputil /scan-devices`, then the state is read again and the verdict repeated |

The one package that may stay is the libusbK package the picture interface is
bound to right now, when Windows reports that binding as working. A libusbK
package that the camera is not using, or that it is using with an error code,
is treated like any other old package: exported, removed, and the interface
left ready for a clean libusbK install. With the camera not connected the
tool cannot tell a working libusbK package from a stale one, so it leaves
libusbK packages alone until the camera is back and removes only the foreign
ones.

Two situations are reported instead of repaired, because the tool must not
run anybody else's uninstaller: the CL-Eye program is still installed (the
customer uninstalls it from Windows Settings, restarts, and runs the tool
again), and the picture interface is on a driver the tool cannot trace to any
stored package.

The microphone interface `MI_01` is never touched. The tool names it on screen
so the customer stops uninstalling it. A stored package that names only `MI_01`
is logged and left alone.

## What the diagnostics pass collects

The first pass is the complete PS3 Eye Diagnostics collector (standalone
version 1.0.0) and writes the same files: Windows version and computer model,
the present camera and imaging devices, their properties and hardware IDs,
the drivers bound to them, their PnP entities and Device Manager error codes,
`pnputil /enum-devices` for every connected device, `pnputil /enum-drivers`
for every stored third-party package, the Windows device installation log
`setupapi.dev.log`, the Kernel-PnP, UserPnp and DriverFrameworks events of the
last 14 days, and `errors.txt`. The full list, file by file, is in the
[diagnostic tool's README](../ps3-eye/README.md); the `README.txt` inside
every report repeats it.

The Fix Tool adds `SUMMARY.txt` (the verdicts before and after, every device
entry with its driver, every stored package with the decision taken on it, the
CL-Eye program if installed, the USB path, the findings and what was
repaired) and `LOG.txt` (everything shown on screen plus every `pnputil`
command with its output and exit code).

## Usage

1. Keep the PS3 Eye connected, if possible straight into a USB port at the
   back of the PC, and close OpenTrack.
2. Download `PS3Eye-FixTool.zip` from the latest release and unzip it. Do not
   run the tool from inside the ZIP.
3. Run `PS3Eye-FixTool.cmd`. Read the notice and press a key. Windows then
   shows a User Account Control prompt, because driver packages can only be
   removed with administrator permission. Accept it. If it is declined, the
   tool still collects the report and checks the PC, but cannot repair
   anything.
   If Windows answers the double-click with "Smart App Control blocked a
   file that may be unsafe", close that message, right-click the file and
   choose "Run as administrator". Smart App Control blocks script files
   downloaded from the internet before they start, so nothing inside the tool
   can prevent that message; running as administrator is the documented way
   around it.
4. Step 1 of 2 collects the report (about a minute, every step shown on
   screen). Step 2 of 2 reads the driver state and then explains in plain
   words what it found and what it would remove. Nothing has been changed at
   this point.
5. To repair, press `Y`. Press `N` to leave the system as it is.
6. After the repairs the tool asks Windows to look at the camera again,
   checks everything once more and says what to do next:
   - **ready**: continue with Step 2 of the
     [PS3 Eye manual](https://delanclip.com/manuals/ps3-eye-camera-head-tracking/),
     the libusbK installer; the camera will now appear in its wizard;
   - **healthy**: start OpenTrack and pick the PS3 Eye;
   - **missing**: plug the camera into a rear USB port and run the tool
     again;
   - **cl-eye-installed**: uninstall the CL-Eye program, restart, run the
     tool again.
7. Only if the camera still does not work after the manual's steps: send the
   report ZIP named on the last screen to Delanclip Support.

Everything the tool writes lands in a `DELANCLIP` folder on the Desktop, and
that folder opens in File Explorer when the tool finishes, so the results can
be found on a cluttered Desktop.

The screen shows only plain-language results. Every technical detail
(instance IDs, INF names, each `pnputil` command and its output) goes to
`LOG.txt` in the run folder.

Switches, for Delanclip Support:

| Switch | Effect |
| --- | --- |
| `/apply` | Repair without asking `Repair now?` (the UAC prompt still appears) |
| `/undo` | Undo the most recent repair found on the Desktop, without collecting or checking first |

Running the tool a second time on a repaired system changes nothing and
reports the state as **ready** or **healthy**.

`pnputil /delete-driver`, `/export-driver` and `/add-driver` need Windows 10
version 1607 or later; `/remove-device` and `/scan-devices` need version 2004
or later. On an older Windows 10 the tool reports what it would do and asks
for the report to be sent instead; on a build between the two, it removes
packages and asks the customer to unplug and reconnect the camera in place of
the rescan.

## Undo

Before a package is removed it is exported with `pnputil /export-driver` into
`DELANCLIP\PS3Eye-FixTool-YYYYMMDD-HHMMSS\driver-backup\<oem name>\`, INF,
catalog and driver files together. The run folder also gets `UNDO.cmd`, a
script that adds those packages back with `pnputil /add-driver ... /install`,
in reverse order, and rescans.

There are two ways to undo, both one click:

- run `UNDO.cmd` in that folder as administrator (right-click, "Run as
  administrator"), or
- run the tool again: when it finds an earlier repair on the Desktop it
  offers `Press U to undo that repair` before collecting anything.

Either way the driver store is back to the packages it held before the
repair, and Windows installs them on the camera again at the next connection.
After a successful undo the folder's `UNDO.cmd` is renamed to `UNDO-done.cmd`
and an `UNDONE.txt` note is added, so the same backup is never offered twice.
A removed leftover device entry has nothing to put back; Windows recreates it
cleanly when the camera is next connected there, and `UNDO.cmd` says so.

## Privacy

The tool does not collect:

- camera pictures or sound;
- personal documents, photos, emails, passwords or browser history;
- any other unrelated personal file.

It does not install software, does not install or download any driver, makes
no network connections, sends no telemetry, uploads nothing and downloads no
code. It never runs another program's uninstaller.

The only changes it makes, and only after `Y`, are: removing stored driver
packages whose INF names the PS3 Eye (each exported to the run folder first),
removing leftover device entries for the camera's picture interface, and a
device rescan. The microphone interface is never touched.

Two of the collected files are system-wide rather than camera-specific:
`connected-devices.txt` lists every currently connected device, and
`driver-store.txt` lists every third-party driver package Windows has stored.
Both are needed because a camera problem is often caused by a driver that
belongs to something else. The report also records the Windows build, whether
the run was elevated, the local user name, the instance IDs and INF names of
the camera entries, and every `pnputil` command with its output. It stays on
the Desktop until the customer chooses to send it.

## Output

Every run creates, inside the `DELANCLIP` folder on the Desktop:

| Item | Contents |
| --- | --- |
| `PS3Eye-FixTool-YYYYMMDD-HHMMSS\` | The run folder: every diagnostic report file (`README.txt`, `windows.txt`, `camera-devices.txt`, `camera-properties.txt`, `camera-drivers.txt`, `camera-pnp-entities.txt`, `connected-devices.txt`, `driver-store.txt`, `setupapi.dev.log`, `recent-device-events.txt`, `errors.txt`), `SUMMARY.txt`, `LOG.txt`, and, once a repair was made, `driver-backup\` with the exported packages and `UNDO.cmd` |
| `SEND-TO-DELANCLIP-PS3Eye-Report-YYYYMMDD-HHMMSS.zip` | The run folder zipped: the report for Delanclip Support |

`SUMMARY.txt` starts with the verdict before and after, then lists every
device entry and every stored package with the decision taken on it.

Exit codes: 0 when the state is **ready** or **healthy** (nothing to do, or the
repairs were applied and verified); 2 when findings remain (not applied, a
manual step is needed, or still blocked after apply); 1 when the tool itself
failed.

## How it works

The `.cmd` file contains its PowerShell implementation after a marker at the
end of the same file. It first shows the notice, then relaunches itself
elevated through the standard Windows prompt, and the elevated copy reads its
own embedded PowerShell section and runs it with the 64-bit Windows
PowerShell 5.1 that ships with Windows 10 and 11. Nothing is installed or
downloaded.

Inside, the diagnostic collector runs first and writes its files into the run
folder. The detection pass then reads the device entries with `Get-PnpDevice`,
the stored packages by reading every `oem*.inf` in `C:\Windows\INF` and
looking for the camera's hardware ID in its model sections, and the Uninstall
keys for the CL-Eye program. Each finding carries its own repair action; the
check pass lists them, the apply pass runs them one by one (export, remove,
log), and a second detection pass verifies the result. The source is in this
folder in the same form it ships in, so it can be read before it is run.
