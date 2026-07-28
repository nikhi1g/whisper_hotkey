# whisper_hotkey MVP implementation plan

## Product

Build `/Applications/whisper_hotkey.app`, a headless arm64 agent, plus a
`whisper_hotkey` terminal controller. The Swift sources target macOS 14+, while
the MVP artifact is intentionally host-local to this Mac's installed
Whisper/GGML libraries.

- Hold dedicated Right Command to listen; release to transcribe and insert.
- Begin audio capture and Base English model loading together on key-down.
- Discard holds shorter than 250 ms; Escape cancels; ten minutes auto-finalizes.
- Show a caret-attached Listening/Transcribing/Busy/Error badge and an
  event-driven menu-bar state icon with setup, cancel, and quit controls.
- Keep no model, helper, transcript history, Dock item, or polling worker alive
  while idle.
- Register a signed, one-shot native LaunchAgent after one-time permission
  setup. It opens the app at login and exits, leaving no second resident worker.

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
4. `WhisperHotkeyShell` owns the badge, menu-bar state UI, first-run permission
   UI, one-shot login launcher registration, and private local control socket.
5. `whisper_hotkey` exposes start, stop, restart, status, cancel, setup,
   enable-login, disable-login, and logs.

## Delivery

- Main agent establishes contracts and integration.
- `asr_core`, `system_bridge`, and `service_shell` subagents implement
  non-overlapping modules in isolated worktrees.
- Each subagent compiles and runs focused tests. The main agent runs the full
  Swift suite, builds/signs/installs the app, verifies lifecycle and idle
  resource use, and coordinates the physical-hotkey insertion acceptance check.
- Final signing follows BookCLI's stable-identity requirement, signs nested
  helpers before the outer bundle, and refuses an ad-hoc final app.

## Acceptance

- Automated Swift tests cover the lifecycle reducer, capture cleanup,
  helper/CLI recognition fallback, physical hotkey suppression, target
  validation, spacing, clipboard restoration, badge placement, control socket,
  and Login Item policy.
- The release build must pass strict deep code-signature verification and the
  installed main executable and controller must hash-match their built copies.
- Installed verification must cover setup readiness, Login Item registration,
  terminal status/stop/start/restart, absence of an idle Whisper helper, and
  idle CPU/RAM sampling.
- Final application insertion remains a manual acceptance check because it
  requires real microphone input and a physical Right Command hold in each
  destination class.
