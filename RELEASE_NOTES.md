Version 3.2.3 fixes the public download, which macOS refused to open.

## Highlights

- Download `whisper_hotkey.zip`. The previous disk image was blocked
  by macOS before it could mount, with no way forward except Move to Trash.
- Approve the first launch once through **System Settings → Privacy & Security →
  Open Anyway**. The README and the product page document the step.
- Verify either asset before approving it using the published `.sha256` file.
- The release workflow builds and uploads the assets again instead of failing on
  notarization secrets that do not exist.

The app is signed with a stable Apple Development identity and is not notarized,
because notarization requires a paid Apple Developer Program membership. The
`whisper_hotkey.dmg` asset is unchanged and still serves the in-app updater.
Audio and transcripts remain local, and the bundled Base English model is still
pinned and SHA-256 verified.
