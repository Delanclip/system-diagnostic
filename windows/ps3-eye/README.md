# PS3 Eye Diagnostic Tool (Windows)

`Delanclip-PS3Eye-Diagnostics.cmd` collects the Windows device and driver
information that Delanclip Support needs in order to say why a PS3 Eye camera
is not working. It writes that information to a ZIP file on the Desktop and
does nothing else with it.

Download the packaged version from
[Releases](https://github.com/Delanclip/system-diagnostic/releases/latest).
The source in this folder is the same file that ships inside it.

## Purpose

Support asks for this when a case has stopped being answerable from
screenshots:

- the PS3 Eye is not detected at all;
- Windows shows only `USB Camera` and nothing else;
- Windows has loaded a driver, but the wrong one;
- reinstalling the driver repeatedly changes nothing;
- OpenTrack cannot open the camera.

A Device Manager screenshot shows a name and an icon. It does not show the
driver version, the provider, the INF file behind it, the device error code, or
what the installer logged while trying. Those four or five facts usually decide
the answer, and all of them are in the report this tool produces.

## Usage

1. Keep the PS3 Eye connected while the tool runs.
2. Download `Delanclip-PS3Eye-Diagnostics.zip` from the latest release and
   unzip it. Do not run the tool from inside the ZIP.
3. Run `Delanclip-PS3Eye-Diagnostics.cmd`. It explains what it is about to do
   and waits for a key press before it starts, so a paused window is normal and
   not a freeze.
4. Wait for it to finish. It saves the report on the Desktop and opens Explorer
   with that file selected.
5. Reply to Delanclip Support and attach the report.

Administrator rights are not required. The tool runs without them and records
which steps it could not complete. If the report comes back with gaps, running
it again with **Run as administrator** usually fills them in.

Windows may warn before running a script downloaded from the internet. That is
the operating system doing its job with any `.cmd` file, and the reason this
one's source is published here to be read first.

The tool also runs with the camera unplugged or absent. It then records that no
matching device was found, which is itself a useful answer.

## Privacy

The tool does not collect:

- personal documents;
- browser history;
- passwords;
- emails;
- photos;
- any other unrelated personal file.

It makes no network connections, sends nothing anywhere, downloads nothing, and
runs no code other than what is inside the file itself. The report stays on the
Desktop until the customer chooses to attach it to an email.

Two of the collected files are system-wide rather than camera-specific:
`connected-devices.txt` lists every currently connected device, and
`driver-store.txt` lists the third-party driver packages Windows has stored.
Both are needed because a camera problem is often caused by a driver that
belongs to something else, and both are named openly here rather than described
as camera data.

## Output

The report is saved to the Desktop as
`Delanclip-PS3Eye-Diagnostics-YYYYMMDD-HHMMSS.zip`, for example
`Delanclip-PS3Eye-Diagnostics-20260813-125225.zip`.

It contains:

| File | Contents |
| --- | --- |
| `README.txt` | What the run collected, when it ran, and whether it had administrator rights |
| `windows.txt` | Windows edition, version, build, architecture, last boot time, and the computer's manufacturer and model |
| `camera-devices.txt` | Present devices of class Camera or Image, plus anything named `PS3`, `Eye` or `USB Camera`: status, class, friendly name, instance ID |
| `camera-properties.txt` | Every PnP property of those devices, including hardware IDs |
| `camera-drivers.txt` | The driver bound to each of those devices: provider, version, date, INF file, signature status and signer |
| `camera-pnp-entities.txt` | The same devices seen as PnP entities, including the service behind them and the Device Manager error code |
| `connected-devices.txt` | `pnputil /enum-devices /connected /deviceids /drivers` for every connected device |
| `driver-store.txt` | `pnputil /enum-drivers`, the third-party driver packages held in the Driver Store |
| `setupapi.dev.log` | The Windows device installation log, which records what happened during past driver installs |
| `recent-device-events.txt` | System log entries from Kernel-PnP, UserPnp and DriverFrameworks over the last 14 days |
| `errors.txt` | Any collection step that failed, and why. It says so explicitly when nothing failed |

Each step catches its own failure, so a step that cannot run costs one file's
worth of detail rather than the whole report.

## How it works

The `.cmd` file carries its PowerShell body after a marker at the end of the
file, reads itself to find it, and runs that block. That is why it is a single
file with nothing to install, and why the whole of what it does can be read in
one place. It reads only its own path, never a remote one.
