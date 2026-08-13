Version 4.2.7 fixes capture failures caused by microphone format changes and
corrects the misleading interruption shown for silent dictations.

## Microphone route changes no longer terminate the app

macOS can change an input device's native sample rate while the app is idle,
especially after wake or when an audio route changes. The prior capture path
could read 48 kHz, then attempt to install that stale format after the hardware
had moved to 24 kHz. AVAudioEngine raises an uncaught native exception for that
mismatch.

Capture now installs its tap using the input node's current native format. The
private writer creates or replaces its converter from the actual incoming
buffer, so a route change remains compatible with the fixed private 16 kHz mono
WAV used for local recognition.

## Correct silent-dictation result

The recognition coordinator now preserves the recognizer's explicit no-speech
result. Silence shows the bounded No Speech Detected state instead of being
collapsed into Transcription Interrupted. Genuine provider failures retain the
interruption path.

## Verification

- The complete Swift suite passes: 377 tests, with three intentional opt-in
  integration tests skipped.
- A format-change regression feeds a 24 kHz microphone buffer after a stale
  48 kHz converter and verifies valid 16 kHz output.
- The installed signed bundle survived ten consecutive capture/cancel cycles
  and a completed silent session without a crash or format-mismatch log.
- The installed app and controller match their built SHA-256 hashes and the
  bundle passes deep strict code-signature verification.

## Compatibility

No preference is migrated or reset. The release remains a native arm64 macOS
14-or-newer app with local-only audio and recognition. It uses the same three
permissions: Microphone, Accessibility, and Input Monitoring.

The app is signed with the project's stable Apple Development identity and is
not notarized. A first manual installation may still require System Settings >
Privacy & Security > Open Anyway. The ZIP is the human download; the DMG
remains for the in-app updater.
