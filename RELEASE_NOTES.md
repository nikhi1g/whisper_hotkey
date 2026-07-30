# whisper_hotkey 3.0.0: Parallel Recognition

Version 3.0 adds confidence-adaptive decoding and an optional processing
pipeline that begins recognition while speech capture continues.

## Highlights

- Choose After Recording, Model Ready, or Decode While Speaking from the
  Processing control in Settings.
- Decode bounded speech chunks in the background through one serial model
  runtime while microphone capture continues.
- Keep partial results private and insert once when dictation finishes.
- Preserve the complete recording for automatic full-context fallback if any
  background chunk fails.
- Use Smart Decode to accept confident fast passes and retry uncertain audio
  with five-beam Precision decoding.
- Retain the compact fixed HUD, internal dictionary, Pause Mode, Apple
  acceleration options, terminal control, and ephemeral local audio.
- Include a reproducible 100-recording LibriSpeech benchmark covering release
  latency and word error rate.

Quick Start:

```sh
git clone https://github.com/nikhi1g/whisper_hotkey.git
cd whisper_hotkey
./run.sh
```

The release includes source and a signed arm64 app bundle. The app is not
notarized and model weights are not included. The verified source bootstrap is
the recommended installation path for a new Mac.
