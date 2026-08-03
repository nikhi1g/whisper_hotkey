Version 3.1.3 fixes the verified in-app update and restart flow added in 3.1.2.

Recommended for users testing the version 3.1 update path.

## Highlights

- Read the designated signing requirement from either output stream used by
  `codesign`, matching current macOS behavior.
- Keep checksum, bundle identity, version, signature, and signing identity
  verification intact.
- Show **Update failed** for an installation failure instead of the unrelated
  **Unable to check** status.
- Add an opt-in live test that downloads, verifies, mounts, stages, and removes
  the published 3.1.2 update.

This test patch uses the existing release packaging path. Public distribution
still requires Developer ID signing and notarization before general release.
