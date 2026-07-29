# whisper_hotkey product contract

`whisper_hotkey` makes private local dictation available wherever macOS accepts
text while keeping its always-running cost as close to zero as practical.

The app has no Dock presence. A lightweight menu-bar item shows current state
and offers only immediate actions: setup, Advanced Settings, cancellation,
copying the last dictation, restart, and quit. Configuration pickers do not
expand the status menu.
Restart appears immediately before Quit, completes normal cleanup, and uses the
signed bundled one-shot launcher to reopen the installed app only after the old
process exits. It starts at
login as a visible macOS background item: a signed, one-shot Service Management
LaunchAgent opens the main app and immediately exits. The app can be started,
stopped, inspected, or disabled from the terminal. A one-time Setup window
handles Microphone, Accessibility, and Input Monitoring permissions. A separate
lazy Advanced Settings window owns persistent behavior and launch preferences;
it is not constructed until opened and has no polling task.

Advanced Settings' **Dictation key** picker selects Right/Left Command, Shift,
Option, or Control, Caps Lock, Escape, or Fn/Globe and persists that choice.
Right Command is the default. A selected modifier remains usable in ordinary
shortcuts: combining it with another key or a mouse click passes through and
does not trigger dictation. Hold-to-talk is the default: a one-shot 150 ms dwell
arms capture without polling, after which the microphone starts and the
installed Base English whisper.cpp model loads asynchronously. Releasing after
at least 250 milliseconds transcribes once, pastes at the current focus, and
unloads the model. A faster tap does nothing.

The **Input behavior** picker offers explicit **Press and Hold**, **Toggle**, and
**Pause Mode** choices. The selected mode persists across launches. Toggle
changes the bare gesture to tap-to-start and tap-again-to-finish. Pause Mode
uses that same gesture but treats roughly 850 milliseconds of silence following
confirmed speech as a phrase boundary. It immediately rotates to a fresh
private WAV, transcribes and pastes completed phrases in strict order, and keeps
listening until the user stops the session. It reuses one loaded helper during
the active session, but retains no model or audio worker at idle. Caps Lock
cannot use Press and Hold because macOS exposes its lock-state changes rather
than a momentary hold/release pair; it can use Toggle or Pause Mode.
its normal lock state is otherwise left to macOS. Escape is a dedicated,
consumed trigger when selected. During active dictation, Escape otherwise acts
exactly like Stop and Insert: it finalizes, transcribes, and inserts without
pressing Return. Return and keypad Enter act exactly like Send: they finalize,
insert, and then post one unmodified Return. Both key pairs are consumed only
for an active dictation; ordinary Escape and Return remain untouched. True
cancellation and audio discard remain available from the menu.
Advanced Settings and Setup controls are disabled during active dictation so
they cannot steal the destination focus. The **Recording limit** picker persists
a choice from 30 seconds through one hour; ten minutes is the default, and
reaching the chosen limit finalizes automatically. Bare gestures are ignored
while a previous dictation is finishing.

The **Whisper model** picker persists Base English (default), Small English,
Medium English, or Large-v3 Turbo Q5. Missing local model files remain visible
but cannot be selected; the app never downloads them. The accuracy-first decoder
keeps a beam width of five, uses Metal and flash attention, and gives whisper.cpp
half of the Mac's logical CPUs up to an eight-thread cap. **Open at login** uses
the existing signed one-shot login service and respects explicit opt-out.

The menu also offers **Copy Last Dictation** after the first successful local
transcription. It copies that latest transcript to the system clipboard as a
normal permanent copy. Only one transcript is retained in memory, it is replaced
by the next successful transcription, and it is discarded when the app exits.

Runtime UI consists of a non-activating badge beside the Accessibility caret
and the persistent menu-bar state icon. Standard selection ranges and
Chromium-style text markers are both used to locate the caret. Exact caret
geometry is feasible only when the destination app exposes one of those
Accessibility representations. If it does not, the badge snapshots the current
pointer position once when recording begins and centers the Send/Enter button
under that pointer, enabling key, speak, click without pointer travel. The badge
keeps that exact initial frame—including origin, width, and height—through
listening and all following status states; it does not poll, follow the pointer,
shrink for short status text, or resize during the session. Screen-edge clamping
keeps the complete badge visible. This fallback affects presentation only and
never validates or changes the paste destination. While listening, the compact
badge shows a sensitive scrolling 23-sample waveform read from the existing
audio callback at 20 Hz, elapsed time, a Stop and Insert button, and a Send
button. The recording limit stays hidden until its final minute; then elapsed
time becomes a remaining-time countdown, its text shifts continuously from
orange to red, and the thin limit track appears. Limits shorter than one minute
use their complete duration for that warning shift. Stop and Insert has the same
result as hotkey release. Send inserts successfully before posting an unmodified
Return. The same unsmoothed audio callback feeds a zero-idle-cost energy gate:
Whisper runs only after at least 100 milliseconds of contiguous speech-like
energy above -48 dBFS. The same detector supplies Pause Mode's trailing-silence
duration from the existing callback, without a second audio pass. Flat silence
and short mechanical transients are treated as no speech, so Whisper cannot
invent a phrase from an empty recording. The panel remains
non-activating, and controller clicks are excluded from modifier-chord
cancellation. The badge has no outline or gradient; a restrained system shadow
separates it from the destination.
The update task exists only while recording. The panel joins every application,
Space, and full-screen set;
the update task restores it if AppKit orders it out or leaves it on an inactive
Space or Stage Manager set. One panel is reused for the process lifetime so
repeated dictations cannot accumulate hidden WindowServer windows. Other badge
states show Transcribing, Busy, or an
actionable error. The menu icon
distinguishes starting, ready, preparing, listening, transcribing, inserting,
unavailable, and failed states. There is no live text preview or success
confirmation.

Insertion always posts one local Command-V to the currently focused application.
This naturally replaces the current selection in normal text controls. When
nearby text is exposed through Accessibility, contextually necessary boundary
spacing is added; only one character on either side is queried. When there is
no exposed following character, the insertion ends in exactly one space so the
next dictation or typed word is separated naturally. Missing or opaque
information never blocks the paste. There is no text-role classification,
target validation, or alternate delivery path. Pasting into a non-text control
may do nothing or invoke that application's normal paste behavior. The
pasteboard transaction restores prior clipboard contents when possible.

The app is English-only for version 2.0.0. Beyond the single in-memory last
dictation, it stores no history, performs no network requests, never downloads
models, and removes audio state after use. Logs contain state and errors only.
The separately invoked `run.sh` bootstrap may download selected documented
models, but installs them only after pinned SHA-256 verification.
