# whisper_hotkey MVP implementation plan

## Product

Build `/Applications/whisper_hotkey.app`, a headless macOS 14+ arm64 agent,
plus a `whisper_hotkey` terminal controller.

- Hold dedicated Right Command to listen; release to transcribe and insert.
- Begin audio capture and Base English model loading together on key-down.
- Discard holds shorter than 250 ms; Escape cancels; ten minutes auto-finalizes.
- Show only a caret-attached Listening/Transcribing/Busy/Error badge.
- Keep no model, helper, transcript history, menu item, Dock item, or polling
  worker alive while idle.
- Register as a native Login Item after one-time permission setup.

[`purpose.md`](purpose.md) is authoritative for detailed behavior.

## Architecture

1. `WhisperHotkeyApp` coordinates the state machine.
2. `WhisperHotkeyASR` records private 16 kHz mono audio and owns a
   per-dictation whisper.cpp helper. The helper preloads on press, transcribes
   once on release, and exits. Stock `whisper-cli` provides the Metal then
   Metal-specific CPU fallback.
3. `WhisperHotkeySystem` owns the Right Command event tap, release-time
   Accessibility target, caret geometry, context spacing, temporary paste, and
   one-paste clipboard leases.
4. `WhisperHotkeyShell` owns the badge, first-run permission UI, Login Item,
   and private local control socket.
5. `whisper_hotkey` exposes start, stop, restart, status, cancel, setup,
   enable-login, disable-login, and logs.

## Delivery

- Main agent establishes contracts and integration.
- `asr_core`, `system_bridge`, and `service_shell` subagents implement
  non-overlapping modules in isolated worktrees.
- Each subagent compiles and runs focused tests. The main agent runs the full
  Swift suite, builds/signs/installs the app, and verifies native, browser,
  Electron, and terminal insertion plus idle resource use.
- Final signing follows BookCLI's stable-identity requirement and refuses an
  ad-hoc final app.
