# whisper_hotkey product contract

`whisper_hotkey` makes private local dictation available wherever macOS accepts
text while keeping its always-running cost as close to zero as practical.

The app has no Dock or menu-bar presence. It starts at login as a visible macOS
background item: a signed, one-shot Service Management LaunchAgent opens the
main app and immediately exits. The app can be started, stopped, inspected, or
disabled from the terminal. A one-time setup window handles Microphone,
Accessibility, and Input Monitoring permissions.

Right Command is reserved for push-to-talk. Pressing it starts microphone capture
and asynchronously loads the installed Base English whisper.cpp model. Releasing
it after at least 250 milliseconds transcribes once, inserts into the editable
field focused at release, and unloads the model. Escape cancels. A hold lasting
ten minutes finalizes automatically. Right Command presses are ignored while a
previous dictation is finishing.

Runtime UI is limited to a non-activating badge beside the Accessibility caret:
Listening, Transcribing, Busy, or an actionable error. There is no live text
preview or success confirmation.

Insertion replaces the selected text and adds only contextually necessary
boundary spacing. It uses a temporary pasteboard transaction for compatibility
and restores prior clipboard contents when possible. If the release-time field
is missing, secure, changed, or unsafe to target, the transcript becomes a
one-paste clipboard lease: after the next manual paste, the previous clipboard is
restored. A newer copy always wins.

The app is English-only for the MVP. It stores no history, performs no network
requests, never downloads models, and removes audio/transcript state after use
except while a one-paste lease is active. Logs contain state and errors only.
