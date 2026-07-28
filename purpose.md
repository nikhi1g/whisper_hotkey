# whisper_hotkey product contract

`whisper_hotkey` makes private local dictation available wherever macOS accepts
text while keeping its always-running cost as close to zero as practical.

The app has no Dock presence. A lightweight menu-bar item shows current state
and offers setup, cancellation, and quit controls without polling. It starts at
login as a visible macOS background item: a signed, one-shot Service Management
LaunchAgent opens the main app and immediately exits. The app can be started,
stopped, inspected, or disabled from the terminal. A one-time setup window
handles Microphone, Accessibility, and Input Monitoring permissions.

Right Command remains a usable Command modifier. A bare Right Command gesture
controls dictation, while Right Command combined with another key or a mouse
click passes through as an ordinary macOS shortcut and does not trigger
dictation. Hold-to-talk is the default: a one-shot 150 ms dwell arms capture
without polling, after which the microphone starts and the installed Base
English whisper.cpp model loads asynchronously. Releasing after at least 250
milliseconds transcribes once, pastes at the current focus, and unloads the
model. A faster tap does nothing.

The menu-bar option **Right Command Toggles Dictation** changes the bare gesture
to tap-to-start and tap-again-to-finish, persists across launches, and is visibly
checked while selected. The toggle is decided on bare-key release so Command
shortcuts remain available in this mode too. Escape cancels either mode. A
session lasting ten minutes finalizes automatically. Bare gestures are ignored
while a previous dictation is finishing.

Runtime UI consists of a non-activating badge beside the Accessibility caret
and the persistent menu-bar state icon. Standard selection ranges and
Chromium-style text markers are both used to locate the caret. Exact caret
geometry is feasible only when the destination app exposes one of those
Accessibility representations. If it does not, no approximate pointer,
focused-field, or screen-corner badge is shown; the menu-bar icon remains the
authoritative state indicator. The badge shows Listening, Transcribing, Busy,
or an actionable error. The menu icon distinguishes starting, ready, preparing,
listening, transcribing, inserting, unavailable, and failed states. There is no
live text preview or success confirmation.

Insertion always posts one local Command-V to the currently focused application.
This naturally replaces the current selection in normal text controls. When
nearby text is exposed through Accessibility, contextually necessary boundary
spacing is added; missing or opaque target information never blocks the paste.
The user is responsible for keeping the intended destination focused. The
pasteboard transaction restores prior clipboard contents when possible and
does not retain a transcript for a later manual paste.

The app is English-only for the MVP. It stores no history, performs no network
requests, never downloads models, and removes audio/transcript state after use
without retaining a clipboard fallback. Logs contain state and errors only.
