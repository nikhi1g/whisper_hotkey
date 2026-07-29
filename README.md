# whisper_hotkey

Native, offline dictation for macOS 14+ on Apple Silicon.

Hold or toggle a configurable modifier key, speak, then insert the local Whisper
transcription into the focused app. The agent provides a menu-bar controller,
caret-attached HUD, three dictation modes, local vocabulary hints, four model
sizes, and optional Apple Core ML engines.

## Develop

Requirements:

- macOS 14+
- Apple Silicon
- Xcode and Command Line Tools
- Homebrew `whisper-cpp`
- At least one local Whisper model

```sh
git clone https://github.com/nikhi1g/whisper_hotkey.git
cd whisper_hotkey
swift build
swift test
```

Run the complete verified bootstrap:

```sh
./run.sh
```

Useful bootstrap variants:

```sh
./run.sh --model turbo
./run.sh --all-models
./run.sh --model turbo --engine coreml
./run.sh --model turbo --engine whisperkit
```

`run.sh` installs required local dependencies, verifies downloaded model
checksums, builds the app, installs it, launches it, and opens Setup. The running
application never downloads models.

## Build and install

```sh
python3 build_app.py
python3 install.py
```

The build script requires a stable signing identity. Set
`WHISPER_HOTKEY_CODESIGN_IDENTITY`, or allow it to select the first valid local
identity. It does not silently use ad-hoc signing.

Installation targets:

```text
/Applications/whisper_hotkey.app
~/bin/whisper_hotkey
```

## Architecture

| Target | Responsibility |
| --- | --- |
| `WhisperHotkeyCore` | State, preferences, shared contracts |
| `WhisperHotkeyASR` | Audio capture, VAD, local recognition |
| `WhisperHotkeySystem` | Global input, Accessibility, clipboard delivery |
| `WhisperHotkeyShell` | Menu, Settings, Setup, HUD, login and control transport |
| `WhisperHotkeyApp` | Application lifecycle and orchestration |
| `WhisperModelHelper` | Per-session whisper.cpp model process |
| `whisper_hotkey` | Terminal controller |

Runtime flow:

```text
hotkey -> capture + preload -> local decode -> clipboard transaction -> Command-V
```

With **Keep Model Ready** off, the model helper is created on demand and removed
after dictation. With it on, only the selected model helper remains resident.
The microphone and recording UI are active only during dictation.

## Recognition

Models:

- Base English, 141 MB
- Small English, 465 MB
- Medium English, 1.5 GB
- Large-v3 Turbo Q5, 547 MB

Engines:

- whisper.cpp Metal
- whisper.cpp Core ML encoder
- WhisperKit Core ML and Neural Engine

The decoder uses English, beam width five, Metal flash attention where
available, and half the logical CPUs up to eight threads.

Settings includes an **Internal dictionary** token field for names and technical
phrases. Entries are stored locally and compiled into a bounded recognition
prompt sent through private helper stdin. It adds no idle task or network work.

## Controls

The default gesture is bare Right Command press and hold. Settings can select
another modifier and one of:

- **Press and Hold**: release to transcribe and insert.
- **Toggle**: tap once to start and again to finish.
- **Pause Mode**: paste phrases after natural pauses while capture continues.

During dictation:

- Escape cancels and discards.
- Return or keypad Enter inserts and sends.
- The square HUD button inserts.
- The arrow HUD button inserts and sends.

## Terminal

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

## Privacy and permissions

The app requires Microphone, Accessibility, and Input Monitoring. It does not
request Screen Recording, Full Disk Access, or Automation.

Audio is written to private temporary files and deleted on every exit path.
Transcripts and audio are never logged or sent remotely. The app retains only
the latest successful dictation in memory for **Copy Last Dictation**.

## Project references

- [Product contract](purpose.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Models and engines](docs/MODELS.md)
- [Changelog](CHANGELOG.md)
- [Agent instructions](AGENTS.md)
- [MIT License](LICENSE)
