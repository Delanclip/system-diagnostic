Delanclip PS3 Eye Diagnostics
=============================

What this is
------------
A tool that collects the Windows device and driver information Delanclip
Support needs to work out why a PS3 Eye camera is not working. It saves that
information to a ZIP file on your Desktop. It does nothing else with it.

How to run it
-------------
1. Keep the PS3 Eye connected.
2. Run Delanclip-PS3Eye-Diagnostics.cmd from this folder.
   Do not run it from inside the ZIP you downloaded.
3. It tells you what it is about to do and waits for a key press. A paused
   window is normal, not a freeze.
4. When it finishes it saves the report on your Desktop and opens Explorer
   with the file selected. The name looks like:
   Delanclip-PS3Eye-Diagnostics-20260813-125225.zip
5. Reply to Delanclip Support and attach that file.

Administrator rights are not needed. The tool runs without them and notes any
step it could not complete. If we ask for a fuller report, right-click the
file and choose "Run as administrator".

Privacy
-------
This tool does NOT collect:
  - personal documents
  - browser history
  - passwords
  - emails
  - photos
  - any other unrelated personal file

It makes no network connections. It sends nothing anywhere. It downloads
nothing and runs no code other than what is inside the file itself. The report
stays on your Desktop until you decide to send it.

What it collects
----------------
Your Windows version and build, the make and model of the computer, the camera
and imaging devices Windows can see, their properties and hardware IDs, the
drivers bound to them, the Device Manager error codes, the list of connected
devices and stored driver packages, the Windows device installation log, and
device-related system events from the last 14 days.

The full list, file by file, is published with the source at:
https://github.com/Delanclip/system-diagnostic/tree/main/windows/ps3-eye

Source
------
The complete source of this tool is public and can be read before you run it:
https://github.com/Delanclip/system-diagnostic

Support
-------
https://delanclip.com/contact/
