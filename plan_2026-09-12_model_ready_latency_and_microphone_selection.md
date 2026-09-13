# Model Ready Latency and Microphone Selection Plan

## Decision

Preserve Model Ready's whole-recording, full-context recognition path. Do not reuse Decode While Speaking chunks, merge provisional text, reduce beam width, shorten completion post-roll, or change recognition output. The speed win is deliberately small and deterministic: remove redundant per-session model preparation and replace the whisper.cpp helper's 10 ms response polling with event-driven wake-up. This preserves every accuracy input while removing avoidable actor work, wakeups, and up to one polling interval from helper response delivery.

Add a Settings microphone picker with **Automatic** plus every currently available input device. Automatic keeps today's system-default behavior. A manual choice binds only whisper_hotkey's owned audio engine; it must never change the macOS system default.

## Current accuracy path

Model Ready uses one complete-session decode, not chunk fusion. Its effective accuracy stages vary by engine, but there are three active categories:

1. **Acoustic decode:** one full-context primary recognition pass; whisper.cpp uses the selected Precision or Smart Decode policy, while Parakeet uses its native decoder.
2. **Recognition guidance/retry:** whisper.cpp can consume the bounded internal-dictionary prompt and Smart Decode can retry uncertain output with the Precision beam. Parakeet does not support prompts or beam retry.
3. **Deterministic output cleanup:** transcript protocol validation, sanitization, and lexically invariant formatting preserve recognized words while normalizing presentation.

The selective verifier infrastructure is present but disabled without promoted calibration and verifier artifacts; it must not be counted as an active production layer.

## Track A: Model Ready latency without accuracy loss

### A1. Measure the exact boundary

Add content-free monotonic timings around:

- completion gesture to recorder finalization,
- finalization to coordinator primary request,
- primary request to provider result,
- provider result to delivery.

Expose timings only to tests or existing numeric diagnostics. Never log audio, transcript text, prompts, filenames, or destination content. Use the measurements to verify that the implementation removes scheduling delay rather than claiming faster model inference.

### A2. Remove duplicate preparation ownership

`RecognitionPipelineCoordinator.beginSession()` already owns `providers.preparePrimary`. `WhisperHotkeyApplicationDelegate.beginSession()` also creates a separate `preloadTask` for modes that keep the model ready, then finalization awaits both tasks. Make the coordinator the sole per-session preparation owner:

- remove the application-level duplicate preload task and its await,
- keep idle Model Ready lifecycle in `WhisperRecognition.setKeepsModelReady`,
- let `pipelineBeginTask` remain the single session-readiness barrier,
- preserve cleanup ordering when settings change, cancellation occurs, or the app terminates.

Acceptance: one preparation request per session, no model reload for an already-ready model, and finalization waits for exactly one readiness barrier.

### A3. Replace whisper.cpp event polling

`WhisperHelperSession.nextEvent()` currently checks its line queue and sleeps for 10 ms repeatedly. Extend the bounded line queue with an async waiter:

- a pushed line resumes one waiter immediately,
- finish/termination resumes waiters with an explicit closed state,
- cancellation unregisters its waiter and cancels the owned helper as today,
- timeout remains authoritative and terminates the helper on expiry,
- line ordering and one-command/one-terminal-event semantics remain unchanged,
- no detached polling task or idle timer is introduced.

This removes repeated wakeups and up to 10 ms of response-delivery latency for warm whisper.cpp Model Ready sessions. Parakeet does not use this helper; its decode remains unchanged unless timing evidence identifies a separate avoidable boundary.

### A4. Accuracy invariants

Tests must prove the optimized Model Ready path still submits:

- the same complete audio object and sample range,
- `.primaryFullSession` and `.finalSession`,
- the same prompt, decoding strategy, and beam size,
- the same sanitizer/formatter stages,
- exactly one final delivery.

Do not compare source wiring. Assert provider requests and consumer-visible transcript/delivery behavior.

## Track B: Microphone source picker

### B1. Core preference model

Add a small value type representing either:

- `automatic`, or
- a persistent Core Audio device UID.

Persist the UID, not the transient `AudioDeviceID`. Add a dedicated preference key. Existing installations default to Automatic with no migration write. A manual selection remains stored across disconnect/reconnect.

### B2. Device discovery and resolution

Add a narrow Core Audio input-device service beside audio capture. It must:

- enumerate devices with input channels,
- resolve stable UID, display name, and current `AudioDeviceID`,
- identify the current system-default input,
- return deterministic name-sorted choices with UID tie-breaking,
- tolerate devices disappearing during enumeration,
- avoid polling.

Wrap Core Audio property access behind a protocol so tests use deterministic fixtures. Do not use `AVCaptureDevice` for routing; it owns permission discovery, while AVAudioEngine input routing requires Core Audio device identity.

### B3. Recorder routing

Before installing the input tap or starting `AVAudioEngine`, resolve the stored selection on the recorder control queue:

- Automatic leaves the engine on the system-default input.
- Manual sets the owned AUHAL input device using its current `AudioDeviceID`.
- Never modify the machine-wide default input.
- Validate a nonzero sample rate and channel count after selection.
- A missing manually selected device fails visibly as unavailable; it must not silently capture another microphone.
- Configuration-change recovery reapplies the selection before reinstalling the tap.
- Capture timing, first-buffer watchdog, private WAV ownership, and cancellation semantics remain unchanged.

Changing the setting is disabled during active dictation, matching all other configuration controls. Applying a new idle selection resets only the recorder graph; it does not load a model.

### B4. Settings and status surfaces

Add a **Microphone** popup near the Dictation key/Input behavior controls:

- first item: `Automatic — <current default name>`,
- remaining items: available input-device names,
- manual selected device carries a checkmark,
- a disconnected stored device appears as `Unavailable — <last known name>` until the user chooses another source,
- native help text explains that Automatic follows macOS and manual selection affects only whisper_hotkey.

Refresh choices when Settings opens and after a selection. If live device-list updates are needed while the window remains open, install a Core Audio property listener only for the visible window and remove it on close; never add an idle polling task.

Extend terminal status with both configured and effective source, for example:

- `Microphone source: Automatic`
- `Active microphone: MacBook Pro Microphone`

Status must expose names only, never audio data or device transport metadata not needed by the user.

### B5. Tests

Keep tests only for durable behavior:

- preference round-trip and legacy default to Automatic,
- deterministic filtering/sorting of input-capable devices,
- stable UID resolving to a changed transient device ID,
- Automatic resolving the current default at capture start,
- manual selection applying only to the owned engine,
- missing manual device failing instead of falling back,
- route recovery reapplying the selected UID,
- Settings selection dispatching exactly once and remaining disabled while busy,
- status reporting configured and effective sources.

Use a fake Core Audio property client; tests must not change the developer machine's default input.

## Delegation and scoped commits

The main agent owns the complex backend and integration contract:

- event-driven helper response delivery,
- Model Ready preparation ownership,
- microphone preference and device value types,
- Core Audio enumeration, UID resolution, AUHAL routing, and recovery,
- application state/action wiring, status output, backend tests, integration,
- full verification, signed build, installation, and physical checks.

One isolated Luna Worker Max owns only the simple Settings presentation after
the main agent defines the shared state/action contract. Its write scope is:

- `Sources/WhisperHotkeyShell/AdvancedSettingsWindowController.swift`,
- `Tests/WhisperHotkeyShellTests/AdvancedSettingsWindowControllerTests.swift`.

The worker adds the Microphone popup, renders Automatic/available/unavailable
choices supplied by application state, dispatches one selection action, follows
the existing busy-state and theme conventions, and adds focused UI tests. It
must not define preferences, enumerate hardware, call Core Audio, change
application wiring, edit shared schemas, run broad suites, or install the app.
It returns one isolated commit for cherry-pick.

Commit boundaries:

1. `docs: assign model latency and microphone work` — this revised plan only.
2. `perf: remove warm recognition polling` — helper wake-up, preparation
   ownership, timings, and focused recognition tests.
3. `feat: add selectable microphone routing` — core preference, Core Audio
   backend, application/status wiring, and focused backend tests.
4. `feat: add microphone settings picker` — the delegated UI commit,
   cherry-picked without rewriting.
5. A separate documentation commit updates the product contract, architecture,
   guide, and release notes after the installed behavior is proven.

## Implementation order

1. Add latency measurements and baseline focused Model Ready runs.
2. Consolidate preparation ownership and verify lifecycle/cancellation.
3. Implement event-driven helper response waiting and verify ordering, timeout, close, and cancellation.
4. Add microphone preference and Core Audio discovery abstraction.
5. Apply selected routing in recorder startup and recovery.
6. Add Settings and status presentation.
7. Update product contract, architecture, user guide, and release notes only when behavior is implemented.

## Verification

- Focused recognition coordinator and helper protocol tests.
- Full `swift test` and bootstrap suite.
- Signed bundled build via `WHISPER_HOTKEY_BUNDLE_MODEL=1 python3 build_app.py`.
- Install into `/Applications`, verify signature, executable path, and built/installed hashes.
- Measure warm Model Ready completion before/after with identical generated private audio; report boundary deltas without claiming ASR inference improvement.
- Physical checks with Automatic, built-in microphone, AirPods manually selected, device disconnect/reconnect, missing manual device, route change during capture, and return to Automatic.
- Cross-app insertion checks for hold, toggle, and Pause Mode.
- Confirm no idle helper/timer is added outside the already-selected Model Ready policy and no audio/transcript appears in logs.

## Risks and limits

- Event-driven wake-up improves orchestration latency, not model inference; expected gain is bounded by the existing 10 ms poll interval plus removed actor scheduling.
- Manual Core Audio routing is hardware-sensitive. Device UIDs are stable, device IDs are not.
- Aggregate devices and Bluetooth profile changes may replace formats during capture; existing configuration recovery remains authoritative.
- A disconnected manual device must produce a clear failure rather than surprise the user with another microphone.
- Model Ready accuracy must remain byte-for-byte equivalent at the provider request boundary. Any optimization requiring provisional transcript reuse belongs to Decode While Speaking and is out of scope.
