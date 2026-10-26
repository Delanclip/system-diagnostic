# Delanclip system-diagnostic

Public diagnostic tools that Delanclip Support asks customers to run when a head
tracking setup will not work and screenshots cannot explain why.

A screenshot of Device Manager shows a device name and an icon. It does not show
which driver Windows actually loaded, which INF file that driver came from, what
error code the device is reporting, or what the installer logged when it tried.
The tools here read that information from the machine itself, write it to a ZIP
file on the Desktop, and stop. The customer sends that ZIP to Delanclip Support,
who read it and reply with a fix instead of another round of questions.

## Available tools

| Platform | Tool | Use it when |
| --- | --- | --- |
| Windows | [PS3 Eye Fix Tool](windows/ps3-eye-fixtool/) | The PS3 Eye will not take the libusbK driver from the Delanclip manual, or keeps going back to an old one. One run collects the full diagnostic report, backs up and removes the stored driver packages Windows keeps putting back on the camera (only after the customer confirms), and leaves the camera ready for the manual's libusbK step. It never touches the camera's microphone interface |
| Windows | [PS3 Eye Diagnostic Tool](windows/ps3-eye/) | Finished project, no longer developed: the report-only collector that the PS3 Eye Fix Tool now contains. Kept so published download links keep working |
| Windows | [DelanCam1 Fix Tool](windows/delancam1-fixtool/) | Anything wrong with DelanCam1: not detected, a Device Manager error, a corrupted or missing picture, or OpenTrack and AITrack unable to open it. One run collects the full diagnostic report, repairs the known Windows video-pipeline damage after a backup and only when the customer confirms, and zips the report for support |
| Windows | [DelanCam1 Diagnostic Tool](windows/delancam1/) | Finished project, no longer developed: the report-only collector that the Fix Tool now contains. Kept so published download links keep working |

Linux and macOS tools will live in `linux/` and `macos/` folders beside
`windows/`. Nothing has been published for them yet.

## What these tools do not do

Every tool in this repository runs entirely on the machine it is started on:

- it does not upload anything, anywhere;
- it does not send telemetry;
- it does not make network requests of any kind;
- it does not download or execute any further code;
- it does not read personal documents, photos, emails, passwords or browser
  history.

The ZIP a tool produces stays on the Desktop until the customer chooses to
attach it to a reply to Delanclip Support. Nothing leaves the machine on its
own.

The diagnostic tools change nothing on the machine. The two Fix Tools do, and
only in one bounded way each: the DelanCam1 Fix Tool repairs known registry
damage, and the PS3 Eye Fix Tool removes stored driver packages and leftover
device entries for the PS3 Eye. Both show every change first, make it only
after the customer confirms, export a backup and write an undo script before
touching anything, and never delete a personal file. Without the customer's
confirmation, or without administrator permission, they only collect and
report, exactly like the diagnostic tools.

## Read it before you run it

Being wary of a script somebody sent you is the correct instinct. The source of
every tool is in this repository in the same form it ships in, so it can be read
first. Each tool's own README lists exactly what that tool collects, file by
file, and that list is meant to be checked against the source rather than taken
on trust.

## Downloads

Ready-to-run packages are published under
[Releases](https://github.com/Delanclip/system-diagnostic/releases). Every
release asset keeps the same file name across versions, so a download link
published on a support page or in an email stays valid after an update.

## Contributing

Changes go through a pull request. A tool is only accepted with a complete and
accurate list of what it collects, checkable against its source, and with the
guarantees above intact.

## License

MIT, see [LICENSE](LICENSE).
