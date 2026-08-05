Version 3.2.4 fixes dictation being polluted by the internal dictionary, and
makes the download install and configure itself properly.

## Highlights

- Stop internal dictionary entries appearing in transcripts. A pause with no
  speech could be decoded as a confident "continuation" of the vocabulary hint,
  splicing entries such as `Codex.md` into the middle of dictation. The hint is
  now withheld from clips with no audible signal.
- Offer to move the app into Applications on first launch, so a download opened
  from the Downloads folder stops running as a read-only quarantined copy that
  cannot update itself.
- Open Settings once on a new installation.
- Include Base English, Small English, and Large-v3 Turbo Q5 in the download,
  which is every model the first run can select on its own. The download grows
  to about 1 GB.
- Download Medium English on demand, with progress and checksum verification,
  instead of silently ignoring the selection. It is the one model too large to
  bundle.
- Show progress while an update downloads, verifies, and installs.

The app is signed with a stable Apple Development identity and is not
notarized, so the first launch still needs one approval through System
Settings > Privacy & Security > Open Anyway. Audio and transcripts remain
local, and every bundled and downloaded model is verified against a pinned
SHA-256.
