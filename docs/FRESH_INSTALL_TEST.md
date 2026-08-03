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
5. Complete the microphone, Accessibility, and Input Monitoring prompts.
6. Confirm the default dictation key is Right Option.
7. Dictate into TextEdit, Safari, and one Electron application.
8. Use Settings > Check for Updates to verify the public update path.

This isolates per-user preferences, permissions, model caches, login items, and
the controller. Homebrew, Xcode, and the source checkout in the development
account do not affect the test.

## Strongest isolation: fresh macOS virtual machine

Use a new Apple Silicon macOS virtual machine when testing Gatekeeper, first
download behavior, and installation without any machine-level development
tools. Take a snapshot before the first download so the complete flow can be
repeated without manually clearing private state.

## Same-account smoke test

A same-account test is useful for updating an existing installation, but it is
not evidence of a clean install. Do not delete preferences, permissions, model
caches, or login items on the development account merely to simulate one.
