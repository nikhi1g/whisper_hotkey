Version 4.2.8 restores AirPods dictation when macOS changes the Bluetooth audio
route after capture has started.

## AirPods route changes resume the active recording

When an AirPods microphone activates, macOS can change the input hardware's
sample rate or channel count. Apple documents that `AVAudioEngine` stops itself
during this reconfiguration and posts an engine-specific configuration-change
notification. Version 4.2.7 safely followed changing buffer formats, but it did
not restart an engine that macOS had stopped, so no later microphone buffers
could reach the writer.

The recorder now observes that notification for its exact engine and returns
recovery work to its existing serial capture queue. It removes the invalidated
tap, resets the stopped engine, validates the current input, reinstalls the tap
using the device's native format, and resumes the same private recording. Audio
already written before the transition is retained. A transient restart failure
gets one bounded delayed retry; a second failure stops visibly and uses the
normal private-audio cleanup path.

The existing local-only guarantees are unchanged. Audio and transcripts remain
ephemeral, no content enters logs, and route recovery adds no idle polling,
resident model, or network activity.

## Verification

- The complete Swift suite passes: 379 tests, with three intentional opt-in
  integration tests skipped.
- All 16 bootstrap and release-tooling tests pass.
- Configuration notifications are accepted only from the recorder's owned
  `AVAudioEngine`, and the observer unregisters with its owner.
- Consecutive 48 kHz, 16 kHz, and 24 kHz microphone buffers produce one valid
  private 16 kHz mono WAV.
- The release workflow blocks publication unless the Developer ID signature,
  notarized and stapled DMG, Gatekeeper assessment, and artifact checks pass.

## Distribution

Version 4.2.8 is the first release under the settled stable-publication policy:
the application is Developer ID-signed with hardened runtime and secure
timestamps, the DMG is notarized and stapled, and Gatekeeper assessment must
pass before GitHub publishes it. The DMG is the only packaged application
download used by the product website and in-app updater.

The first Developer ID build changes the app's designated requirement from the
historical Apple Development identity. Existing users may need to grant
Microphone, Accessibility, and Input Monitoring again after replacing the old
installation. No preference is migrated or reset. The release remains native
arm64 and requires macOS 14 or later.
