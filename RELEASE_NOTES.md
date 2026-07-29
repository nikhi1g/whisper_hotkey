# whisper_hotkey 2.9.0: Apple Acceleration

Version 2.9 adds two optional Apple-optimized recognition paths while retaining
the established Metal engine and local dictation workflow.

## Highlights

- Select Metal, whisper.cpp Core ML Encoder, or native WhisperKit directly
  beneath Model in Settings.
- Keep Metal as the compatible default with no change to existing preferences.
- Provision accelerated artifacts only through the explicit bootstrap with
  pinned revisions and SHA-256 verification.
- Prevent incomplete engines from being selected and never silently fall back
  to another engine.
- Optionally keep the selected model ready for shorter startup latency.
- Apply the selected theme to the HUD, Settings, and User Guide.
- Retain Press and Hold, Toggle, Pause Mode, caret-aware HUD placement,
  recording limits, terminal control, and local-only ephemeral audio.

Clone the repository and run:

```sh
./run.sh
```

The bootstrap installs/checks Homebrew whisper.cpp, downloads the verified Base
English model, builds and signs the app locally, installs it in `/Applications`,
launches it, and opens the macOS permission setup.

Optional accelerated Turbo installations:

```sh
./run.sh --model turbo --engine coreml
./run.sh --model turbo --engine whisperkit
```

The release includes a source archive and a signed arm64 app bundle. The app is
not notarized and model weights are not included. The source bootstrap remains
the recommended installation path for a new Mac.
