# Global Dictation MVP — implementation plan

## Outcome

Build a small, local-only macOS menu-bar application that lets the user hold a
global hotkey, speak, see an unobtrusive live transcript, then release the key
to insert the final transcript into whichever editable control was focused
before dictation began.

The first milestone proves the interaction. It deliberately excludes a full
transcript history, accounts, cloud services, custom vocabulary, launch-at-login,
and production-grade text cleanup.

## What is known

- Target platform: macOS on Apple Silicon.
- Desired interaction: press and hold a global hotkey in any text-capable app;
  show live text preview; release to finish and insert text at the cursor.
- ASR must run locally. Existing machine context says `whisper.cpp` provides
  `whisper-cli` and `whisper-stream`, with local English Small (about 465 MB)
  and Base (about 141 MB) models and Metal acceleration available.
- The intended MVP may reuse `whisper-stream`; no cloud account, API key, or
  model download is required to establish the flow.
- This repository currently has no application source, project file, package
  manifest, build scripts, tests, or `purpose.md`. The initial Git commit is
  `f7b2f8b`.
- `AGENTS.md` describes a separate BookCLI library project and references paths
  that do not exist here. Its only directly applicable instruction is to commit
  every repository change. It should be replaced or narrowed before app code is
  added, rather than treating BookCLI rules as this app's architecture.

## MVP decisions

| Area | MVP choice | Why |
| --- | --- | --- |
| App shape | Native Swift/AppKit menu-bar app | Small, reliable access to macOS windows, permissions, and pasteboard. |
| Hotkey | One configurable push-to-talk chord; default decided before implementation | Global, hold/release semantics without a custom keyboard listener where possible. |
| Audio | `AVAudioEngine`, 16 kHz mono WAV in a private temporary directory | Matches the existing Whisper setup and makes cleanup predictable. |
| Recognition | Owned `whisper-stream` child process, Small English model by default | Fully local and leverages installed Metal-capable tooling. |
| Preview | Non-activating floating AppKit panel | Visible without stealing focus from the insertion target. |
| Insertion | Capture focused app; try Accessibility value replacement, fall back to restoring the pasteboard and sending Cmd-V | Works broadly while preserving the user's clipboard. |
| Privacy | No network calls and no saved audio/transcript history | The safest useful first release. |

## Scope and acceptance criteria

1. **Shell and permissions**
   - App launches into the menu bar and explains microphone and Accessibility
     requirements.
   - It reports actionable permission state rather than silently failing.

2. **Push-to-talk lifecycle**
   - Holding the chosen shortcut begins capture once; repeated key events do not
     create multiple sessions.
   - Releasing it stops capture, terminates owned recognition cleanly, and
     deletes temporary audio on every outcome (success, cancellation, failure).
   - Escape cancels and inserts nothing.

3. **Live preview**
   - A compact overlay reflects partial `whisper-stream` output while speaking.
   - The overlay does not become key and remains readable over the active app.

4. **Final insertion**
   - Releasing inserts a trimmed final transcript into TextEdit and at least one
     browser/editor field.
   - Empty transcripts and secure/password fields insert nothing.
   - Clipboard fallback restores the prior clipboard contents when feasible and
     clearly reports insertion failure.

5. **Minimal control surface**
   - Menu items: status, choose hotkey, choose Small/Base model, test
     permissions, and Quit.
   - Persist only these device-local preferences.

## Delivery sequence

### Phase 0 — establish the project boundary

- Replace the inherited BookCLI-specific `AGENTS.md` with concise dictation-app
  instructions and add a `.gitignore` for Xcode build products, user settings,
  recordings, and models.
- Create an Xcode-native Swift/AppKit app project and a lightweight test target.
- Add `Info.plist` microphone usage text and a deterministic developer setup
  note listing the Whisper executable/model locations.

**Exit:** the empty menu-bar app builds, launches, and has no network dependency.

### Phase 1 — audio and recognition spike

- Add an `AudioRecorder` with explicit state transitions: idle → recording →
  finalizing → idle/cancelled.
- Add a `WhisperProcess` that owns one process group, parses line-oriented
  partial output, captures the final text, and has bounded TERM-to-KILL cleanup.
- Feed live partials to a simple status view before introducing the overlay.

**Exit:** pressing an in-app test control produces partial and final local
transcripts; no helper remains after stop/cancel.

### Phase 2 — system interaction MVP

- Register the hold-to-talk hotkey, retaining an in-app fallback if the OS
  rejects the chosen shortcut.
- Record the foreground app/paste target immediately before recording.
- Build the non-activating preview overlay and connect hold/release/cancel.
- Implement insertion, first with an Accessibility-capable focused element and
  then a carefully scoped pasteboard/Cmd-V fallback.

**Exit:** TextEdit end-to-end demo works: hold → preview → release → text appears
at the original caret, with the app never taking focus.

### Phase 3 — hardening the MVP

- Handle focus changes, no editable target, denied permissions, process startup
  failure, and secure fields without leaking text or overwriting the clipboard.
- Persist the hotkey and model selection.
- Add focused unit tests for the recording/recognition state machine and manual
  smoke checks for TextEdit, a browser field, and a terminal.

**Exit:** a signed-local developer build can be used daily for short dictation.

## Architecture sketch

```text
Global hotkey (down/up)
        │
        ▼
DictationCoordinator ── captures focused target ──► PreviewPanel
        │                         │                    ▲
        ├──► AudioRecorder ─► temporary WAV            │ partial text
        │                         │                    │
        └──► WhisperProcess ◄─────┴────────────────────┘
                  │ final text
                  ▼
           TextInserter ──► Accessibility API ──► pasteboard/Cmd-V fallback
```

## Risks to validate early

- The exact output behavior and command-line flags of the locally installed
  `whisper-stream` are not yet verified; Phase 1 should test it before the UI is
  built around its output.
- macOS versions and applications vary in accessibility support. Paste fallback
  is likely essential; secure-entry behavior must be conservative.
- Global shortcut registration may conflict with system or third-party shortcuts.
  The app needs a visible conflict state and reconfiguration path.
- Whisper Small may be too slow for satisfying partials on some hardware. Base
  is the fallback benchmark; the MVP should measure first-token and final latency
  before choosing the default permanently.

## Decisions still needed from you

1. Preferred default hotkey (for example, Right Option, or a chord such as
   Control-Option-Space). A modifier-only key is ergonomic but may require a
   lower-level event monitor than a normal chord.
2. Should release **insert immediately** (recommended), or should it leave the
   final text in the preview for confirmation/editing first?
3. Is English-only acceptable for the first MVP? The known installed models are
   English models.
4. What minimum macOS version should the app support?
5. May the MVP use the clipboard as an insertion fallback? It can restore normal
   text content, but there are edge cases for rich/multi-item clipboard data.
