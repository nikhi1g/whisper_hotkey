# whisper_hotkey 2.6.0: Personalization

Version 2.6 makes whisper_hotkey easier to configure, understand, and
personalize while preserving its local, low-resource dictation workflow.

## Highlights

- Configure behavior and recognition faster with one-click segmented controls.
- Choose among eleven restrained HUD themes, including GitHub Dark Dimmed,
  Nord, Dracula, Solarized Dark, Rosé Pine, and High Contrast.
- Learn every gesture, completion key, HUD control, behavior, model, and menu
  action from the built-in User Guide.
- Review the current key, behavior, model, recording limit, theme, and login
  state in a compact Settings summary.
- See empty recordings dismiss twice as quickly through the one-second
  No Speech Detected status.
- Retain Press and Hold, Toggle, Pause Mode, configurable local models,
  caret-aware HUD placement, recording limits, and terminal controls.

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
