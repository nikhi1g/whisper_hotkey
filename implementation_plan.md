# whisper_hotkey MVP implementation plan

## Product

Build `/Applications/whisper_hotkey.app`, a headless arm64 agent, plus a
`whisper_hotkey` terminal controller. The Swift sources target macOS 14+, while
the MVP artifact is intentionally host-local to this Mac's installed
Whisper/GGML libraries.

- Default to bare Right Command, with persisted selection of either side of
  Command, Shift, Option, or Control, plus Caps Lock, Escape, and Fn/Globe.
  Selected modifiers remain ordinary shortcut modifiers. A persistent checked
  menu option switches the gesture to tap-to-start/tap-to-finish; Caps Lock is
  inherently toggle-only.
- In hold mode, use one cancellable 150 ms dwell timer and begin audio capture
  and Base English model loading only when it fires.
- Discard holds shorter than 250 ms; Escape cancels unless selected as the
  dedicated trigger; persist a 30-second-through-one-hour auto-finalize limit.
- Persist a local model selection from Base, Small, Medium, and Large-v3 Turbo
  Q5; never download missing weights. Use accuracy-first beam width five and
  half the available logical CPUs up to eight threads.
- Show a caret-attached waveform/timer while listening and textual
  Transcribing/Busy/Error states, with a
  pointer-position snapshot when exact caret geometry is unavailable, and an
  event-driven menu-bar state icon with setup, cancel, and quit controls.
- Keep one latest transcript in memory and expose **Copy Last Dictation** as a
  permanent ordinary clipboard copy.
- Keep no model, helper, transcript history, Dock item, or polling worker alive
  while idle.
- Register a signed, one-shot native LaunchAgent after one-time permission
  setup. It opens the app at login and exits, leaving no second resident worker.

[`purpose.md`](purpose.md) is authoritative for detailed behavior.

## Architecture

1. `WhisperHotkeyApp` coordinates the state machine.
2. `WhisperHotkeyASR` records private 16 kHz mono audio and owns a
   per-dictation whisper.cpp helper. The selected helper preloads on press, transcribes
   once on release, and exits. Stock `whisper-cli` provides the Metal then
   Metal-specific CPU fallback.
3. `WhisperHotkeySystem` owns the configurable bare-key event tap, exact
   Accessibility caret geometry, bounded one-character context spacing,
   unconditional temporary paste, and permanent explicit copy. It has no
   target validation or one-paste lease.
4. `WhisperHotkeyShell` owns the caret-preferred, pointer-fallback badge,
   persistent mode checkmark, menu-bar state UI, first-run permission UI,
   one-shot login launcher registration, and private local control socket.
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
  helper/CLI recognition fallback, every selectable hotkey, bare-key/chord
  disambiguation, spacing, temporary clipboard restoration, permanent
  last-dictation copy, caret-preferred pointer fallback, control socket, and
  Login Item policy.
- The release build must pass strict deep code-signature verification and the
  installed main executable and controller must hash-match their built copies.
- Installed verification must cover setup readiness, Login Item registration,
  terminal status/stop/start/restart, absence of an idle Whisper helper, and
  idle CPU/RAM sampling.
- Final application insertion remains a manual acceptance check because it
  requires real microphone input and a physical selected-key gesture in each
  destination class.
