# whisper_hotkey 2.5.0: Live Flow

Version 2.5 makes private, low-resource, system-wide dictation feel continuous:
Pause Mode inserts speech after natural pauses, while the compact HUD follows
the focused text control until the user chooses a position.

## Highlights

- Use **Pause Mode** for ordered, phrase-by-phrase live insertion from one
  uninterrupted private recording and one session-scoped model helper.
- Start inserting after a responsive 450 ms pause target that adapts between
  300 and 750 ms to the current speaking cadence.
- Preserve continuation punctuation and casing with a private, bounded
  prior-phrase prompt.
- Let the fixed-size HUD follow newly focused text controls during dictation
  through event-driven Accessibility notifications with no polling or idle cost.
- Drag the HUD to lock its position for the current dictation; the next session
  returns to automatic placement.
- Keep compact composers unobscured while rejecting oversized terminal
  containers in favor of the active caret.
- Stop and insert with the HUD or dictation key, submit with Return or Send, and
  discard the complete active dictation with Escape.
- Retain the low-cost waveform, silence gate, configurable local models,
  recording limits, login item, and terminal controls from version 2.0.

Clone the repository and run:

```sh
./run.sh
```

The bootstrap installs/checks Homebrew whisper.cpp, downloads the verified Base
English model, builds and signs the app locally, installs it in `/Applications`,
launches it, and opens the macOS permission setup.

See the README for prerequisites, permissions, gesture and hotkey configuration,
model choices, terminal control, and local-signing details.

This release is distributed as source because the project does not currently
ship a notarized Developer ID binary. Models are not included in the archive.
