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
| Windows | [PS3 Eye Diagnostic Tool](windows/ps3-eye/) | The PS3 Eye is not detected, Windows shows only `USB Camera`, or the right driver will not install |

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

`AGENTS.md` covers how changes are made here, including the rules that keep this
repository safe to point customers at.

## License

MIT, see [LICENSE](LICENSE).
