Version 3.4.2 is release plumbing. Nothing about how the app behaves changed
from 3.4.1 — if you are already on 3.4.1, there is no reason to update.

## What it fixes

Bundling the Parakeet checkpoints in 3.4.1 broke the signed-release workflow in
a way that was hidden behind an unrelated failure. `build_app.py` copies the
checkpoints out of FluidAudio's cache, and a clean CI runner has no cache, so
the build would have failed even once the signing secrets were in place.

- The benchmark harness grew a `download` subcommand, so the workflow can
  populate that cache before building. It already links FluidAudio, so this
  needed no new package and no hand-rolled fetch against a file layout
  FluidAudio owns. Verified against both a warm cache, where it is a no-op, and
  a genuinely empty one.
- The workflow was still downloading `ggml-small.en.bin`, retired in 3.4.1. Its
  download list now matches `build_app.py` exactly, so the two cannot drift
  again the next time the lineup changes.
- `build_app.py` no longer copies the Parakeet checkpoints from inside the
  function that copies the digest-verified Whisper models. Each does one job,
  and the Parakeet copy honors the same opt-in flag, so an ordinary development
  build does not need the checkpoints present.

## Unchanged

The recognition presets, the bundled model lineup, and the app binary behave
exactly as in 3.4.1: Fast and Accurate, both running Parakeet on the Neural
Engine, with both checkpoints shipped inside the app.

The app is signed with a stable Apple Development identity and is not
notarized, so the first launch still needs one approval through System
Settings > Privacy & Security > Open Anyway. Audio and transcripts remain
local, and every bundled Whisper model is verified against a pinned SHA-256.
