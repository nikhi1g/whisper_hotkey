# whisper_hotkey

`whisper_hotkey` is a private, background macOS dictation utility. By default,
hold the physical Right Command key, speak, and release to paste a local Base
English Whisper transcription at the current selection. Right Command remains a
normal modifier whenever it is combined with another key or a mouse click. A
hold shorter than 250 ms is discarded, Escape cancels, and a ten-minute session
finalizes automatically.

The app has no Dock icon, live transcript, or success notification. Its
menu-bar symbol changes for ready, listening, transcribing, inserting, setup,
and error states. Its menu offers Cancel Dictation, Open Setup, Quit, and the
persistent checked option **Right Command Toggles Dictation**. A non-activating
Listening/Transcribing/Busy/Error badge also appears beside the destination
caret.

## Use

1. Focus an editable field and place the caret or select text to replace.
2. Hold bare Right Command while speaking.
3. Release Right Command and leave the destination focused until insertion.

To dictate without holding the key, enable **Right Command Toggles Dictation**
in the menu-bar menu. Tap and release bare Right Command once to start, speak
while the caret-attached badge says Listening, then tap and release it again to
transcribe and insert. Ordinary typing and Right Command shortcuts remain
available between the two taps; Escape cancels.

In hold mode, a single cancellable 150 ms timer distinguishes a deliberate bare
hold from a shortcut. The microphone and model do not start during that dwell.
Pressing another key or clicking while Right Command is down cancels the pending
dictation gesture and passes the shortcut through normally. There is no polling
worker for this decision.

The transcript is always pasted once into whatever application is focused when
delivery occurs. In normal text controls this replaces the current selection.
Boundary spaces are added when Accessibility exposes enough surrounding text;
missing or opaque target information never blocks delivery. There is no delayed
clipboard fallback, so keep the intended text field focused until insertion.
Pasting into a non-text control may do nothing or invoke that application's
ordinary paste behavior.

After a transcription, the menu item **Copy Last Dictation** permanently copies
the latest transcript to the system clipboard. It is disabled until a transcript
exists. Only that one transcript is held in memory; it is replaced on the next
dictation and discarded when the app quits.

The badge uses both standard macOS selection ranges and Chromium/Electron text
markers. Exact caret placement is not universally available: if an editor
exposes neither representation, the app intentionally shows no approximate
pointer/field/corner badge. The changing menu-bar icon still reports state.

## Setup and permissions

Install first, then open setup:

```sh
python3 build_app.py
python3 install.py
whisper_hotkey setup
```

The signed app requests three local macOS permissions:

- **Microphone** records only after an accepted bare Right Command gesture.
- **Input Monitoring** distinguishes bare Right Command gestures from ordinary
  Right Command shortcuts and observes Escape while dictating.
- **Accessibility** reads exact caret geometry and at most one neighboring
  character on each side, then posts one local Command-V. It performs no target
  validation and does not gate delivery on a detected field.

macOS describes Accessibility as permission to “control this computer” because
it offers no narrower per-API grant. `whisper_hotkey` does not request Screen
Recording, Full Disk Access, or Automation permission, and it has no network
code.

The Login Item is a signed, bundled, one-shot LaunchAgent. It opens the main
headless app at login and exits; it is not a second persistent worker. macOS
shows this registration under **System Settings → General → Login Items &
Extensions → App Background Activity**.

## Terminal control

The installer places the app at `/Applications/whisper_hotkey.app` and the
controller at `~/bin/whisper_hotkey`.

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

`disable-login` prevents future login launches without stopping the current
process. Use `whisper_hotkey stop` when both behaviors are wanted.

## Local runtime and privacy

This build uses the already-installed local stack:

- `/opt/homebrew/bin/whisper-cli`
- `/opt/homebrew/opt/whisper-cpp/`
- `/opt/homebrew/opt/ggml/`
- `~/.cache/whisper/ggml-base.en.bin`

In hold mode, audio capture and model preload begin together only after the
150 ms bare-key dwell. In toggle mode they begin after the first bare-key
release. The model helper is owned only for that dictation and is terminated
after insertion, cancellation, or failure. Idle operation is event-driven; no
Whisper model, transcription helper, polling worker, audio, or transcript
history remains resident. The menu-bar icon is updated only by state
transitions.

Temporary audio lives in a mode-0700 directory as a mode-0600 WAV and is removed
after the session. Logs contain state transitions and errors, never audio or
transcript text. No model is downloaded and no network request is made.

The Swift package declares macOS 14 as its source-level minimum. The currently
installed Homebrew Whisper/GGML libraries were built for this Mac's current
macOS toolchain, so the produced bundle is a host-local MVP rather than a
portable release for older Macs.

## Development

```sh
swift build
swift test
```

The desktop sandbox may require `CLANG_MODULE_CACHE_PATH` and
`SWIFTPM_MODULECACHE_OVERRIDE` to point inside `.build/module-cache`.

The final bundle refuses ad-hoc signing. `build_app.py` selects a stable
Apple Development or Developer ID identity, signs every nested executable
before the outer app, and verifies the finished bundle. `install.py` safely
stops the old instance, atomically replaces the controller, installs the app,
verifies executable hashes, and relaunches it.
