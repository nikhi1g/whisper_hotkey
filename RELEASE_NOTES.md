Version 4.3.1 reduces application-imposed capture onset delay and starts the listening badge's updates before gesture acceptance.

## Physical-edge capture and presentation

Model Ready and Decode After Speaking now use an AVAudioEngine sink node's native render quanta instead of waiting for an input tap to coalesce audio. The existing bounded FIFO retains an owned copy of each quantum before Core Audio reuses its buffer. Conversion, speech detection, metering, and private WAV writes remain on the writer queue.

The provisional pointer-fallback badge starts its waveform and timer updates before Hold dwell or Toggle release acceptance. Accepting capture is asynchronous, so engine startup cannot block the main actor or freeze the badge. Acceptance does not reset its waveform or elapsed time. Quick taps and modifier shortcuts still reject only their matching provisional capture and discard its audio without recognition or insertion.

Content-free diagnostics distinguish badge visibility, recorder queue admission, engine startup, first non-empty buffer, and first committed sample. They do not equate queue admission with microphone readiness. Bluetooth activation can still add hardware latency; audio that the hardware has not supplied cannot be recovered without keeping a microphone active at idle, which this app does not do.

## Complete-recording processing and finishing

Decode After Speaking prepares its model only after the complete private WAV seals. Model Ready may warm after recorder admission, but also decodes only sealed full-session audio.

Finish input captures the destination immediately. Continued speech is retained until the learned cadence silence target is reached, subject to `0.25 + 0.75 * d / (d + 10)` seconds of maximum additional wait, where `d` is confirmed speaking duration. Cancellation is immediate and the recording limit remains authoritative.

Decode While Speaking and Pause Mode retain their existing input tap, segmentation, recognition, reconciliation, prompts, and completion behavior.

## Distribution

The packaged helper now resolves its signed libraries from the application's
Frameworks directory, rather than depending on the builder's Homebrew or
temporary dependency paths.

This change does not publish an artifact. Stable distribution still requires a Developer ID-signed, hardened, securely timestamped, notarized, and stapled DMG with its matching SHA-256 asset. A local Apple Development-signed candidate is not a production distribution artifact.
