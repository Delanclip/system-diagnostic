# Releases

Downloads are published through
[GitHub Releases](https://github.com/Delanclip/system-diagnostic/releases), not
from this folder. Nothing binary is committed here. This file records how the
assets are assembled so that a download can always be traced back to a tagged
commit.

## The asset name never changes

The Delanclip website and support emails link to a packaged tool as:

```
https://github.com/Delanclip/system-diagnostic/releases/latest/download/Delanclip-PS3Eye-Diagnostics.zip
```

That link only survives an update if the asset in every release carries exactly
that name. So a file name never gains a version number, a date or a suffix.
The version lives in the Git tag and the release title, nowhere else. Every
release contains the assets of **all** tools, so a link to a tool that did not
change keeps working after another tool is updated.

The asset name is the name of the tool's `.cmd` file with `.zip` in place of
`.cmd`: `Delanclip-PS3Eye-Diagnostics.zip`, `DelanCam1-Diagnostics.zip` and
`DelanCam1-FixTool.zip`.

## How a release is made

The **Release diagnostic tools** workflow
(`.github/workflows/release.yml`) starts in one of two ways:

- by hand from the Actions tab, against `main`, with `version` (the tag to
  create, for example `v1.0.0`) and `title` (the release title, for example
  `Delanclip Diagnostic Tools`; the version is appended automatically);
- automatically on a push to `main` that changes
  `.github/release-request.txt`, which carries the same two values as
  `version=` and `title=` lines plus a `request_id=` line that makes each
  request distinct.

The workflow checks out the commit it runs against, builds one asset per
folder under `windows/` from that checkout, creates the tag on it, and
publishes the release with all the assets. Building in the workflow rather than
on somebody's laptop is what makes a release traceable: an asset can only
contain what the repository held at that commit.

It refuses to publish if any tool folder holds anything other than exactly one
`.cmd`, if its `README.txt` is missing, or if either file arrives without CRLF
line endings.

Each archive holds exactly two files at the top level, with no folder around
them: the tool's `.cmd` and its `README.txt`.

Assets are never committed. `.gitignore` blocks `*.zip` so that cannot happen
by accident.

## Order of operations

1. The pull request is merged into `main`.
2. The workflow runs against `main`, by hand or through the merged change to
   `release-request.txt`, and creates the tag and the release together.

No release is published before its pull request is merged. A release that does
not correspond to a commit on `main` cannot be audited later, which defeats the
reason this repository is public.

## Building by hand

Only if the workflow is unavailable. Start from a clean checkout of the commit
being tagged, so `.gitattributes` supplies the CRLF endings, and repeat for
every tool folder:

```sh
git checkout <tag>
cd windows/ps3-eye
zip -X ../../Delanclip-PS3Eye-Diagnostics.zip \
    Delanclip-PS3Eye-Diagnostics.cmd \
    README.txt
```
