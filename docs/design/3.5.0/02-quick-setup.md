# 3.5.0 Quick Setup: Interaction Specification

Author: subagent A. This is the full design for the **Quick Setup** pane
named in `01-information-architecture.md`. It is a single scrolling SwiftUI
`Settings` pane, not a multi-step wizard, and it is not a one-shot modal: it
opens automatically on first run (replacing `SetupWindowController`) and
stays reachable afterward like any other pane, so a user whose permissions
got reset by macOS has one obvious place to come back to.

Everything below is a design spec, not Swift. Control implementation for
Quick Setup belongs to whichever subagent builds it; the recognition-preset
resolver and the `configurationEnabled` exception are interface requirements
on subagent B's state model (`01-information-architecture.md` §5).

## 1. Goal and success framing

A nontechnical user should be able to, in about a minute, without ever
seeing the words "engine," "model," or "decoding":

1. See what key starts dictation and how it activates.
2. Optionally change the key, the activation style, or the speed/accuracy
   preference.
3. Grant whatever macOS permissions are outstanding.
4. Actually dictate something and see it appear, proving the whole pipeline
   works end to end.

The pane is one continuous scroll, top to bottom, in this order: **Shortcut →
Activation → Recognition → Test Dictation → Readiness**. Readiness sits last
on purpose: a user with everything already granted (the common case after
first run) never has to look at it, while a user missing a permission sees it
right after trying the parts above, at the point where the test would
otherwise silently do nothing.

## 2. Shortcut and Activation

Two rows, always visible, always editable (not just on first run).

**Shortcut**
- Control: a menu/popup, same option set as today's `hotkeyPopup`.
- Options and display strings (unchanged from `HotkeyKey.displayName`):
  "Right Command," "Left Command," "Right Shift," "Left Shift," "Right
  Option," "Left Option," "Right Control," "Left Control," "Caps Lock,"
  "Fn / Globe."
- Default: **Right Option**.
- Caption beneath, secondary text: "This key starts dictation in any app."

**Activation**
- Control: a 3-way segmented control, same three values as today's
  `modeControl`.
- Options, each shown with its own one-line caption beneath the segmented
  control (caption text swaps to match the current selection):
  - **"Press and Hold"** — "Hold the key, speak, then let go to finish."
  - **"Toggle"** — "Press once to start. Press again when you're done."
  - **"Pause Mode"** — "Press once to start. It finishes on its own after you
    stop talking."
- Default: **Press and Hold**.
- Constraint carried over unchanged from `GlobalInputReducer`: **Caps Lock
  cannot use Press and Hold** (macOS reports it as a lock state, not a
  momentary press). When Shortcut = Caps Lock, the "Press and Hold" segment
  is disabled with tooltip *"Caps Lock can't be held — choose Toggle or Pause
  Mode."* If a user has Press and Hold selected and then changes Shortcut to
  Caps Lock, activation silently becomes Toggle (existing
  `GlobalInputReducer.setHotkey` behavior) — Quick Setup just reflects the
  resulting selection, it does not add its own dialog for this.

Both rows write directly to the same preferences Advanced Recognition and
Dictation Behavior would (`dictationHotkey`, `dictationMode`) — there is
exactly one home for each, per the IA table, and Quick Setup is it.

## 3. Recognition preference

**Control:** a 3-way segmented control, values **Fastest / Balanced / Most
Accurate**. Default: **Balanced**.

**Hard constraint:** none of the three options, their captions, tooltips, or
any surrounding copy on this pane may use the words "engine," "model," or
"decoding," or name a specific engine (Metal, Core ML, WhisperKit, Parakeet)
or a specific model file/size. Those words and choices exist only in
**Advanced Recognition**.

Exact captions (each shown beneath the segmented control for the current
selection):

- **Fastest** — "Replies almost instantly. Best on older Macs or when speed
  matters most."
- **Balanced** — "A strong mix of speed and accuracy. Recommended for most
  people."
- **Most Accurate** — "Takes a little longer to finish, for the most
  accurate result."

Below the segmented control, a single plain-text link, always visible but
visually secondary (not a button): **"Open Advanced Recognition to choose
the exact engine and model."** This is the one and only escape hatch out of
plain language, and it is a navigation link to the other pane, not a control
on this one.

### What each preset resolves to

This mapping is the *policy* Quick Setup requires; subagent B's resolver
function (`01-information-architecture.md` §5, item 1) is the implementation
of record. Two ground rules that shape the policy, both load-bearing for
"configure and confirm in about a minute":

- **Quick Setup never triggers a network request.** Base, Small, and
  Large-v3 Turbo Q5 ship inside the app bundle (`build_app.py`); only Medium
  is fetched on demand (`ModelDownloadCatalog`). None of the three presets
  may resolve to Medium, because that would silently turn "confirm it works
  in a minute" into "wait for a download," on a metered or offline connection
  a nontechnical user has no way to diagnose.
- **Quick Setup never resolves to Parakeet, WhisperKit, or the Core ML
  encoder.** All three are opt-in, artifact-gated engines that can be
  unavailable, mid-download, or require `run.sh`. The one engine guaranteed
  present with zero setup is `whisperCppMetal`. Presets stay there; a user
  who wants Parakeet's latency or WhisperKit's Neural Engine path opts in
  explicitly through Advanced Recognition, with full jargon, because at that
  point they've asked for it.

| Preset | Engine | Model | Decoding | Processing | Rationale |
|---|---|---|---|---|---|
| Fastest | `whisperCppMetal` | `baseEnglish` (always installed) | `adaptive` (Smart Decode) | `decodeWhileSpeaking` if ≥8 GB RAM, else `afterRecording` | Smallest model, fast greedy-first decoding, and decode-while-speaking together minimize time to finished text; both are the "trade a little cross-chunk context for speed" combination `purpose.md` already documents as an explicit, intentional tradeoff. |
| Balanced | `whisperCppMetal` | RAM-tiered pick from installed models — Large-v3 Turbo Q5 at ≥16 GB, Small at ≥8 GB, else Base | `precision` | `decodeWhileSpeaking` at ≥8 GB, else `afterRecording` | This is exactly `FirstRunPerformanceProfile.recommended`, already shipped and tuned. Balanced does not reinvent a policy; it names the existing one. |
| Most Accurate | `whisperCppMetal` | Best already-installed model, preferring `largeV3TurboQ5`, falling back to `smallEnglish`, then `baseEnglish` | `precision` (always 5-beam) | `afterRecording` | Full-recording context beats windowed decoding for accuracy per `purpose.md`; After Recording is the only processing mode with no cross-chunk tradeoff at all. Deliberately does **not** reach for Medium (the only non-bundled tier) — see network-request rule above. A user who specifically wants Medium's extra accuracy gets there through Advanced Recognition, where the download prompt and its size are shown honestly. |

Selecting a preset calls the resolver and writes through the same setters
Advanced Recognition uses (`selectEngine`, `selectModel`,
`selectDecodingProfile`, `selectProcessingMode`), so switching to Advanced
Recognition afterward shows exactly what Quick Setup just set — never a
second, disagreeing source of truth. If the user later changes Engine, Model,
Decoding, or Processing directly in Advanced Recognition, Quick Setup's
segmented control simply shows no selection highlighted (the current
combination no longer matches any preset's resolved tuple) rather than
guessing or fighting the user's explicit choice.

## 4. Dictation test

**Purpose:** an objective, self-contained proof that the whole pipeline —
permission grants, the configured shortcut, the resolved recognition
preference, and text insertion — works, without leaving the Settings window
or needing a second app open.

**Layout:**
- A short instruction line above an empty bordered text field. Instruction
  text is generated from the current Shortcut + Activation selection so it
  always matches what the user just configured:
  - Press and Hold: **"Click below, then hold {Shortcut} and speak. Let go
    when you're done."**
  - Toggle: **"Click below, then press {Shortcut} to start, and press it
    again when you're done."**
  - Pause Mode: **"Click below, then press {Shortcut} and start speaking. A
    pause finishes it for you."**
  ({Shortcut} substitutes the current `HotkeyKey.displayName`, e.g. "Right
  Option.")
- The field itself: placeholder text **"Your test dictation will appear
  here."**
- No separate "Start Test" button. The mechanism *is* the real, global
  hotkey — there is no simulated or fake path. To make the very first press
  land somewhere meaningful without forcing the user to click first, **the
  scratch field becomes the window's first responder whenever the Quick
  Setup pane is shown.** If the user clicks elsewhere in the pane or the app
  loses focus, the next dictation gesture follows normal focus rules like
  any other dictation in the OS — the field is a convenience default, not a
  forced target.

**On a successful insertion into the field:**
- A green, check-marked line appears directly beneath the field:
  **"Confirmed — dictation just inserted text here."**
- A small text-button beside it: **"Clear and Try Again"** — empties the
  field's content only (never persisted, never logged, consistent with
  `purpose.md`'s "audio and transcripts are ephemeral" rule; this is a
  scratch buffer, not a transcript history).

**On an attempt that produces no insertion** (cancelled, no speech detected,
or any runtime error already surfaced by the existing badge): Quick Setup
does **not** build a second, competing error system. The runtime badge is
still the authoritative status surface for what happened during the attempt
(Listening → Transcribing → error states are unchanged). Quick Setup adds
exactly one small, secondary-colored caption beneath the field, shown only if
an attempt completed and the field's contents did not change:
**"Didn't catch that — check the status badge, or try again."**

**Required exception to `configurationEnabled`:** every other control on
every pane disables while a dictation is active, exactly as today (so
dictation can't have its destination stolen out from under it). The test
field is the one deliberate exception — it must stay focused and interactive
for the *entire* test pane to make sense, since it is deliberately posing as
the destination. This is captured as interface requirement §5.3 in the IA
document; Quick Setup depends on it existing rather than special-casing
window-level focus itself.

## 5. Readiness, permissions, and problem states

A checklist, shown last, listing only items that are not already satisfied
once the pane has settled — i.e., an already-fully-set-up user scrolls past a
short list of green rows, not five rows demanding attention every time they
revisit the pane. (Green, already-satisfied rows still render, just compactly
— nothing disappears outright, so the state is always legible, matching the
"no live preview, but always show ground truth" spirit of the rest of the
app.)

| Row | Ready state | Not-ready state | Action button | Notes |
|---|---|---|---|---|
| **Microphone** | "Allowed" (green) | "Needed" (secondary) | **"Allow Microphone…"** — triggers the system TCC prompt directly, same as today's `requestMicrophone` action | |
| **Accessibility** | "Allowed" (green) | "Needed" (secondary) | **"Open System Settings…"** | Accessibility can't be granted programmatically; this deep-links exactly as `openAccessibilitySettings` does today |
| **Input Monitoring** | "Allowed" (green) | "Needed" (secondary) | **"Open System Settings…"** | Same pattern as Accessibility |
| **Dictation files** | "Ready" (green) | **"Missing — dictation can't run yet."** (red) | **"Use the Built-in Option"** (primary) plus a secondary text link **"Open Advanced Recognition to fix this manually."** | Folds today's separate "Selected model" and "Recognition helper" rows into one, since a nontechnical user does not need to know those are two different files. "Use the Built-in Option" resolves the Quick Setup preset to the guaranteed-present configuration (`whisperCppMetal` + `baseEnglish` + `precision` + `afterRecording`) with one click — this is the **only** repair action Quick Setup itself performs, and it never downloads anything. The secondary link is the escape hatch for a user who specifically wants to keep a broken custom Advanced Recognition combination and knows what they're doing. |

**Login Item** is deliberately *not* a checklist row (per
`01-information-architecture.md` §3 — Application owns the one authoritative
toggle). Quick Setup shows nothing about it in the common case. The single
exception, matching today's `automaticallyEnableLoginItemIfReady` behavior
exactly: once the four rows above are all green, registration is attempted
silently; if the result is `requiresApproval`, one line appears beneath the
checklist: **"whisper_hotkey needs your approval to open automatically at
login. [Open System Settings]"** — dismissible, and it does not block
anything else on the pane.

### Readiness banner

One line at the very top of the pane (above Shortcut), reflecting overall
state at a glance:

- **Nothing granted yet / mid-setup:** "Finish the steps below to start
  dictating. No audio or text ever leaves this Mac." (secondary color)
- **All four checklist rows green, test not yet run this session:**
  "Dictation is ready. Try it below to confirm." (secondary color)
- **All four rows green AND at least one successful test this session:**
  "Dictation is ready and confirmed working." (green)
- **Login approval pending** (in addition to whichever of the above applies):
  a second line, "Approve whisper_hotkey in Login Items to finish setup."
  (orange) — additive, never replaces the primary banner line.

## 6. What counts as successful completion

Two distinct signals, deliberately not merged into one:

1. **`setupCompleted` (persisted, `UserDefaults` key unchanged from today).**
   Flips true under the same condition as current
   `SetupWindowController.isReady && loginStatus == .enabled` — all four
   readiness rows green *and* the login item registered. This flag is what
   suppresses Quick Setup from forcing itself in front of the user on future
   launches, same as today's `showIfNeeded(force:)` contract. It is
   preserved exactly, not redesigned, because other code depends on its
   existing semantics and changing it silently would be a regression the
   task's own acceptance criteria warns against.
2. **"Confirmed working" (ephemeral, session-only, never persisted).** Set
   the first time a test dictation in §4's scratch field completes
   successfully. It only affects the banner copy in §5 — it is not required
   to close the window, dismiss Quick Setup, or use the app normally, because
   requiring an actual spoken test before letting someone proceed would
   undermine the "about a minute, low friction" goal for the (common) case
   where permissions were already fine and the user just wants to change the
   shortcut. It resets every time the pane is reopened, consistent with the
   app retaining no transcript state at rest.

Quick Setup is "done" the moment signal 1 is true. Signal 2 is the
felt, demonstrated proof the objective asks for, and the pane visibly
encourages it (the test sits directly above the readiness checklist, not
buried below it) without gating on it.

## 7. Consolidated user-visible strings

For quick reference during implementation — every literal string this
document introduces or carries over, in reading order:

```
Finish the steps below to start dictating. No audio or text ever leaves this Mac.
Dictation is ready. Try it below to confirm.
Dictation is ready and confirmed working.
Approve whisper_hotkey in Login Items to finish setup.

Shortcut
This key starts dictation in any app.

Activation
Press and Hold — Hold the key, speak, then let go to finish.
Toggle — Press once to start. Press again when you're done.
Pause Mode — Press once to start. It finishes on its own after you stop talking.
Caps Lock can't be held — choose Toggle or Pause Mode.

Recognition
Fastest — Replies almost instantly. Best on older Macs or when speed matters most.
Balanced — A strong mix of speed and accuracy. Recommended for most people.
Most Accurate — Takes a little longer to finish, for the most accurate result.
Open Advanced Recognition to choose the exact engine and model.

Click below, then hold {Shortcut} and speak. Let go when you're done.
Click below, then press {Shortcut} to start, and press it again when you're done.
Click below, then press {Shortcut} and start speaking. A pause finishes it for you.
Your test dictation will appear here.
Confirmed — dictation just inserted text here.
Clear and Try Again
Didn't catch that — check the status badge, or try again.

Microphone — Allowed / Needed — Allow Microphone…
Accessibility — Allowed / Needed — Open System Settings…
Input Monitoring — Allowed / Needed — Open System Settings…
Dictation files — Ready / Missing — dictation can't run yet. — Use the Built-in Option / Open Advanced Recognition to fix this manually.
whisper_hotkey needs your approval to open automatically at login. [Open System Settings]
```
