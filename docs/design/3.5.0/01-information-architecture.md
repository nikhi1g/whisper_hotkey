# 3.5.0 Settings: Information Architecture

Author: subagent A (IA + Quick Setup). Scope: the full settings inventory, its
new hierarchy, and placement decisions. Control design for Advanced Recognition
belongs to subagent B; visual system and Application/Appearance control design
belong to subagent C. This document places every setting; it does not design
their SwiftUI controls except where noted as "spec only" for Quick Setup, which
is this subagent's own surface (detailed in `02-quick-setup.md`).

## 0. What 3.5.0 replaces

Two AppKit windows disappear outright:

- `AdvancedSettingsWindowController` — INPUT, RECOGNITION, APPEARANCE, STARTUP
  sections plus its footer (summary chips, version, GitHub link, help button).
- `SetupWindowController` — the one-time permissions window (Microphone,
  Accessibility, Input Monitoring, Selected model, Recognition helper, Login
  Item).

Both are replaced by one native SwiftUI `Settings` scene with five panes:
**Quick Setup, Advanced Recognition, Dictation Behavior, Application,
Appearance**. `SetupWindowController` is fully **subsumed** by Quick Setup —
see §3 for the reasoning — so there is no longer a separate permissions
window at all; first run opens straight into the Quick Setup pane.

## 1. Complete setting inventory

Every row, control, and persisted value in the current window, mapped to its
new pane. "Persisted" lists the storage this design assumes carries forward
unchanged — subagent B's settings state model owns actually wiring it, this
is the contract this IA depends on.

| # | Current label / control | Type & values | Default | Persisted key | New pane | New label | Priority | Default visibility |
|---|---|---|---|---|---|---|---|---|
| 1 | Dictation key (`hotkeyPopup`) | `HotkeyKey`, 10 cases (Right/Left ⌘, Right/Left ⇧, Right/Left ⌥, Right/Left ⌃, Caps Lock, Fn/Globe) | Right Option | `dictationHotkey` | **Quick Setup** | Shortcut | Primary | Always shown |
| 2 | Behavior (`modeControl`) | `HotkeyActivationMode`: Press and Hold / Toggle / Pause Mode | Press and Hold (forced to Toggle if key is Caps Lock) | `dictationMode` | **Quick Setup** | Activation | Primary | Always shown |
| 3 | Engine (`engineControl`) | `RecognitionEngine`: Metal / Core ML Encoder / WhisperKit / Parakeet | Metal (`whisperCppMetal`) | `recognitionEngine` | **Advanced Recognition** | Engine | Secondary | Always shown; segments for engines whose local artifacts are missing render disabled with a tooltip |
| 4 | Model (`modelControl`, whisper family) | `DictationModel`: Base / Small / Medium / Large-v3 Turbo Q5 | Base English (RAM-tiered on first run; existing choice never overwritten) | `dictationModel` | **Advanced Recognition** | Model | Secondary | Shown when Engine ≠ Parakeet; chips for uninstalled models render disabled with a tooltip |
| 5 | Model (`modelControl`, Parakeet family) | `ParakeetVariant`: Fast / Accurate | Accurate | `parakeetModel` | **Advanced Recognition** | Model | Secondary | Shown when Engine = Parakeet, replacing row 4's chips in place |
| 6 | Decoding (`decodingControl`) | `DecodingProfile`: Precision / Smart Decode | Precision | `decodingProfile` | **Advanced Recognition** | Decoding | Tertiary | Hidden outright when the engine has no beam search (WhisperKit, Parakeet) — same rule as today, not greyed out |
| 7 | Processing (`processingModeControl`) | `ModelProcessingMode`: After Recording / Model Ready / Decode While Speaking | RAM-tiered on first run (After Recording below 8 GB, else Decode While Speaking); existing choice never overwritten | `modelProcessingMode` (+ legacy `keepModelReady` mirror) | **Advanced Recognition** | Processing | Secondary | Always shown |
| 8 | Internal dictionary (Add draft + Existing list) | `[String]`, ≤64 entries, ≤80 chars each, ≤320-char generated prompt | Empty | `internalDictionary` | **Dictation Behavior** | Custom Words | Secondary | Always shown; Add/Existing controls disable (not hide) when the engine has no prompt conditioning (Parakeet), matching today's rule |
| 9 | Recording limit (`recordingLimitPopup`) | `RecordingLimit`: 30 sec – 1 hour, 8 steps | 10 Minutes | `recordingLimit` | **Dictation Behavior** | Recording Limit | Tertiary | Always shown |
| 10 | Copy Last Dictation (`keepLatestDictationToggle`) | `Bool` | On | `keepLatestDictation` | **Dictation Behavior** | Keep Last Dictation | Secondary | Always shown |
| 11 | Theme (`themePopup`) | `BadgeThemeSelection`: 24 built-in themes (14 dark / 10 light) grouped by mode, plus custom themes | GitHub Dark Dimmed | `badgeTheme` | **Appearance** | Theme | Primary (for this pane) | Always shown |
| 12 | New / Edit theme (inline editor) | `CustomBadgeTheme`: name, mode, background/text/accent hex | — | `customBadgeThemes`, ≤32 | **Appearance** | New Theme / Edit Theme | Secondary | Edit only enabled when the current selection is a custom theme, same as today |
| 13 | Open at login (`loginItemToggle` + status + "Open Settings") | `SMAppService` registration state (`LoginItemStatus`), not a `UserDefaults` pref | Auto-registered once setup is fully ready; explicit opt-out respected | n/a (Service Management) | **Application** | Open at Login | Primary (for this pane) | Always shown |
| 14 | Check for Updates / Update and Restart (`checkForUpdatesButton`) | Action, button title switches on `SoftwareUpdateStatus.available(_, installable: true)` | — | n/a | **Application** | Check for Updates / Update and Restart | Primary (for this pane) | Always shown |
| 15 | Check automatically (`automaticUpdateCheckToggle`) | `Bool` | Off | `automaticallyChecksForUpdates` | **Application** | Check Automatically | Secondary | Always shown |
| 16 | Software update status label | Read-only text (`SoftwareUpdateStatus.displayText`) | — | n/a | **Application** | (status text beside the Updates control) | — | Shown only while non-idle |
| 17 | Version label | Read-only text | — | n/a | **Application** | Version | — | Always shown |
| 18 | GitHub ↗ button | Action, opens repository URL | — | n/a | **Application** | View on GitHub | — | Always shown |
| 19 | Help button → User Guide popover | Action, opens the two-table reference (active path, then everything else) | — | n/a | **Application** | User Guide | — | Always shown; content regenerates from live state each open, per `purpose.md` |
| 20 | Summary chips (hotkey/mode/model/limit/theme/login, footer) | Read-only | — | n/a | **removed** | — | — | n/a — see §4 |
| 21 | Setup: Microphone row | Permission status + "Request" action | — | n/a (TCC) | **Quick Setup** | Microphone | Primary | Always shown |
| 22 | Setup: Accessibility row | Permission status + "Open Settings" action | — | n/a (TCC) | **Quick Setup** | Accessibility | Primary | Always shown |
| 23 | Setup: Input Monitoring row | Permission status + "Open Settings" action | — | n/a (TCC) | **Quick Setup** | Input Monitoring | Primary | Always shown |
| 24 | Setup: Selected model row | Availability status + "Show Location" action, label switches on engine | — | n/a (derived) | **Quick Setup** | (folded into "Dictation is ready" readiness row) | Primary | Always shown; see `02-quick-setup.md` §4 |
| 25 | Setup: Recognition helper row | Availability status + "Show Location" action, label switches on engine | — | n/a (derived) | **Quick Setup** | (folded into "Dictation is ready" readiness row) | Primary | Always shown; see `02-quick-setup.md` §4 |
| 26 | Setup: Login Item row | Same control as row 13, duplicated | — | n/a | **removed as a duplicate control** | — | — | Quick Setup references login status passively; the one authoritative toggle is Application (row 13). See §4. |
| 27 | Setup: detail/status line | Read-only text, switches on readiness | — | n/a | **Quick Setup** | (readiness banner) | Primary | Always shown; see `02-quick-setup.md` §5 |

Rows 1–19 come from `AdvancedSettingsWindowController`; rows 20–27 come from
`SetupWindowController`. That is every control in both files. Nothing is
dropped without the explicit call-outs in §4.

### New setting this redesign adds

- **Recognition preference** (Fastest / Balanced / Most Accurate) —
  **Quick Setup**, Primary, always shown. Not a persisted preference of its
  own; it is a plain-language selector that resolves to a concrete
  `(engine, model, decodingProfile, processingMode)` tuple. Full specification
  in `02-quick-setup.md` §3. The resolution function is an **interface
  requirement on subagent B's settings state model** (§5).

## 2. Pane hierarchy

```
Settings
├── Quick Setup            (this doc's owner; full spec in 02-quick-setup.md)
│    ├── Shortcut                          [setting 1]
│    ├── Activation                        [setting 2]
│    ├── Recognition preference            [new setting]
│    ├── Dictation test
│    └── Readiness / permissions           [settings 21–25, 27]
│
├── Advanced Recognition   (subagent B owns controls + state model)
│    ├── Engine                            [setting 3]
│    ├── Model                             [settings 4–5]
│    ├── Decoding                          [setting 6]
│    └── Processing                        [setting 7]
│
├── Dictation Behavior     (placement only; control design open — see §6)
│    ├── Custom Words (internal dictionary) [setting 8]
│    ├── Recording Limit                    [setting 9]
│    └── Keep Last Dictation                [setting 10]
│
├── Application            (subagent C owns controls)
│    ├── Open at Login                      [setting 13]
│    ├── Updates (check / automatic / status) [settings 14–16]
│    ├── Version                            [setting 17]
│    ├── View on GitHub                     [setting 18]
│    └── User Guide                         [setting 19]
│
└── Appearance             (subagent C owns controls)
     ├── Theme                              [setting 11]
     └── Custom theme editor                [setting 12]
```

Every one of settings 1–19 and 21–27 (minus the two explicit removals in §4)
appears in exactly one pane above.

## 3. Why Quick Setup subsumes `SetupWindowController` rather than linking to it

`SetupWindowController` today does two things at once: it gates first use on
three TCC permissions plus two derived readiness checks (model file present,
helper present), and it doubles as the only place a user can re-check
permission status later (its `showSetup()` entry point is reachable after
first run too, e.g. after macOS resets a permission).

3.5.0 folds this into Quick Setup rather than keeping it separate because:

- The task objective is "configure dictation and confirm it works in about a
  minute." Permission grants are not optional prerequisites bolted on before
  configuration — they are load-bearing parts of "confirm it works." Splitting
  them into a different window means the user configures a shortcut and a
  recognition preference, then has to go find a *second* place to learn the
  microphone was never granted, which is exactly the kind of dead end a
  nontechnical user gets stuck on.
- `SetupWindowController`'s own detail line already conditionally reports
  readiness ("Ready. Use the selected dictation key anywhere...") using the
  *same* hotkey that Quick Setup configures. The two windows were already
  describing one flow through two doors.
- Because Quick Setup is a permanent Settings pane (not a one-shot modal),
  "link to Setup" would mean shipping a second, separate way to view
  permission status that can drift from the first. One pane, one status
  model, no drift.

The one row that does **not** fully collapse into Quick Setup is Login Item
(setting 13/26): today it appears in *both* windows with independent toggle
logic. In 3.5.0 there is exactly one authoritative Login Item control
(Application, §1 row 13). Quick Setup keeps the passive, read-only side effect
that already exists today — `automaticallyEnableLoginItemIfReady` fires
silently once readiness is reached — and surfaces it only as a one-line
mention when it needs the user's attention (the "requires approval" case).
This is detailed in `02-quick-setup.md` §5.

## 4. Explicit removals

| Removed item | Justification |
|---|---|
| Footer summary chips (setting 20: hotkey/mode/model/limit/theme/login as read-only pills) | These existed to compress AdvancedSettingsWindowController's entire state into one glance because everything else lived in collapsible, easy-to-lose sections of a single dense window. A tabbed `Settings` scene makes each pane's current values visible at the top of that pane instead (Advanced Recognition shows its own engine/model/decoding/processing; Dictation Behavior shows its own limit/dictionary/retention; Appearance shows its own theme). A cross-pane summary strip has no SwiftUI `Settings` scene equivalent worth building and duplicates information the user already sees one click away. This is a real removal, not a relocation — flagged per the acceptance criteria. |
| Setup window's duplicate Login Item row (setting 26) | Not a removal of the *setting* — the setting survives as Application row 13 — but the second, independently-toggled control surface is removed. Two live toggles for one `SMAppService` registration is a correctness risk (they can show stale state relative to each other) as well as an IA smell: one persistent fact belongs in one place. |

No persisted preference is dropped. Every `UserDefaults` key in
`WhisperHotkeyPreferenceKeys` and every ad hoc key (`dictationHotkey`,
`dictationMode`) keeps a home in the table in §1.

## 5. Interface requirements on subagent B (Advanced Recognition + settings state model)

These are contracts Quick Setup depends on; B designs and owns the
implementation.

1. **Recognition preset resolver.** A pure function, shape:
   `resolve(preset: .fastest | .balanced | .mostAccurate, availableModels: Set<DictationModel>, availableEngines: Set<RecognitionEngine>, physicalMemory: UInt64) -> (engine: RecognitionEngine, model: DictationModel, decodingProfile: DecodingProfile, processingMode: ModelProcessingMode)`.
   Quick Setup calls this once per preset selection and writes the result
   through the same setters Advanced Recognition uses
   (`selectEngine`, `selectModel`, `selectDecodingProfile`,
   `selectProcessingMode`) so the two panes can never disagree about what is
   active. The policy each preset should encode is specified in
   `02-quick-setup.md` §3 — Quick Setup never resolves to Parakeet, WhisperKit,
   or the Core ML encoder, and never triggers a network request, so the
   resolver must restrict itself to `whisperCppMetal` with a model already
   verified as installed.
2. **A single source of truth for "is recognition ready."** Quick Setup's
   readiness row (§1, folded settings 24–25) needs one boolean-plus-reason
   signal — "the currently selected engine/model/helper combination is usable
   right now" — rather than re-deriving it from `availableModels` /
   `availableEngines` itself. This already exists in spirit as
   `AdvancedSettingsState.availableModels` / `.availableEngines`; B's state
   model should expose it as one derived value both panes read.
3. **The test-field exception to `configurationEnabled`.** Every Advanced
   Recognition (and Dictation Behavior) control disables while dictation is
   active, via `configurationEnabled`, exactly as today. Quick Setup's dictation
   test (`02-quick-setup.md` §4) requires the *opposite* for exactly one field:
   its own scratch text field must stay focusable and must keep the current
   window as the live insertion target while a test dictation is in flight,
   even though every other control in the settings window is disabled for the
   same duration. This needs to be a named exception in the shared state model
   (e.g. a `testFieldRemainsInteractive` flag alongside
   `configurationEnabled`), not a special case built independently in each
   pane.

## 6. Open placement note for the orchestrator

Dictation Behavior's three settings (Custom Words, Recording Limit, Keep Last
Dictation) are placed by this document but **their control design is not
claimed by this document** — they were not explicitly assigned to B (Advanced
Recognition + state model) or C (visual system + Application/Appearance) in
the task split. Someone needs to own building them; this IA only guarantees
they have exactly one correct home to be built into.
