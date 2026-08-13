# Releases

Downloads are published through
[GitHub Releases](https://github.com/Delanclip/system-diagnostic/releases), not
from this folder. Nothing binary is committed here. This file records how each
asset is assembled so that a download can always be traced back to a tagged
commit.

## The asset name never changes

The Delanclip website links to the packaged tool as:

```
https://github.com/Delanclip/system-diagnostic/releases/latest/download/Delanclip-PS3Eye-Diagnostics.zip
```

That link only survives an update if the asset in every release carries exactly
that name. So the file name never gains a version number, a date or a suffix.
The version lives in the Git tag and the release title, nowhere else.

## How a release is made

Run the **Release a tool** workflow
(`.github/workflows/release.yml`) from the Actions tab, against `main`, with:

- `tool` - the folder under `windows/`, for example `ps3-eye`;
- `version` - the tag to create, for example `v1.0.0`;
- `title` - the release title, for example `Delanclip PS3 Eye Diagnostics v1.0.0`.

The workflow checks out the commit it was dispatched against, builds the asset
from that checkout, creates the tag on it, and publishes the release. Building
in the workflow rather than on somebody's laptop is what makes a release
traceable: the asset can only contain what the repository held at that commit.

It refuses to publish if the tool folder holds anything other than exactly one
`.cmd`, if `README.txt` is missing, or if either file arrives without CRLF line
endings.

The archive holds exactly two files at the top level, with no folder around
them:

- `Delanclip-PS3Eye-Diagnostics.cmd`
- `README.txt`

The asset is never committed. `.gitignore` blocks `*.zip` so that cannot happen
by accident.

## Order of operations

1. The pull request is merged into `main`.
2. The workflow is run against `main`, which creates the tag and the release
   together.

No release is published before its pull request is merged. A release that does
not correspond to a commit on `main` cannot be audited later, which defeats the
reason this repository is public.

## Building by hand

Only if the workflow is unavailable. Start from a clean checkout of the commit
being tagged, so `.gitattributes` supplies the CRLF endings:

```sh
git checkout <tag>
cd windows/ps3-eye
zip -X ../../Delanclip-PS3Eye-Diagnostics.zip \
    Delanclip-PS3Eye-Diagnostics.cmd \
    README.txt
```
