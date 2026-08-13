# Working in this repository

This is a public repository. Everything committed here is readable by customers,
competitors and search engines, and the whole point of it being public is that a
customer can read a tool before running it. Treat every change as something a
stranger will read with suspicion.

Read this file before changing anything.

## What belongs here

Diagnostic tools, their documentation, and the sources a release asset is built
from. Nothing else.

Never commit:

- customer data, support tickets, email addresses or names;
- diagnostic reports produced by running a tool, from any machine;
- credentials, tokens, API keys or licence keys;
- internal notes, pricing, supplier details or anything about work in progress;
- release ZIPs or other build outputs.

## How changes are made

- Work on a branch named `agent/<description>`.
- Open a draft pull request into `main`.
- Never commit to `main` directly.
- A pull request is a review checkpoint, not permission to publish a release.

## What every tool must have

A tool is not finished until all of these exist:

1. Its own folder under the platform it runs on: `windows/`, `linux/` or
   `macos/`. One folder per tool.
2. A `README.md` in that folder with four sections: **Purpose**, **Usage**,
   **Privacy** and **Output**.
3. A complete list of what the tool collects, item by item, in that README. The
   list has to match the source. If a change makes the tool collect something
   new, the list changes in the same commit.
4. A privacy section stating plainly what the tool does **not** collect.

The collection list is the promise the repository makes. A tool that collects
more than its README admits to is a defect, and a serious one, whatever else it
does correctly.

## What a tool may never do

These are not style preferences. A tool that breaks any of them does not go in.

- No network requests, of any kind, for any reason.
- No telemetry.
- No uploading the report, or any part of it, anywhere.
- No downloading further scripts, payloads or dependencies at runtime.
- No executing code fetched from the internet.

A tool runs locally, writes its report locally, and stops. The customer decides
whether to send it and to whom.

## Releases

- Release assets are built from the sources in this repository, at the commit
  being tagged. Never from a file somebody had lying around.
- Release assets are not committed to the repository. `.gitignore` blocks `*.zip`
  to keep that accidental.
- An asset file name never carries a version number. The version lives in the
  Git tag and the release title. A fixed asset name is what keeps
  `releases/latest/download/<asset>` working as a permanent link from the
  Delanclip website.
- No release is published before its pull request is merged.

`releases/README.md` records how each asset is assembled.

## Line endings

Windows scripts are downloaded rather than cloned by the people who run them,
and `cmd.exe` is unforgiving about line endings. `.gitattributes` forces CRLF on
`.cmd`, `.bat`, `.ps1` and `.txt`. Do not remove it and do not commit a Windows
script normalised to LF.

## Wider Delanclip rules

Delanclip's approved company facts, product truth and writing standards live in
[`Delanclip/delanclip-knowledge-base`](https://github.com/Delanclip/delanclip-knowledge-base).
Where that repository and this file disagree, the knowledge base decides. Do not
copy its rules here; a second copy drifts.

Customer-facing text in this repository is written in English (en-GB). Pull
request titles and descriptions are written in Polish, because they are an
internal conversation.
