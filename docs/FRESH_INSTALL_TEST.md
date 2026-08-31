# Fresh Install Test

Deleting only `/Applications/whisper_hotkey.app` does not reproduce a new
user. The current macOS account can still retain preferences, model files,
permissions, a login item, and the controller installed by `run.sh`.

## Recommended test: fresh macOS user

1. Create a temporary Standard user in System Settings > Users & Groups.
2. Sign in to that account without copying files from the development account.
3. Open Safari and download the current DMG from the public product site or
   GitHub release.
4. Open the DMG, drag `whisper_hotkey.app` to Applications, and launch it.
5. Confirm Finder mounts the quarantined DMG without **Move to Trash** or an
   **Open Anyway** workaround, and that the app launches normally.
6. Complete the Microphone, Accessibility, and Input Monitoring prompts.
7. Confirm the default dictation key is Right Option.
8. Dictate into TextEdit, Safari, and one Electron application.
9. Use Settings > Check for Updates to verify the public update path.

This isolates per-user preferences, permissions, model caches, login items, and
the controller. Homebrew, Xcode, and the source checkout in the development
account do not affect the test.

## Strongest isolation: fresh macOS virtual machine

Use a new Apple Silicon macOS virtual machine when testing Gatekeeper, first
download behavior, and installation without any machine-level development
tools. Take a snapshot before the first download so the complete flow can be
repeated without manually clearing private state.

## Developer ID migration test

The first notarized release also needs an upgrade test from the latest
Apple Development-signed public version. Grant all three permissions to the old
version, update through Settings, and record whether macOS asks for any one-time
reapproval after the designated requirement changes. Preferences, models, the
login item, and in-app replacement must survive.

## Same-account smoke test

A same-account test is useful for updating an existing installation, but it is
not evidence of a clean install. Do not delete preferences, permissions, model
caches, or login items on the development account merely to simulate one.
