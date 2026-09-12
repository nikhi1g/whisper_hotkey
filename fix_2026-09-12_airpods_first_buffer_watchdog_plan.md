# AirPods First-Buffer Watchdog Plan

## Problem

Version 4.2.8 repairs the observed AirPods failure when macOS posts
`AVAudioEngineConfigurationChange`: the recorder removes the stale input tap,
resets the engine, validates the new native input format, reinstalls the tap, and
restarts capture without discarding audio already written.

That recovery remains notification-driven. Core Audio can report
`AVAudioEngine.isRunning == true` while the input tap delivers no buffers, or it
can fail to deliver a useful configuration-change notification. In that state,
the UI remains in Listening, the level remains zero, and capture has no outcome
until the user explicitly stops it. The recorder already measures the first
buffer and first committed sample, but `scheduleCaptureTimingReport(for:)` uses
those measurements only for bounded logging.

## Objective

Bound the no-input state during an active dictation. If the selected input does
not deliver its first non-empty buffer within one second of capture startup,
restart the existing engine graph once through the established recovery path.
If no buffer arrives within one additional second, fail visibly and run normal
session cleanup.

The watchdog must observe delivered audio, not `AVAudioEngine.isRunning`, because
the latter describes graph state rather than microphone progress.

## Non-goals

- Do not replace `AVAudioEngine` during the first implementation.
- Do not add an idle timer, device watcher, polling loop, or audio worker.
- Do not change model loading, recognition, VAD thresholds, segmentation, or
  insertion behavior.
- Do not log audio, transcript text, device names, prompts, or raw buffers.
- Do not retry indefinitely or silently continue with an empty recording.

## Existing ownership

- `WhisperAudioRecorderBackend.controlQueue` in
  `Sources/WhisperHotkeyASR/AudioCapture.swift` serializes engine start/stop,
  input-tap mutation, adoption, cancellation, and route recovery.
- `WhisperAudioCaptureTimingTracker` records the first non-empty tap buffer and
  first committed sample under `NSLock`.
- `restartCaptureAfterConfigurationChange()` already performs the required safe
  graph repair while preserving the existing `WhisperBufferedAudioSink`, writer,
  lease, canonical WAV, segment WAV, and capture token.
- `recordingPresentationTask` in
  `Sources/WhisperHotkeyApp/WhisperHotkeyApplicationDelegate.swift` already runs
  only while listening and samples recorder presentation state every 50 ms.
- `cancelSession()` and the recorder cleanup paths already own final task,
  engine, sink, writer, lease, and temporary-file cleanup.

The watchdog belongs in the ASR backend. The application should only translate a
latched backend failure into the existing visible failure transition.

## Design

### Timing and retry policy

Add explicit constants to `WhisperAudioRecorderBackend`:

```swift
private static let firstBufferDeadline: TimeInterval = 1.0
private static let postRecoveryBufferDeadline: TimeInterval = 1.0
private static let maximumFirstBufferRecoveries = 1
```

One second is intentionally conservative relative to the existing 500 ms timing
report. It leaves room for Bluetooth profile negotiation while changing an
unbounded stall into a failure or successful recovery within approximately two
seconds. These values remain implementation constants, not user preferences.

Track only capture-scoped state:

```swift
private var firstBufferRecoveryCount = 0
```

The active token and the existing timing tracker identify the session. Do not
introduce a repeating timer or a second queue.

### Scheduling

After `prepareCapture(...)` has successfully started the engine and attached the
writer, enqueue one `controlQueue.asyncAfter` closure for the active token and
its `WhisperAudioCaptureTimingTracker`.

The closure must revalidate all of the following before acting:

- `activeToken == token`;
- `phase != nil`;
- `startupError == nil` and `captureError == nil`;
- the timing tracker still has no first non-empty buffer.

A stale closure therefore becomes a no-op after cancellation, quick-tap
rejection, normal finalization, a newer capture, or successful buffer delivery.
No explicit timer cancellation object is required; monotonically increasing
capture tokens prevent a closure from affecting a later session.

### Outcome-based recovery

Add a lock-protected timing query such as:

```swift
var hasReceivedFirstBuffer: Bool
```

The first deadline evaluation has three outcomes:

1. **Buffer received:** return without touching the engine.
2. **No buffer, recovery unused:** increment `firstBufferRecoveryCount`, invoke
   the existing restart primitive on `controlQueue`, and schedule the
   post-recovery deadline for the same token and timing tracker.
3. **No buffer after recovery:** latch a capture failure and stop the engine/tap.

Refactor the small duplicated failure assignment in
`recoverFromConfigurationChange()` into a backend helper that sets
`startupError` for a provisional capture or `captureError` for an adopted
capture. Both notification recovery and watchdog recovery must use the same
message classification and cleanup ownership.

A successful `engine.start()` must not reset `firstBufferRecoveryCount`. Engine
startup is not evidence that the microphone is producing data. Only first-buffer
arrival makes the pending watchdog closure harmless. Reset the count in
`beginProvisionalCapture` and every normal/error cleanup path.

Keep `configurationRecoveryFailures` separate. It bounds exceptions thrown while
repairing a notified route change; `firstBufferRecoveryCount` bounds successful
restarts that still produce no input. Combining them would conflate two distinct
failure signals and could suppress the watchdog after a transient thrown start.

### Failure propagation

Expose the already-latched active capture error through a read-only recorder
property, backed by `controlQueue.sync`. Do not throw from the Core Audio callback
or invoke AppKit from ASR.

During the existing 50 ms `recordingPresentationTask` loop, check this property
before updating the meter. When present, call the application delegate's
existing `fail(_:)` path and return. That path already:

- invalidates the session generation;
- cancels recognition and presentation work;
- calls `recorder.cancel()`;
- stops capture;
- deletes the private audio lease after borrowers unwind;
- presents the actionable error for the standard duration.

Use a content-free message such as `Microphone input did not begin delivering
audio.` Do not include the device name or Core Audio internals in user-facing
text or logs.

The same error observation also improves the existing notification-recovery
path: a route recovery that exhausts its restart attempts becomes visible while
recording rather than only when the user later stops.

## State transitions

```text
capture starts
    |
    +-- first buffer before 1.0 s -----------------> continue normally
    |
    +-- no first buffer at 1.0 s
            |
            +-- restart throws --------------------> existing bounded route retry
            |
            +-- restart succeeds
                    |
                    +-- first buffer within 1.0 s -> continue normally
                    |
                    +-- still no buffer -----------> latch failure
                                                        |
                                                        +-> app fail transition
                                                        +-> recorder cancellation
                                                        +-> private-audio cleanup
```

Configuration notifications may arrive before either deadline. Their recovery
continues to use `configurationRecoveryScheduled` for deduplication. Every
watchdog evaluation rechecks the timing tracker after earlier queued recovery
work, so a notification-driven recovery that restores buffers prevents a second
restart.

## Concurrency invariants

1. All engine and tap mutations remain on `controlQueue`.
2. The real-time tap callback performs no scheduling, engine mutation, logging,
   or AppKit work; it only uses the existing locked timing mark and bounded PCM
   enqueue.
3. A watchdog closure may act only on the exact token that scheduled it.
4. At most one watchdog-triggered restart occurs per capture.
5. Successful `engine.start()` is never treated as proof of audio delivery.
6. The canonical writer and lease survive the one recovery attempt.
7. Failure cleanup remains idempotent and uses the existing recorder/app paths.
8. No watchdog activity exists after a session ends or while the app is idle.

## Files and symbols

### `Sources/WhisperHotkeyASR/AudioCapture.swift`

- `WhisperAudioRecorder`
  - Add a read-only active capture failure accessor.
- `WhisperAudioRecorderBackend`
  - Add watchdog constants and `firstBufferRecoveryCount`.
  - Schedule the first deadline after successful capture preparation.
  - Add token-checked deadline evaluation and post-recovery scheduling.
  - Share failure latching with configuration-change recovery.
  - Reset watchdog state in new-session and cleanup paths.
- `WhisperAudioCaptureTimingTracker`
  - Add a lock-protected first-buffer query; retain existing timestamps.

### `Sources/WhisperHotkeyApp/WhisperHotkeyApplicationDelegate.swift`

- `startRecordingPresentation(generation:limit:)`
  - Read the recorder failure before the level sample.
  - Route it through `fail(_:)` exactly once and exit the active presentation
    task.
- `scheduleCaptureTimingReport(for:)`
  - Keep it telemetry-only. It must not become a second watchdog owner.

### `Tests/WhisperHotkeyASRTests/AudioCaptureTests.swift`

Add focused coverage for observable watchdog behavior using a deterministic test
seam around deadline evaluation/restart, without sleeping for wall-clock time:

1. A first buffer before the deadline causes no restart and no failure.
2. Missing the first deadline requests exactly one restart.
3. A first buffer after that restart suppresses the second-deadline failure.
4. Missing both deadlines latches one failure and cannot trigger another restart.
5. A stale token after cancellation or replacement performs no action.
6. Notification recovery followed by a delivered buffer prevents watchdog
   recovery.

The test seam should inject scheduling/restart effects at the narrow backend
boundary. Do not mock the recognizer, clipboard, UI, or transcript pipeline.

### `Tests/WhisperHotkeyAppTests/`

Add an application-level test only if the current test construction can observe
`fail(_:)` without reproducing AppKit lifecycle. Its contract is that a latched
recorder failure leaves Listening and enters the existing failure cleanup path.
If that requires a broad new dependency-injection framework, omit the permanent
test and cover the boundary with an installed-app smoke check instead.

## Verification

### Automated

```sh
swift test --filter AudioCaptureTests
swift test
python3 Tests/BootstrapTests/test_run_sh.py
```

Required assertions:

- exactly one watchdog recovery;
- no action after first-buffer delivery;
- no action from a stale capture token;
- visible failure after continued starvation;
- private audio removed on failure;
- existing AirPods format-transition and engine-notification tests remain green.

### Bundle and installation

```sh
python3 build_app.py
codesign --verify --deep --strict --verbose=2 dist/whisper_hotkey.app
python3 install.py
~/bin/whisper_hotkey status
```

Verify the installed executable path and signature, and compare built/installed
executable hashes as `install.py` already requires.

### Physical AirPods matrix

The decisive check remains real Bluetooth hardware:

1. Connect AirPods before launching dictation; speak immediately after the
   trigger.
2. Connect AirPods while the app is idle, then dictate.
3. Start dictation while AirPods negotiate their microphone profile.
4. Change the route during active capture, continue speaking, and finish.
5. Disconnect AirPods while idle and confirm the next built-in-mic dictation.

For successful cases, confirm both first-buffer and first-committed-sample timing
appear as numeric metadata only. For a deliberately unavailable input, confirm a
bounded actionable failure replaces the indefinite Listening state and no
private temporary audio remains.

## Rollback

The change is isolated to one-shot active-capture health detection. Rollback
removes the watchdog scheduling/state and the recorder-error observation while
leaving the 4.2.8 notification-driven recovery intact. No preference, protocol,
model, migration, or persistent data changes are involved.

## Acceptance criteria

- A capture that receives audio normally is behaviorally unchanged.
- A silent-but-running engine is restarted once within one second.
- Audio arriving after recovery continues through the original writer and lease.
- Continued starvation becomes a visible failure within approximately two
  seconds instead of an indefinite stall.
- Cancellation and later sessions cannot be affected by an earlier deadline.
- No idle timer, polling task, model, helper, or network request is added.
- Focused tests, full tests, signed bundle build, installation verification, and
  the physical AirPods matrix pass.

## TL;DR / Read This If You Read Nothing Else

Add one token-scoped, one-shot deadline to the recorder. If no non-empty mic
buffer arrives within one second, reuse the existing AirPods engine restart once.
If another second passes without a buffer, surface an error and use normal secure
cleanup. Keep all engine work on the recorder queue, reuse the active UI loop to
notice failure, and add no idle polling. Normal captures do nothing new; broken
Bluetooth captures recover or fail clearly instead of hanging.
