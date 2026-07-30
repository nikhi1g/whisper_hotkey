# whisper_hotkey 2.11.0: Perimeter Flow

Version 2.11 replaces textual transcribing feedback with a compact perimeter
activity treatment and adds local vocabulary personalization.

## Highlights

- Replace the Transcribing label with a thin activity trail that starts at the
  capsule's top center and loops clockwise around its complete perimeter.
- Keep one fixed HUD size and position through listening, transcribing, and
  insertion.
- Drive the seven-segment fading trail through Core Animation with no polling
  task, gradient, or idle work.
- Add an Internal dictionary for names and technical phrases, applied locally
  across every dictation mode.
- Tighten the HUD to a flat 203 by 42-point capsule with equal circular actions,
  no panel shadow, and no static outline.
- Retain Metal, Core ML Encoder, WhisperKit, model readiness, Pause Mode,
  terminal control, and private ephemeral audio.

Quick Start:

```sh
git clone https://github.com/nikhi1g/whisper_hotkey.git
cd whisper_hotkey
./run.sh
```

The release includes source and a signed arm64 app bundle. The app is not
notarized and model weights are not included. The verified source bootstrap is
the recommended installation path for a new Mac.
