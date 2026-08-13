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

## Building the Windows PS3 Eye asset

Run from a clean checkout of the commit being tagged, so that what ships is what
the repository holds:

```sh
git checkout <tag>
cd windows/ps3-eye
zip -X ../../Delanclip-PS3Eye-Diagnostics.zip \
    Delanclip-PS3Eye-Diagnostics.cmd \
    README.txt
```

The archive holds exactly two files, both at the top level, with no folder
around them:

- `Delanclip-PS3Eye-Diagnostics.cmd`
- `README.txt`

Both must be CRLF. `.gitattributes` guarantees that on checkout; a build done
outside a proper checkout does not get that guarantee, which is why the
instruction above starts with `git checkout`.

The resulting ZIP is uploaded as the release asset and is not committed.
`.gitignore` blocks `*.zip` so that cannot happen by accident.

## Order of operations

1. The pull request is merged into `main`.
2. The tag is created on the merge commit.
3. The asset is built from that tag.
4. The release is published with the asset attached.

No release is published before its pull request is merged. A release that does
not correspond to a tagged commit on `main` cannot be audited later, which
defeats the reason this repository is public.
