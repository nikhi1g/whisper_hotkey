# whisper_hotkey product contract

`whisper_hotkey` makes private local dictation available wherever macOS accepts
text while keeping its always-running cost as close to zero as practical.

The app has no Dock presence. A lightweight menu-bar item shows current state
and offers setup, cancellation, and quit controls without polling. It starts at
login as a visible macOS background item: a signed, one-shot Service Management
LaunchAgent opens the main app and immediately exits. The app can be started,
stopped, inspected, or disabled from the terminal. A one-time setup window
handles Microphone, Accessibility, and Input Monitoring permissions.

The menu's **Dictation Key** submenu selects Right/Left Command, Shift, Option,
or Control, Caps Lock, Escape, or Fn/Globe and persists that choice. Right
Command is the default. A selected modifier remains usable in ordinary
shortcuts: combining it with another key or a mouse click passes through and
does not trigger dictation. Hold-to-talk is the default: a one-shot 150 ms dwell
arms capture without polling, after which the microphone starts and the
installed Base English whisper.cpp model loads asynchronously. Releasing after
at least 250 milliseconds transcribes once, pastes at the current focus, and
unloads the model. A faster tap does nothing.

The dynamically named **[Key] Toggles Dictation** option changes the bare
gesture to tap-to-start and tap-again-to-finish, persists across launches, and
is visibly checked while selected. Caps Lock always uses toggle mode because
macOS exposes its lock-state changes rather than a momentary hold/release pair;
its normal lock state is otherwise left to macOS. Escape is a dedicated,
consumed trigger when selected, so cancellation remains available from the menu
instead of the same key. For every other selection, Escape cancels either mode.
Changing the selected key cancels an active dictation cleanly. A session lasting
ten minutes finalizes automatically. Bare gestures are ignored while a previous
dictation is finishing.

The menu also offers **Copy Last Dictation** after the first successful local
transcription. It copies that latest transcript to the system clipboard as a
normal permanent copy. Only one transcript is retained in memory, it is replaced
by the next successful transcription, and it is discarded when the app exits.

Runtime UI consists of a non-activating badge beside the Accessibility caret
and the persistent menu-bar state icon. Standard selection ranges and
Chromium-style text markers are both used to locate the caret. Exact caret
geometry is feasible only when the destination app exposes one of those
Accessibility representations. If it does not, the badge snapshots the current
pointer position when each runtime state begins; it does not poll or follow the
pointer. This fallback affects presentation only and never validates or changes
the paste destination. The badge shows Listening, Transcribing, Busy, or an
actionable error. The menu icon distinguishes starting, ready, preparing,
listening, transcribing, inserting, unavailable, and failed states. There is no
live text preview or success confirmation.

Insertion always posts one local Command-V to the currently focused application.
This naturally replaces the current selection in normal text controls. When
nearby text is exposed through Accessibility, contextually necessary boundary
spacing is added; only one character on either side is queried, and missing or
opaque information never blocks the paste. There is no text-role classification,
target validation, or alternate delivery path. Pasting into a non-text control
may do nothing or invoke that application's normal paste behavior. The
pasteboard transaction restores prior clipboard contents when possible.

The app is English-only for the MVP. Beyond the single in-memory last
dictation, it stores no history, performs no network requests, never downloads
models, and removes audio state after use. Logs contain state and errors only.
