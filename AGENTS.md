# whisper_hotkey Agent Instructions

Read [`purpose.md`](purpose.md) before changing application behavior. It is the
product contract for this repository.

## Session context

The `post_processing` branch carries active voice-to-prompt development. Read
[`2026-08-17-post-processing-branch-commit-log.md`](2026-08-17-post-processing-branch-commit-log.md)
for the session commit log, keychain contract, known bug fixes, and handoff
pointers before working on or near that branch.

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

## Releases

Read [`docs/DISTRIBUTION.md`](docs/DISTRIBUTION.md) before publishing anything.
Three points are settled policy and must not be re-litigated:

- **Releases are never notarized.** There is no paid Apple Developer Program
  membership. Every release is signed with the project's stable **Apple
  Development** identity. `spctl --assess` reporting `rejected` is the expected
  state, not a regression. Never describe a release as notarized.
- **The ZIP is the human download; the DMG exists only for the in-app updater.**
  macOS 15+ blocks an unnotarized disk image *before it mounts*, which leaves a
  user at a "Move to Trash" dead end with no Open Anyway. This is a deliberate
  workaround, accepted by the project owner, and stands until the $99
  membership is purchased.
- **The GitHub release workflow is expected to fail on tag push, and that is
  fine.** It has no `APPLE_SIGNING_CERTIFICATE_P12_*` secrets, so it exits in
  ~15s at its "Validate release ref and secrets" step, before touching the
  release. Locally-built assets are never at risk. **Do not "fix" this, and do
  not raise it as a problem** unless the owner asks or buys the membership.

Releases are therefore built and uploaded locally:

```sh
WHISPER_HOTKEY_BUNDLE_MODEL=1 WHISPER_HOTKEY_DISTRIBUTION=1 \
  WHISPER_HOTKEY_UNNOTARIZED=1 python3 build_app.py
python3 tools/package_zip.py
python3 tools/package_dmg.py --unnotarized
python3 tools/package_release.py "v$(cat VERSION)"
gh release create "v$(cat VERSION)" --notes-file RELEASE_NOTES.md --verify-tag
gh release upload "v$(cat VERSION)" --clobber dist/release/*
```

`build_app.py` will refuse Homebrew's `whisper-cpp`: it targets the host macOS
and trips the macOS 14 deployment-target guardrail, which exists so the release
runs on macOS 14 and later. Build the pinned library first and point
`WHISPER_CPP_PREFIX` and `GGML_PREFIX` at its install prefix — whisper.cpp
`v1.9.1`, commit `f049fff95a089aa9969deb009cdd4892b3e74916`, configured with
`-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 -DCMAKE_OSX_ARCHITECTURES=arm64
-DGGML_METAL=ON -DGGML_OPENMP=OFF -DBUILD_SHARED_LIBS=ON`. This mirrors
`.github/workflows/release.yml`, which is the reference for the exact flags.

Never publish an ad-hoc build. Ad-hoc changes the designated requirement on
every build, which breaks in-app updates and drops the Microphone,
Accessibility and Input Monitoring grants.

## Git

- After every turn that changes files, stage and commit the relevant tracked
  changes with a concise message.
- Never commit models, recordings, transcripts, logs, build products, app
  bundles, local sockets, or credentials.
- Preserve unrelated user changes and avoid destructive Git/file operations.

Subagents in isolated worktrees must also follow [`SUBAGENTS.md`](SUBAGENTS.md).
