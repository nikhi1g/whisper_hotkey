# whisper_hotkey

`whisper_hotkey` is a private, background macOS dictation utility. By default,
hold the physical Right Command key, speak, and release to paste a local Base
English Whisper transcription at the current selection. The menu can instead
select either side of Command, Shift, Option, or Control, plus Caps Lock,
Escape, or Fn/Globe. A selected modifier remains normal when combined with
another key or a mouse click. A hold shorter than 250 ms is discarded, Escape
cancels unless it is the selected trigger. The persistent **Recording Limit**
submenu chooses an automatic stop from 30 seconds through one hour; ten minutes
is the default.

The app has no Dock icon, live transcript, or success notification. Its
menu-bar symbol changes for ready, listening, transcribing, inserting, setup,
and error states. Its menu includes persistent checked controls for the gesture,
dictation key, local Whisper model, and recording limit. While recording, the
caret badge shows a small audio-reactive waveform and elapsed time. In the final
30 seconds it switches to elapsed/limit and pulses orange toward deep red.

## Use

1. Focus an editable field and place the caret or select text to replace.
2. Hold bare Right Command while speaking.
3. Release Right Command and leave the destination focused until insertion.

Choose a trigger from **Dictation Key**. To dictate without holding it, enable
the dynamically named **[Key] Toggles Dictation** item. Tap and release the
selected key once to start, speak while the badge says Listening, then tap and
release it again to transcribe and insert. Ordinary typing and selected-modifier
shortcuts remain available between the two taps.

Caps Lock always uses toggle mode because macOS reports lock-state changes
rather than a normal hold/release pair; its normal capitalization state remains
under macOS control. Selecting Escape makes it a dedicated consumed trigger, so
use **Cancel Dictation** in the menu to cancel. For every other trigger, Escape
continues to cancel.

In hold mode, a single cancellable 150 ms timer distinguishes a deliberate bare
hold from a shortcut. The microphone and model do not start during that dwell.
Pressing another key or clicking while a selected modifier is down cancels the
pending dictation gesture and passes the shortcut through normally. There is no
polling worker for this decision.

The transcript is always pasted once into whatever application is focused when
delivery occurs. In normal text controls this replaces the current selection.
Boundary spaces are added when Accessibility exposes enough surrounding text.
At the end of a field, or when the following character is opaque, every
dictation ends with exactly one space so the next dictation or typed word does
not run into it. Missing target information never blocks delivery. There is no
delayed clipboard fallback, so keep the intended text field focused until
insertion.
Pasting into a non-text control may do nothing or invoke that application's
ordinary paste behavior.

After a transcription, the menu item **Copy Last Dictation** permanently copies
the latest transcript to the system clipboard. It is disabled until a transcript
exists. Only that one transcript is held in memory; it is replaced on the next
dictation and discarded when the app quits.

The badge uses both standard macOS selection ranges and Chromium/Electron text
markers. Exact caret placement is not universally available: if an editor
exposes neither representation, the badge snapshots the current pointer
position for that state instead. It does not poll or track pointer movement,
and this visual fallback has no effect on where Command-V is posted.

## Setup and permissions

Install first, then open setup:

```sh
python3 build_app.py
python3 install.py
whisper_hotkey setup
```

The signed app requests three local macOS permissions:

- **Microphone** records only after an accepted bare dictation-key gesture.
- **Input Monitoring** distinguishes bare trigger gestures from ordinary
  modifier shortcuts and observes Escape while dictating.
- **Accessibility** reads exact caret geometry and at most one neighboring
  character on each side, permits the intercepting event tap that preserves
  bare-key semantics, and posts one local Command-V. It performs no target
  validation and does not gate delivery on a detected field.

macOS describes Accessibility as permission to “control this computer” because
it offers no narrower per-API grant. `whisper_hotkey` does not request Screen
Recording, Full Disk Access, or Automation permission, and it has no network
code. All three requested permissions remain necessary for the current
hold/toggle, local recording, context spacing, and unconditional paste behavior.

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

The model menu offers:

- **Base English (Fast, 141 MB)** — installed default and smallest option.
- **Small English (More Accurate, 465 MB)** — installed.
- **Medium English (High Accuracy, 1.5 GB)** — selectable when its local file
  is present.
- **Large-v3 Turbo Q5 (Best Balance, 547 MB)** — selectable when its local file
  is present.

Missing models remain visible but disabled. The app never downloads weights.
The decoder keeps beam search at width five for accuracy, uses Metal and flash
attention, and assigns half the available logical CPUs up to eight threads.

In hold mode, audio capture and model preload begin together only after the
150 ms bare-key dwell. In toggle mode they begin after the first bare-key
release. The model helper is owned only for that dictation and is terminated
after insertion, cancellation, or failure. Idle operation is event-driven; no
Whisper model, transcription helper, polling worker, audio, or transcript
history remains resident. The menu-bar icon is updated only by state
transitions. The waveform reads the existing capture buffer at 10 Hz only while
recording; it adds no idle timer or second audio pipeline.

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
