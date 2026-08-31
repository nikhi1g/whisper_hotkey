# Fix Proposal: Recover AirPods Input After Audio-Engine Reconfiguration

**Date:** 2026-08-31  
**Baseline:** `main`, based on the latest public release `v4.2.7`

## Observed failure

Dictation does not capture usable audio when AirPods are the microphone input.

The public `v4.2.7` release already prevents the previously fixed stale-format crash:

- the input tap uses the device's current native format (`format: nil`);
- `WhisperWAVWriter` replaces its converter whenever an incoming buffer's format changes;
- empty Core Audio callbacks are ignored;
- captured audio remains fixed at private 16 kHz mono PCM.

Repeating those changes would not address the remaining failure.

## Remaining failure mechanism

Apple documents that when an `AVAudioEngine` I/O unit observes a hardware sample-rate or channel-count change, the engine stops itself and posts `AVAudioEngineConfigurationChangeNotification`. Activating an AirPods microphone can trigger exactly that transition as macOS changes the Bluetooth audio configuration.

The current recorder does not observe that notification. Therefore capture can start successfully, the route can reconfigure, and the engine can then remain stopped for the rest of the dictation. The writer's dynamic format handling cannot help because no later buffers arrive.

`AVAudioSessionRouteChangeNotification` is not part of this fix because `AVAudioSession` route APIs are unavailable on macOS.

## Fix

1. Observe `AVAudioEngineConfigurationChangeNotification` for the recorder's exact engine instance.
2. Forward the notification onto the recorder's existing serial capture-control queue. Never tear down the engine inside Core Audio's notification callback.
3. If a capture is active and otherwise healthy:
   - remove the invalidated tap;
   - reset the stopped engine;
   - re-read and validate the current input format;
   - reinstall the tap with `format: nil`;
   - prepare and restart the engine while retaining the existing sink, writer, private file, and capture token.
4. Bound recovery attempts. Retry a transient invalid-format/start failure once after a short one-shot settling delay, then fail the recording visibly and delete private audio through the normal cleanup path.
5. Reset recovery state on every new capture and every cleanup path.

This preserves speech already written before the route transition and resumes the same recording after the AirPods input becomes usable. It adds no idle polling, resident helper, audio retention, or network activity.

## Verification

### Automated

- Notification observation is scoped to the exact `AVAudioEngine` instance and unregisters with its owner.
- Consecutive 48 kHz, 16 kHz, and 24 kHz input buffers produce one valid private 16 kHz mono WAV.
- Existing ASR tests pass.
- The application bundle builds and passes strict code-signature verification.

### Installed application

1. Replace `/Applications/whisper_hotkey.app` and `~/bin/whisper_hotkey` from the new build.
2. Verify built and installed executable hashes match.
3. Verify the launched process executes from `/Applications/whisper_hotkey.app`.
4. With AirPods selected as the macOS input device, exercise:
   - AirPods connected before dictation;
   - AirPods connected while the app is idle, followed by dictation;
   - AirPods disconnected while idle, followed by dictation;
   - a route change during active dictation, followed by another dictation.

A physical AirPods interaction remains the decisive end-to-end check; synthetic tests cover notification routing and multi-format conversion but cannot reproduce Bluetooth hardware negotiation.