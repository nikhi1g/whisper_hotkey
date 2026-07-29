# whisper_hotkey

Private, local, low-resource dictation for any macOS application, powered by
whisper.cpp.

`whisper_hotkey` is a background macOS dictation utility. By default,
hold the physical Right Command key, speak, and release to paste a local Base
English Whisper transcription at the current selection. Advanced Settings can
instead select either side of Command, Shift, Option, or Control, plus Caps Lock,
Escape, or Fn/Globe. A selected modifier remains normal when combined with
another key or a mouse click. A hold shorter than 250 ms is discarded, Escape
cancels unless it is the selected trigger. The persistent **Recording limit**
picker chooses an automatic stop from 30 seconds through one hour; ten minutes
is the default.

The app has no Dock icon, live transcript, or success notification. Its
menu-bar symbol changes for ready, listening, transcribing, inserting, setup,
and error states. Its compact menu keeps only immediate actions; persistent
key, gesture, model, duration, and Open at Login controls live in a separate
native **Advanced Settings…** window. While recording, the caret badge shows a
scrolling audio-reactive waveform, elapsed time, **Stop and Insert**, and
**Send**. Stop and Insert behaves like hotkey release; Send inserts and then
presses Return. The badge normally shows only elapsed time. In the final minute,
it switches to a remaining-time countdown whose text shifts from orange to red
and reveals the thin limit track; shorter limits use their full duration for the
warning. The badge uses a borderless flat surface with a restrained system
shadow and no gradients. Its timer and two circular controls sit directly beside
the waveform. Its compact outer frame keeps the same position, width, and height
while it changes from listening to transcribing or another status, so the badge
never jumps or collapses around shorter text.
The same microphone levels provide a lightweight voice-activity gate: sustained
speech proceeds to Whisper, while silence and brief key or click transients are
discarded as no speech instead of being decoded into a hallucinated phrase.
When an app exposes no text caret, pointer fallback centers the Send/Enter button
under the current pointer, so toggle-mode dictation can be completed with a
stationary click. The badge remains clamped inside the visible display.

## Quick start

Requirements: Apple Silicon, macOS 14+, Xcode Command Line Tools, and
[Homebrew](https://brew.sh).

```sh
git clone https://github.com/nikhi1g/whisper_hotkey.git
cd whisper_hotkey
./run.sh
```

The script installs Homebrew `whisper-cpp` when needed, downloads and verifies
Base English, builds/signs the app, installs it in `/Applications`, launches it,
and opens permission setup. With no Apple signing identity it clearly warns and
uses an ad-hoc local signature; macOS may then request permissions again after a
future rebuild.

Use `./run.sh --model small`, `medium`, or `turbo` for another model, or
`./run.sh --all-models` for all four. See [Models](docs/MODELS.md) and
[Architecture](docs/ARCHITECTURE.md).

## Use

1. Focus an editable field and place the caret or select text to replace.
2. Hold bare Right Command while speaking.
3. Release Right Command and leave the destination focused until insertion.

Open **Advanced Settings…**, choose a **Dictation key**, then choose **Press and
Hold** or **Toggle** under **Input behavior**. In Toggle mode, tap and release
the selected key once to start, speak while the badge waveform is active, then
tap and release it again to transcribe and insert. The badge's square button is
an equivalent stop-and-insert action; its arrow button additionally presses
Return after the paste succeeds. Ordinary typing and selected-modifier
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
the latest transcript to the system clipboard. It appears after a transcript
exists. Only that one transcript is held in memory; it is replaced on the next
dictation and discarded when the app quits.

The badge uses both standard macOS selection ranges and Chromium/Electron text
markers. Exact caret placement is not universally available: if an editor
exposes neither representation, the badge snapshots the current pointer
position once when recording begins. It keeps that exact initial origin through
listening and later status states, does not poll or track pointer movement, and
this visual fallback has no effect on where Command-V is posted. The badge
joins every application, Space, and full-screen set. If AppKit orders it out or
leaves it on an inactive Space or Stage Manager set, the active recording update
repairs its membership and periodically keeps it frontmost until recording ends.

## Setup and permissions

For manual installation instead of `run.sh`:

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

The menu-bar dropdown includes **Restart whisper_hotkey** immediately before
**Quit whisper_hotkey**. Restart performs the same bounded cleanup as Quit, then
the signed bundled launcher reopens that exact application bundle after the old
process has exited.

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

The installed runtime uses:

- `/opt/homebrew/bin/whisper-cli`
- `/opt/homebrew/opt/whisper-cpp/`
- `/opt/homebrew/opt/ggml/`
- `~/.cache/whisper/ggml-base.en.bin`

The Advanced Settings model picker offers:

- **Base English (Fast, 141 MB)** — installed default and smallest option.
- **Small English (More Accurate, 465 MB)** — installed.
- **Medium English (High Accuracy, 1.5 GB)** — selectable when its local file
  is present.
- **Large-v3 Turbo Q5 (Best Balance, 547 MB)** — selectable when its local file
  is present.

Missing models remain visible but disabled. The running app never downloads
weights; only the explicitly invoked bootstrap does.
The decoder keeps beam search at width five for accuracy, uses Metal and flash
attention, and assigns half the available logical CPUs up to eight threads.

In hold mode, audio capture and model preload begin together only after the
150 ms bare-key dwell. In toggle mode they begin after the first bare-key
release. The model helper is owned only for that dictation and is terminated
after insertion, cancellation, or failure. Idle operation is event-driven; no
Whisper model, transcription helper, polling worker, audio, or transcript
history remains resident. The menu-bar icon is updated only by state
transitions. The waveform reads the existing capture buffer at 20 Hz only while
recording; it adds no idle timer or second audio pipeline.

Temporary audio lives in a mode-0700 directory as a mode-0600 WAV and is removed
after the session. Logs contain state transitions and errors, never audio or
transcript text. No model is downloaded and no network request is made.

The Swift package requires macOS 14. Version 2.0.0 is source-distributed for
Apple Silicon because the helper links to the user's Homebrew whisper.cpp/GGML
installation. A notarized universal binary is not currently published.

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

`run.sh` is the explicit certificate-free source-install path: it supplies an
ad-hoc identity with a visible warning when no stable identity exists.

See [CHANGELOG.md](CHANGELOG.md). Licensed under the [MIT License](LICENSE).
