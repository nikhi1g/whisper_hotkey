# whisper_hotkey product contract

`whisper_hotkey` makes private local dictation available wherever macOS accepts
text while keeping its always-running cost as close to zero as practical.

The app has no Dock presence. A lightweight menu-bar item shows current state
and offers only immediate actions: setup, Settings, cancellation,
copying the last dictation, restart, and quit. Configuration pickers do not
expand the status menu.
Restart appears immediately before Quit, completes normal cleanup, and uses the
signed bundled one-shot launcher to reopen the installed app only after the old
process exits. It starts at
login as a visible macOS background item: a signed, one-shot Service Management
LaunchAgent opens the main app and immediately exits. The app can be started,
stopped, inspected, or disabled from the terminal. A one-time Setup window
handles Microphone, Accessibility, and Input Monitoring permissions. A separate
lazy Settings window owns persistent behavior and launch preferences;
it is not constructed until opened and has no polling task. Its lower-right
help button opens a transient, scrollable user guide. Its first table reports
the user's complete active path, explains the meaning of every selected
configuration value, and includes the actions available during that workflow.
Its second and final table contains only unselected keys, behaviors, models,
engines, decoding and processing choices, limits, themes, and startup behavior.
The tables rebuild from current state whenever the guide opens and add no idle
task. The guide header contains only its title, without explanatory subtitle
copy.
Settings and its User Guide use the selected visual theme on an opaque
background. Theme changes update the HUD, Settings, and an open guide
immediately without adding an idle task.
Settings behaves as a standard resizable macOS window: Command-W closes,
Command-M minimizes, and Control-Command-F or the green title-bar control
toggles full screen. Its document scrolls vertically when its content exceeds
the available window height.

The Settings **Dictation key** picker selects Right/Left Command, Shift,
Option, or Control, Caps Lock, or Fn/Globe and persists that choice.
Right Command is the default. A selected modifier remains usable in ordinary
shortcuts: combining it with another key or a mouse click passes through and
does not trigger dictation. Hold-to-talk is the default: a one-shot 150 ms dwell
arms capture without polling, after which the microphone starts. Releasing
after at least 250 milliseconds transcribes once and pastes at the current
focus. The selected Processing policy controls when the model loads and whether
hidden background decoding occurs. A faster tap does nothing.

The **Input behavior** picker offers explicit **Press and Hold**, **Toggle**, and
**Pause Mode** choices. The selected mode persists across launches. The three
choices appear as one-click segmented chips, avoiding an extra menu interaction.
Toggle changes the bare gesture to tap-to-start and tap-again-to-finish. Pause Mode
uses that same gesture and learns a bounded pause threshold from resumed,
sub-boundary pauses in the user's current cadence. It starts at 450 milliseconds
and remains between 300 and 750 milliseconds. One uninterrupted private WAV
retains the complete session while the same converted samples feed a small
current inference segment. A phrase boundary rotates only that segment: the
microphone and full recording remain uninterrupted while phrases are transcribed
and pasted in strict order. It reuses one loaded helper during the active
session. Every later phrase
receives a private, bounded 240-character
tail of the current session as its initial Whisper prompt so punctuation and
casing can follow the preceding phrase instead of treating every pause as a new
utterance. The prompt travels only over the owned helper's stdin, is never a
process argument, and does not grow with session length. The app retains no
audio worker at idle. With **After Recording** selected, it also retains no
model helper at idle. Full audio and inference segments are deleted on
stop, cancellation, failure, or termination. Caps Lock
cannot use Press and Hold because macOS exposes its lock-state changes rather
than a momentary hold/release pair; it can use Toggle or Pause Mode.
Its normal lock state is otherwise left to macOS. Escape is reserved as an
unambiguous abort action: during active dictation it stops capture, cancels
queued or active recognition, deletes the private audio, and inserts nothing.
It cannot be selected as the dictation trigger; a legacy stored Escape choice
migrates to Right Command. Return and keypad Enter act exactly like Send: they
finalize, insert, and then post one unmodified Return. These keys are consumed
only for an active dictation; ordinary Escape and Return remain untouched.
Cancellation and audio discard are also available from the menu.
Settings and Setup controls are disabled during active dictation so
they cannot steal the destination focus. The **Recording limit** picker persists
a choice from 30 seconds through one hour; ten minutes is the default, and
reaching the chosen limit finalizes automatically. Bare gestures are ignored
while a previous dictation is finishing.

The **Whisper model** picker persists Base English (default), Small English,
Medium English, or Large-v3 Turbo Q5. Its adjacent **Engine** selector offers
the default whisper.cpp Metal path, an optional whisper.cpp Core ML encoder
path, and an optional native WhisperKit Core ML and Neural Engine path. Only
the selected engine is loaded. The two Core ML choices require their verified
local artifacts and remain disabled when those artifacts are absent. They
perform no runtime download and fall back only by an explicit user selection,
never silently. Missing local model files remain visible
as muted model chips but cannot be selected; the app never downloads them. The
full model description is available from each chip's native help text. The
adjacent **Decoding** selector persists **Precision** or **Smart Decode**.
Precision is the default and always uses a beam width of five. Smart Decode is
available on the whisper.cpp engines. It first runs deterministic greedy
decoding with one candidate and no temperature fallback. It accepts that result
only when average token log probability, the fraction of weak tokens, maximum
no-speech probability, and repeated phrase detection all pass fixed,
benchmark-calibrated thresholds. An uncertain result is discarded and the same
audio is decoded once with the Precision beam. Confidence measurements are
ephemeral protocol metadata and are never logged or persisted. The command-line
failure path retains Precision decoding because it cannot run the adaptive
decision. WhisperKit retains its native decoding behavior and disables this
selector. Both whisper.cpp profiles use Metal and flash attention and give
whisper.cpp half of the Mac's logical CPUs up to an eight-thread cap. The
**Internal dictionary** stores up to 64 user-defined words or phrases as native
preference strings. Settings presents them as editable tokens: commas and Return
commit an entry and Backspace removes one. Entries are trimmed, capped, and
deduplicated case-insensitively. The complete saved list fits a precomputed
prompt of at most 320 characters and combines with the existing bounded Pause
Mode context.
Dictionary parsing happens only at launch or while Settings is edited; it adds
no idle task, process, model, or network work. The prompt remains local, travels
only through the owned helper's stdin, and is never logged or placed in process
arguments.
The persistent **Processing** selector sits directly below the model picker.
**After Recording** is the default: it loads and decodes only after capture
finishes for the lowest idle memory. **Model Ready** keeps the selected helper
and model loaded between dictations. **Decode While Speaking** also keeps one
model loaded, then privately decodes bounded inference segments concurrently
with ongoing capture. It prefers a detected pause after five seconds and rotates
at an eight-second hard bound so release leaves only a small final segment. Segment
recognition is serialized through one helper while whisper.cpp uses its normal
thread and Metal parallelism; multiple competing model processes are never
created. Partial transcripts remain hidden in memory and are inserted once
after the final segment. One uninterrupted private recording is retained as a
fallback if any background chunk fails. Pause Mode continues to own its existing
insert-at-pause behavior and takes precedence when selected. None of the three
processing choices keeps the microphone active or adds idle polling. Changing
the choice, model, or engine, quitting, restarting, or a failed helper cleans up
the owned process as required. Decode While Speaking explicitly trades a small
amount of cross-chunk context accuracy for lower release latency; the other two
choices retain full-recording context.
**Open at login** uses
the existing signed one-shot login service and respects explicit opt-out.
The bottom of Settings reports the current key, behavior, model, recording
limit, theme, and login state as compact read-only summary chips split across
two stable rows so every complete chip remains inside the window.
The **Theme** dropdown changes the floating HUD, Settings window, and User Guide
and persists immediately.
GitHub Dark Dimmed remains the default. The dropdown groups 24 restrained
presets under Dark and Light headings. The dark group contains GitHub Dark
Dimmed, Midnight Indigo, Graphite, Nord, Dracula, Solarized Dark, Forest,
Ocean, Rosé Pine, High Contrast, Tokyo Night, Catppuccin Mocha, Gruvbox Dark,
and Monokai. The light group contains Light Frost, GitHub Light, Solarized
Light, Nord Snow, Rosé Pine Dawn, Paper, Mint, Sky, Lavender, and High Contrast
Light. Existing saved identifiers remain valid. Theme application is
event-driven and adds no idle work.
The Theme row expands a native custom-theme editor inline within the scrollable
Settings document; it never opens a sheet or second window. Existing sections
shift down and the Settings window grows within the visible screen when room is
available, then returns to its prior size after Save or Cancel. A named preset
chooses Dark or Light classification plus Background, Text, and Accent colors
through standard macOS color wells or synchronized six-digit hex fields. A
miniature listening capsule updates immediately inside the editor and includes
the runtime HUD's top-center waiting marker. Saving validates and normalizes the
values, derives all secondary HUD colors, persists up to 32 named presets,
selects the saved preset, and applies it to the HUD, Settings, and User Guide.
Custom themes appear under a separate Custom heading.
Editing and theme loading happen only through Settings and add no idle worker,
file watcher, or network request.

The menu also offers **Copy Last Dictation** after the first successful local
transcription. It copies that latest transcript to the system clipboard as a
normal permanent copy. Only one transcript is retained in memory, it is replaced
by the next successful transcription, and it is discarded when the app exits.

Runtime UI consists of a non-activating badge beside the Accessibility caret
and the persistent menu-bar state icon. Standard selection ranges and
Chromium-style text markers are both used to locate the caret. Exact caret
geometry is feasible only when the destination app exposes one of those
Accessibility representations. When exposed, the focused element's frame is
captured in the same one-time query and the badge sits above the complete text
area when that boundary remains local to the caret. Terminal applications often
report the entire terminal surface as their focused field; oversized or distant
containers are ignored and the badge sits directly above the exact caret
instead. It flips below only at the top display edge. No role validation or
geometry polling is performed. If no Accessibility
geometry is available, the badge snapshots the current
pointer position once when recording begins and centers the Send/Enter button
under that pointer, enabling key, speak, click without pointer travel. The badge
uses a tight true-capsule silhouette with equal circular Stop and Send controls,
compact waveform and timer cells, and one immutable width and height through
listening and all following status states. While it remains undragged, a
recording-only Accessibility focus observer
snaps it to newly focused controls within or across applications; this is
event-driven and has no timer or idle activity. It never follows the pointer.
While listening, its waveform and timer surfaces form a drag handle; Stop and
Send retain independent button hitboxes. The first drag disables automatic
snapping and locks that origin for the rest of the session, including later
status states; the next session begins in automatic mode again. It never shrinks
for short status text or resizes during the session. Screen-edge clamping keeps
the complete badge visible. This behavior affects presentation only and never
validates or changes the paste destination. While listening, the compact
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
cancellation. The badge has no static outline, gradient, or panel shadow; its
opaque theme background alone separates it from the destination. During
listening, a small square accent marker rests at the capsule's top center,
identifying the waiting origin of the transcription activity trail. During
transcribing, the final waveform, elapsed time, and listening controls remain
frozen in place while the panel ignores input and a thin activity trail starts
from that same top-center point; the stationary marker disappears as the trail
traverses the complete perimeter clockwise.
Seven short segments fade progressively behind the leading segment and repeat
on one deterministic 0.92-second Core Animation cycle.
Leaving the transcribing state removes every animation immediately. This
presentation uses no polling task, changes no panel geometry, and retains a
Transcribing accessibility label.
The update task exists only while recording. The panel joins every application,
Space, and full-screen set;
the update task restores it if AppKit orders it out or leaves it on an inactive
Space or Stage Manager set. One panel is reused for the process lifetime so
repeated dictations cannot accumulate hidden WindowServer windows. Other badge
states show the perimeter activity trail, Busy, or an actionable error.
Transcribing, Busy, and No Speech Detected use the selected theme's background,
text, and accent colors. Actionable failures retain a red background so setup
or runtime problems remain distinct. The menu icon
distinguishes starting, ready, preparing, listening, transcribing, inserting,
unavailable, and failed states. Cancellation shows its distinct menu icon for
500 milliseconds, then returns to Ready without waiting for another dictation.
There is no live text preview or success confirmation. No Speech Detected clears
after 200 milliseconds; other errors remain visible for two seconds.

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

The app is English-only for version 3.0.5. Beyond the single in-memory last
dictation, it stores no history, performs no network requests, never downloads
models, and removes audio state after use. Logs contain state and errors only.
The separately invoked `run.sh` bootstrap may download selected documented
models, but installs them only after pinned SHA-256 verification.

Developer benchmarks are separate from the shipping application. The ignored
`Benchmarks/Data` tree can hold the checksum-verified LibriSpeech `test-clean`
and `test-other` splits used by OpenAI's Whisper evaluation. Benchmark results
contain aggregate timing and word-error measurements plus utterance identifiers
and numeric confidence measurements, never audio or transcript text. Benchmark
downloads and conversion tools are never invoked by the running app.
