# whisper_hotkey

Private, local, low-resource dictation for any macOS application, powered by
whisper.cpp or optional native Core ML engines.

`whisper_hotkey` is a background macOS dictation utility. By default,
hold the physical Right Command key, speak, and release to paste a local Base
English Whisper transcription at the current selection. Settings can
instead select either side of Command, Shift, Option, or Control, plus Caps Lock
or Fn/Globe. A selected modifier remains normal when combined with another key
or a mouse click. A hold shorter than 250 ms is discarded. Escape always cancels
an active dictation and safely discards its pending audio and result. The
persistent **Recording limit**
picker chooses an automatic stop from 30 seconds through one hour; ten minutes
is the default.

The app has no Dock icon, live transcript, or success notification. Its
menu-bar symbol changes for ready, listening, transcribing, inserting, setup,
and error states. Its compact menu keeps only immediate actions; persistent
key, gesture, model, duration, and Open at Login controls live in a separate
native **Settings…** window. While recording, the caret badge shows a
scrolling audio-reactive waveform, elapsed time, **Stop and Insert**, and
**Send**. Stop and Insert behaves like hotkey release; Send inserts and then
presses Return. While dictating, Escape aborts and inserts nothing; Return or
keypad Enter is the keyboard shortcut for Send. These keys behave normally when
dictation is inactive. The question-mark button in the lower-right of Settings
opens the complete user guide. A compact row beside it summarizes the active
key, behavior, model, recording limit, theme, and login state. The Theme
dropdown offers GitHub Dark Dimmed plus ten varied HUD presets and applies the
choice immediately to the HUD, Settings, and opaque User Guide. The badge
normally shows only elapsed time. In the final
minute,
it switches to a remaining-time countdown whose text shifts from orange to red
and reveals the thin limit track; shorter limits use their full duration for the
warning. The badge uses a borderless flat surface with a restrained system
shadow and no gradients. Its timer and two circular controls sit directly beside
the waveform. Its compact outer frame keeps the same position, width, and height
while it changes from listening to transcribing or another status, so the badge
never jumps or collapses around shorter text. Drag its waveform or timer to move
it for the rest of the current dictation; the Stop and Send hitboxes remain
independently clickable. When Accessibility exposes the focused field, the badge
starts above that complete field rather than covering its text, flipping below
only when the top display edge leaves no room. Oversized terminal containers are
ignored in favor of the exact local caret, keeping the badge near the active
prompt instead of at the top of the terminal window. Until manually dragged, an
active badge follows focused text controls through an event-driven Accessibility
observer. Dragging locks its position for that dictation only.
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
and opens permission setup. A stable Apple code-signing identity is required so
privacy permissions remain attached to one stable application identity.

Use `./run.sh --model small`, `medium`, or `turbo` for another model, or
`./run.sh --all-models` for all four. See [Models](docs/MODELS.md) and
[Architecture](docs/ARCHITECTURE.md).

The default engine remains whisper.cpp Metal. Two verified, opt-in Apple
acceleration paths are available:

```sh
./run.sh --model turbo --engine coreml
./run.sh --model turbo --engine whisperkit
```

The first builds the pinned whisper.cpp helper with Core ML encoder support.
The second installs the pinned native WhisperKit model and tokenizer bundle.
Both choices appear under **Engine** beside **Model** in Settings only when
their required local artifacts are complete. The running app never downloads
an engine or model.

## Use

1. Focus an editable field and place the caret or select text to replace.
2. Hold bare Right Command while speaking.
3. Release Right Command and leave the destination focused until insertion.

Open **Settings…**, choose a **Dictation key**, then choose **Press and
Hold**, **Toggle**, or **Pause Mode** under **Input behavior**. In Toggle mode,
tap and release the selected key once to start, speak while the badge waveform
is active, then tap and release it again to transcribe and insert. Pause Mode
uses the same start/stop gesture but automatically transcribes and pastes each
phrase after a natural pause, then keeps listening. The boundary begins at
450 milliseconds and adapts between 300 and 750 milliseconds from the short
pauses in the user's current speaking cadence. This gives responsive live,
phrase-by-phrase typing without sending audio to a service. Each decode
receives only the final 240 characters of the current session as private local
context, helping Whisper preserve mid-sentence casing and punctuation across
pause boundaries without unbounded context growth. The badge's
square button is an equivalent stop-and-insert action; its arrow button
additionally presses Return after the final paste succeeds. Ordinary typing and
selected-modifier shortcuts remain available between the two taps.

Caps Lock cannot use Press and Hold because macOS reports lock-state changes
rather than a normal hold/release pair; its normal capitalization state remains
under macOS control. Escape is reserved for aborting active dictation and is not
available as a dictation trigger. An older stored Escape-trigger preference
safely falls back to Right Command.

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

The Settings model picker presents four one-click chips:

- **Base English (Fast, 141 MB)**: installed default and smallest option.
- **Small English (More Accurate, 465 MB)**: installed.
- **Medium English (High Accuracy, 1.5 GB)**: selectable when its local file
  is present.
- **Large-v3 Turbo Q5 (Best Balance, 547 MB)**: selectable when its local file
  is present.

Missing models remain visible but disabled. The running app never downloads
weights; only the explicitly invoked bootstrap does.
The adjacent Engine chips select one of three local paths:

- **Metal**: the existing whisper.cpp GPU and flash-attention path.
- **Core ML Encoder**: whisper.cpp decoding with its encoder on Core ML.
- **WhisperKit**: native Swift Core ML execution using Apple GPU and Neural
  Engine compute units.

Only the selected engine loads. A Core ML option is disabled when its matching
model artifacts are not installed, and an engine failure never silently changes
the user's selection.
The decoder keeps beam search at width five for accuracy, uses Metal and flash
attention, and assigns half the available logical CPUs up to eight threads.
The **Keep Model Ready** switch directly below the model chips defaults off.
Turning it on preloads the selected model and reuses its helper between
dictations for the shortest startup latency. This increases idle memory but
does not keep the microphone active or add polling. Turning it off, changing
models, quitting, or restarting releases the owned helper.

In hold mode, audio capture and model preload begin together only after the
150 ms bare-key dwell. In toggle and Pause modes they begin after the first
bare-key release. With Keep Model Ready off, a normal dictation owns the model
helper only until its one
insertion. Pause Mode reuses one helper and loaded model for its ordered phrase
chunks, then terminates it when the session stops, is cancelled, reaches its
limit, or fails. One uninterrupted private WAV retains the complete active
session. The existing audio callback writes a second lightweight inference
segment from the same converted samples; a pause rotates only that segment, so
the microphone never stops and no speech can fall into a restart gap. The full
recording and every segment are deleted when the session ends. Bounded text
context reaches the helper over private stdin, never as a process argument. Idle
operation is event-driven. With Keep Model Ready off, no Whisper model,
transcription helper, polling worker, audio, or transcript history remains
resident. With it on, only the selected helper and model remain resident. The
menu-bar icon is updated only by state
transitions. The waveform and pause detector read the existing capture callback
at 20 Hz only while recording; they add no idle timer or second audio pipeline.

Temporary audio lives in a mode-0700 directory as a mode-0600 WAV and is removed
after the session. Logs contain state transitions and errors, never audio or
transcript text. No model is downloaded and no network request is made.

The Swift package requires macOS 14. Version 2.6.0 is source-distributed for
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
