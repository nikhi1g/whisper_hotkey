# whisper_hotkey

Native, offline dictation for macOS 14+ on Apple Silicon.

A configurable modifier starts local Whisper capture. Releasing or toggling it
finishes recognition and pastes into the focused app. The app includes
Press-and-Hold, Toggle, and Pause modes, a caret HUD, local vocabulary hints,
four model sizes, and optional Core ML engines.

## Development

Requires Xcode, Apple Silicon, Homebrew `whisper-cpp`, and a local model.

```sh
git clone https://github.com/nikhi1g/whisper_hotkey.git
cd whisper_hotkey
swift build
swift test
```

Bootstrap dependencies, models, build, installation, and Setup:

```sh
./run.sh
./run.sh --model turbo
./run.sh --all-models
./run.sh --model turbo --engine whisperkit
```

Build and install directly:

```sh
python3 build_app.py
python3 install.py
```

`build_app.py` requires `WHISPER_HOTKEY_CODESIGN_IDENTITY` or another valid
local signing identity. It never silently falls back to ad-hoc signing.

## Structure

| Target | Responsibility |
| --- | --- |
| `WhisperHotkeyCore` | State, preferences, contracts |
| `WhisperHotkeyASR` | Capture, VAD, recognition |
| `WhisperHotkeySystem` | Hotkeys, Accessibility, paste |
| `WhisperHotkeyShell` | Menu, Settings, Setup, HUD |
| `WhisperHotkeyApp` | Lifecycle and orchestration |
| `WhisperModelHelper` | Local whisper.cpp process |
| `whisper_hotkey` | Terminal controller |

```text
hotkey -> capture + preload -> local decode -> clipboard -> Command-V
```

With **Keep Model Ready** off, no model remains loaded at idle. Audio is private
and temporary. Audio and transcripts are never logged or sent remotely. The
running app never downloads models.

## Control

```sh
whisper_hotkey status
whisper_hotkey start
whisper_hotkey stop
whisper_hotkey restart
whisper_hotkey cancel
whisper_hotkey setup
whisper_hotkey enable-login
whisper_hotkey disable-login
whisper_hotkey logs
```

Installation targets:

```text
/Applications/whisper_hotkey.app
~/bin/whisper_hotkey
```

## References

- [Product contract](purpose.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Models and engines](docs/MODELS.md)
- [Changelog](CHANGELOG.md)
- [Agent instructions](AGENTS.md)
