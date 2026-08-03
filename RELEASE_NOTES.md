Version 3.1.2 turns stable-release detection into a verified in-app update and
restart flow.

Recommended for users testing the version 3.1 update path.

## Highlights

- Change **Check for Updates** to **Update and Restart** when the latest stable
  release includes the expected DMG and checksum assets.
- Download only after an explicit click into a private temporary directory.
- Verify SHA-256, bundle identity, newer version, complete code signature, and
  the installed signing identity or macOS trust assessment.
- Replace the installed application only after the running process exits, with
  rollback protection and automatic relaunch.
- Remove the downloaded DMG and staged application after success or failure.

This test patch uses the existing release packaging path. Public distribution
still requires Developer ID signing and notarization before general release.
