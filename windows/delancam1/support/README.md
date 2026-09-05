# DelanCam1 support-side scripts

These scripts are for Delanclip Support to run on a customer's Windows PC
during an agreed remote-support session. They are not part of the customer
diagnostic ZIP published in Releases and they are not something we ask
customers to run on their own.

Both scripts are plain PowerShell 5.1, make no network connections, install
nothing and change nothing. They only read system state and, for the frame
probe, briefly open DelanCam1 to count frames. No image data is ever kept.

## `StreamProbe.ps1`

Opens DelanCam1 through the Windows Runtime camera API once per format and
prints how many frames arrive for each (MJPG, NV12 and YUY2 at 640x480 and
1280x720, plus the device default). It answers one question quickly: does the
camera stream at all through Media Foundation, and does it fail only in some
formats (typically MJPEG, when a third-party decoder intercepts it).

Console output only.

## `DelanCam1-DeepCollect.ps1`

Collects the full camera-pipeline state that decides whether OpenTrack can
open DelanCam1 and writes an auto-flagged summary first:

- system: OS, BIOS, board, GPU driver, uptime, Fast Startup, pending reboot;
- camera device: driver stack, device and class filter drivers, USB path;
- Media Foundation: hardware MFT switch, Frame Server, every registered
  transform with signer, and the per-format frame probe;
- DirectShow: core component registrations, virtual-camera entries,
  third-party or dead filters, Preferred and DoNotUse keys, VFW codecs,
  per-user device cache;
- camera privacy consent for the machine and each user, per app, including
  which app currently holds the camera; related policies;
- installed programs, running processes, non-Microsoft services and startup
  entries, with camera/codec/tracking/tweak-tool highlights;
- OpenTrack installations (architecture, OpenCV build), configuration
  folders and the PointTracker camera settings; copies of the `.ini` files;
- recent System and Application events about USB, PnP, crashes and camera apps;
- security products and Defender state;
- `setupapi.dev.log` history for DelanCam1.

Output is a folder plus ZIP under `C:\temp` (override with `-OutRoot`).
`-SkipProbe` skips the camera-opening step.

Both scripts are downloaded straight from this repository during the session,
for example with `curl -L -o C:\temp\<name>.ps1 <raw URL>` and run with
`powershell -NoProfile -ExecutionPolicy Bypass -File C:\temp\<name>.ps1`.
