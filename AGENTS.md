# whisper_hotkey Agent Instructions

Read [`purpose.md`](purpose.md) before changing application behavior. It is the
product contract for this repository.

## Product boundaries

- `whisper_hotkey` is a native, headless macOS 14+ arm64 dictation agent.
- Right Command is a dedicated hold-to-dictate key. Press starts capture and
  model preload; release transcribes and inserts at the release-time field.
- Keep idle use minimal: no resident model/helper, polling loop, menu-bar item,
  Dock icon, transcript history, network request, or live transcript preview.
- The only persistent UI is a one-time permissions window. Runtime UI is a
  non-activating caret-attached Listening/Transcribing/Error badge.
- The running app uses installed local whisper.cpp models and never downloads a
  model or sends audio/transcripts remotely. The explicit `run.sh` bootstrap may
  download documented models only with pinned SHA-256 verification.
- Audio and transcripts are ephemeral. Logs must not contain either.

## Structure

- Swift sources live under `Sources/`, narrow tests under `Tests/`.
- `WhisperHotkeyCore` owns shared states and interfaces.
- `WhisperHotkeyASR` owns audio capture and local recognition.
- `WhisperHotkeySystem` owns global input, Accessibility, targets, and pasteboard.
- `WhisperHotkeyShell` owns setup UI, badge UI, login, and control transport.
- `WhisperHotkeyApp` owns orchestration and the app lifecycle.
- `whisper_hotkey` is the terminal controller.
- `WhisperModelHelper` is the per-dictation C++ whisper.cpp process.

Keep dependencies local and minimal. Do not introduce Hammerspoon, ffmpeg, a
cloud API, a package solely for a small utility, or a second speech engine.

## Verification

- Subagents run `swift build --target <owned-target>` plus focused tests only.
- The main agent runs the full suite, signed bundle build, installation, process
  verification, cross-app interaction checks, and resource measurements.
- Tests must cover state transitions, owned process cleanup, clipboard
  restoration, hotkey exactly-once behavior, and privacy-sensitive failure paths.
- Generated audio must use a private temporary location and be deleted on every
  exit path.

## Builds and installation

- `swift build` is the normal development compile.
- The final app bundle is built by `python3 build_app.py`.
- Bundle signing follows BookCLI's stable-identity policy: use
  `WHISPER_HOTKEY_CODESIGN_IDENTITY`, otherwise the first valid codesigning
  identity; do not silently fall back to ad-hoc signing.
- After app source changes, rebuild before handoff. For an installation handoff,
  replace `/Applications/whisper_hotkey.app`, install the controller at
  `~/bin/whisper_hotkey`, launch the installed bundle, verify its executable
  path and signature, and compare built/installed executable hashes.

## Git

- After every turn that changes files, stage and commit the relevant tracked
  changes with a concise message.
- Never commit models, recordings, transcripts, logs, build products, app
  bundles, local sockets, or credentials.
- Preserve unrelated user changes and avoid destructive Git/file operations.

Subagents in isolated worktrees must also follow [`SUBAGENTS.md`](SUBAGENTS.md).
