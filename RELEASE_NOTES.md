Version 4.2.9 adds explicit microphone routing and lowers warm whisper.cpp response latency without changing recognition accuracy.

## Selectable microphone routing

The menu bar now offers a Microphone submenu with Automatic plus every available input device. Automatic follows the current macOS default. A manual choice persists the device's stable Core Audio UID, configures only whisper_hotkey's owned audio engine, and never changes the system-wide default. Route recovery reapplies the choice. A disconnected manual device remains visible as unavailable and fails explicitly instead of silently recording another microphone.

Terminal status reports both the configured source and effective active microphone, making AirPods and aggregate-device routing directly observable.

## Faster Model Ready response

Model Ready retains its complete-session recognition path. Version 4.2.9 removes duplicate per-session preparation and replaces the whisper.cpp helper's 10 ms response polling with event-driven wake-up. Full audio context, dictionary prompt, selected decoding strategy, beam width, sanitizer, formatter, and exactly-once delivery remain unchanged. Parakeet decoding is unchanged.

## Capture reliability

A bounded first-buffer watchdog handles the separate running-but-silent engine state: after one second without a non-empty input buffer, capture requests one token-scoped graph recovery. Continued starvation fails visibly and follows normal private-audio cleanup instead of remaining stuck on Listening.

## Verification

- The complete Swift suite passes: 397 tests, with three intentional opt-in integration tests skipped.
- All 16 bootstrap and release-tooling tests pass.
- Menu and Settings coverage verifies Automatic, manual, disconnected, and busy-state microphone behavior.
- Focused capture coverage verifies token-scoped watchdog and route-recovery behavior.
- The bundled application builds with a valid deep signature; the built and installed executables match.
- Installed status resolves Automatic to the active Mac microphone.

## Distribution

The stable download remains the Developer ID-signed, hardened, notarized, and stapled `whisper_hotkey.dmg`. The website, GitHub release, and in-app updater use that DMG and matching SHA-256 asset. No application ZIP or unnotarized fallback is published.
