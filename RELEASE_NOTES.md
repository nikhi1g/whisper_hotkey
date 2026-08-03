Version 3.0.8 adds a conventional, self-contained Mac download while preserving
the source bootstrap and the app's private, on-demand runtime.

Recommended for all users of version 3.0.

## Highlights

- Publish a Developer ID-signed, Apple-notarized `whisper_hotkey.dmg` through
  GitHub Releases.
- Include the pinned, SHA-256-verified Base English model in the release app so
  the DMG needs no follow-up model download or build toolchain.
- Add the product page at `nikhi1g.github.io/whisper_hotkey/` with direct DMG
  and source links.
- Keep the existing `git clone` → `./run.sh` path for source installations,
  including its human-in-the-loop setup verification.
- Keep model loading, microphone use, and recognition on demand and entirely
  local after installation.

Fastest install:

1. Download `whisper_hotkey.dmg` from this release.
2. Drag the app to Applications and open it.
3. Complete the three macOS permissions shown by Setup.

Source install:

```sh
git clone https://github.com/nikhi1g/whisper_hotkey.git
cd whisper_hotkey
./run.sh
```

The DMG supports Apple Silicon Macs running macOS 14 or newer. Its release
workflow refuses to publish unless the app is Developer ID signed, notarization
is accepted and stapled, Gatekeeper assessment succeeds, and the included Base
English model matches the pinned digest. Source archives and checksums remain
attached for independent inspection.
