Version 3.1.0 adds an explicit privacy control for Copy Last Dictation and
promotes the downloadable Mac app to the stable release path.

Recommended for all users of version 3.0.

## Highlights

- Add **Keep latest transcript until quit** to Settings. It defaults on for the
  existing Copy Last Dictation behavior.
- Turning the setting off immediately clears the retained transcript, hides the
  menu action, and prevents later transcripts from being retained.
- Keep Pause Mode context separate so disabling Copy Last Dictation does not
  reduce pause-aware punctuation or casing within an active session.
- Retain a transcript only after successful insertion.
- Publish a Developer ID-signed, Apple-notarized `whisper_hotkey.dmg` with the
  pinned Base English model through the stable GitHub release path.
- Refine the product-page demo with direct mode chips, a modern key picker, and
  a continuous perimeter activity trail.

Fastest install:

1. Download `whisper_hotkey.dmg` from this release.
2. Drag the app to Applications and open it.
3. Complete the three macOS permissions shown by Setup.

The DMG supports Apple Silicon Macs running macOS 14 or newer. Recognition and
the optional latest-transcript fallback remain local and in memory only.
