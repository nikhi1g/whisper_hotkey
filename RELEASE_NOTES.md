# whisper_hotkey 2.0.0

Version 2.0 makes the private, low-resource, system-wide dictation agent
substantially more reliable and easier to control across Apple Silicon Macs.

## Highlights

- Choose **Press and Hold** or **Toggle** dictation behavior.
- Configure the hotkey, model, recording limit, worker threads, and login
  behavior in a focused Advanced Settings window.
- Follow a compact, fixed-size recording HUD at the initial caret location, or
  at the pointer when an exact caret is unavailable.
- Stop and insert from the HUD, or insert and send with a plain Return that
  cannot inherit the dictation modifier.
- See a low-cost live waveform and elapsed timer. During the final minute, the
  timer becomes an orange-to-red remaining-time warning.
- Avoid Whisper hallucinations from empty recordings through a lightweight
  voice-activity gate.
- Recover the recording HUD across repeated sessions, applications, Spaces, and
  full-screen windows without restarting the app.
- Restart the background app directly from its menu.

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
