Version 3.5.5 makes the Settings window readable. Nothing is removed — every
engine, model, profile and mode stays reachable.

## What changed

The window had grown to fifteen rows, and two of them were both labelled
`Fast | Accurate` while meaning different things. The Engine row offered
"Metal", "Core ML Encoder" and "WhisperKit", words that say nothing about what
you get. A row called Recognition sat inside a section called RECOGNITION. Six
chips along the bottom repeated values already visible above them.

- **Engine and Model are now one list** of ten named configurations, grouped by
  family, with the ones that need no download first. The old matrix had cells
  that could not run; the matrix is gone.
- **Custom is a real segment.** Previously, a configuration matching neither
  preset left the control with nothing highlighted, which reads as broken.
- **Quality**, not Recognition.
- **The footer chips are gone.**
- **One control for keeping the last dictation**, not a label and a checkbox
  saying the same thing.

Collapsed, the Recognition section is two rows instead of four.

## Processing now defaults to Model Ready

In both presets and on first run. It decodes the whole recording, so it is as
accurate as After Recording, and the model is already resident so the load
latency is gone. Decode While Speaking trades accuracy for perceived speed,
which is the wrong default for someone who has not chosen it deliberately. All
three modes remain selectable under Advanced Options.

## Still to come

The guided first-run window — permissions, key, and a live "try it" that proves
dictation works — is designed and written up in `docs/design/welcome-window.md`,
but not built. It is the larger half of making this approachable for someone
non-technical.

The app is signed with a stable Apple Development identity and is not
notarized, so the first launch still needs one approval through System
Settings > Privacy & Security > Open Anyway. Audio and transcripts remain
local, and every bundled Whisper model is verified against a pinned SHA-256.
