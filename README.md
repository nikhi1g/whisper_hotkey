# whisper_hotkey

`whisper_hotkey` is a private, background macOS push-to-talk utility. Hold the
physical Right Command key, speak, and release to insert a local Base English
Whisper transcription at the current selection. A hold shorter than 250 ms is
discarded, Escape cancels, and a ten-minute hold finalizes automatically.

The app has no Dock icon, live transcript, or success notification. Its
menu-bar symbol changes for ready, listening, transcribing, inserting, setup,
and error states, and its menu offers Cancel Dictation, Open Setup, and Quit.
A non-activating Listening/Transcribing/Busy/Error badge also appears beside
the destination caret.

## Use

1. Focus an editable field and place the caret or select text to replace.
2. Hold Right Command while speaking.
3. Release Right Command and leave the destination focused until insertion.

The transcript replaces the release-time selection and adds boundary spaces
only when the neighboring text needs them. If the destination becomes unsafe or
unavailable while transcription runs, the transcript is placed on a one-paste
clipboard lease. Paste once with Command-V; the previous clipboard is then
restored when it is still safe to do so. A newer copy or cut always wins.

Password fields and macOS secure-input contexts fail closed. Some applications
that do not expose a stable editable Accessibility element may use the
one-paste fallback instead of automatic insertion.

## Setup and permissions

Install first, then open setup:

```sh
python3 build_app.py
python3 install.py
whisper_hotkey setup
```

The signed app requests three local macOS permissions:

- **Microphone** records only during an accepted Right Command hold.
- **Input Monitoring** observes and reserves the physical Right Command key,
  Escape while dictating, and clipboard shortcuts needed for safe restoration.
- **Accessibility** reads the focused editable element, selection, nearby text,
  and caret geometry, then posts one local Command-V for insertion.

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

Audio capture and model preload begin together on key-down. The model helper is
owned only for that dictation and is terminated after insertion, cancellation,
or failure. Idle operation is event-driven; no Whisper model, transcription
helper, polling worker, audio, or transcript history remains resident. The
menu-bar icon is updated only by state transitions.

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
