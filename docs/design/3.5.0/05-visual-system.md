# 3.5.0 Visual and Accessibility System

Owner: subagent C (system/visual). Consumers: subagent A (information
architecture, Quick Setup) and subagent B (advanced recognition, settings
state model). This document specifies the reusable component set, the layout
and typography rules that back it, and the accessibility contract every
component must meet. It defines components by contract, not by the screens
they appear on — neither Quick Setup nor Advanced Recognition is named below
except as an example of where a component's contract applies.

Ground truth referenced throughout: `AdvancedSettingsWindowController.swift`,
`BadgeThemePalette.swift`, `SoftwareUpdate.swift`,
`SoftwareUpdateInstaller.swift`, `ModelDownloadProgressPanel.swift`, and
`Permissions.swift` / `SetupWindowController.swift`, all in this worktree.

## 0. One decision that shapes everything below

Today, `AdvancedSettingsWindowController.applyTheme(_:)` recolors the entire
Settings window — background, every label, every control's tint — using the
selected **badge** theme (`BadgeThemePalette`), and `ARCHITECTURE.md` documents
this as intentional: "Changing the dropdown updates the existing badge,
Settings window, and open opaque User Guide in place."

This redesign **decouples Settings chrome from the badge theme.** Settings,
its advanced disclosures, and the User Guide always render in native macOS
semantic colors and materials, adapting automatically to system light/dark
mode and Increased Contrast. The badge theme picker (Appearance, see
`06-application-preferences.md`) continues to control only the caret-attached
Listening/Transcribing/Error badge, previewed with a live swatch rather than
by reskinning the window that shows the picker.

Rationale: a user's custom theme (arbitrary hex triples, see
`CustomBadgeTheme`) is not contrast-checked. Today a poorly-chosen custom
theme makes Settings itself hard to read while the user is trying to fix it.
Native chrome is legible unconditionally, is the only way to give every
component below one accessibility contract instead of one per theme, and
matches how System Settings and every other native preferences window
behaves. This is a deliberate behavior change from the current build,
not an oversight — flagged again in the handoff for `ARCHITECTURE.md` and
`purpose.md`, which describe the current coupled behavior and are outside
this document's owned paths.

## 1. Component set

Nine components. Each entry gives the contract, where it belongs, what it
must never be used for, and a minimal SwiftUI signature sketch (not an
implementation) to pin the contract precisely.

### 1.1 Settings Page

The root container for one settings screen (a tab's full content, e.g. Quick
Setup, Advanced Recognition, Application, Appearance).

```swift
struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
}
```

- **Used for:** the single top-level view per tab. Owns the scroll view, the
  page title, the max content width, and top/bottom page insets.
- **Must not be used for:** a sub-panel inside a tab (use Settings Section), a
  transient popover/disclosure (use Advanced Disclosure), or a second
  scrollable region nested inside a tab — a page scrolls once, as a whole.

### 1.2 Settings Section

A labeled, visually grouped block of rows.

```swift
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var rows: () -> Content
}
```

- **Used for:** grouping related rows under one heading (mirrors today's
  `INPUT` / `RECOGNITION` / `APPEARANCE` / `STARTUP` grid groups). One section
  per topic; a tab is normally 1–4 sections.
- **Must not be used for:** a single isolated row (use Settings Row directly
  inside the page — a one-row section wastes vertical rhythm and adds a
  heading nothing else groups under), or as a generic card/box for unrelated
  content (e.g. the internal-dictionary Add/Existing pair is two boxes inside
  one row's control area, not two sections).

### 1.3 Settings Row

One label paired with one control, at fixed alignment.

```swift
struct SettingsRow<Control: View>: View {
    let label: String
    /// Overrides `label` for VoiceOver when the visible text is abbreviated
    /// or the control already names itself (e.g. a preset selector chip set).
    var accessibilityLabel: String? = nil
    @ViewBuilder var control: () -> Control
}
```

- **Used for:** every individual setting: one label, one control (a control
  may itself be a compound view, e.g. a chip row, popup + two buttons, or a
  two-pane add/existing box — but it is presented as a single control column
  under one label).
- **Must not be used for:** stacking two unrelated settings under one label
  (give each its own row), or read-only display text with no control (use
  Informational Message, optionally inside a row whose "control" is the
  message itself, but never a bare label with no accessible pairing).

### 1.4 Preset Selector

Selects exactly one value from a closed, known set. Two presentations share
one contract; the presentation is chosen by option count and structure, not
by screen.

```swift
struct PresetSelector<Option: Identifiable & Hashable>: View {
    enum Presentation { case chips, menu }
    let presentation: Presentation
    let options: [Option]
    @Binding var selection: Option.ID
    let title: (Option) -> String
    /// Full, unabbreviated name — chips may show a short label ("Turbo") while
    /// VoiceOver always hears the full one ("Large v3 Turbo, quantized").
    let accessibilityTitle: (Option) -> String
    /// nil = enabled. Non-nil disables that one option and supplies why.
    let disabledReason: (Option) -> String?
    /// menu presentation only; nil = no group heading for that option.
    let groupHeading: (Option) -> String?
}
```

- **Presentation rule:** `chips` when the set has 2–5 options with short
  labels and no grouping (today's mode/model/engine/decoding/processing
  segmented controls). `menu` when the set exceeds ~5 options or has group
  headings (today's hotkey popup, recording-limit popup, and the theme popup
  with its Dark/Light/Custom headings). A section must not invent a third
  presentation for a preset selector.
- **Per-option disable is load-bearing.** SwiftUI's `Picker(.segmented)`
  cannot disable or tooltip individual segments — that is exactly the
  behavior `modelControl.setEnabled(_:forSegment:)` and
  `.setToolTip(_:forSegment:)` depend on today (an uninstalled whisper model
  stays visible but inert, with its reason in the tooltip). The `chips`
  presentation is therefore hand-built from individual `Button`s in an
  `HStack`, each carrying its own `.disabled(because:)` (§2.4), not a native
  segmented `Picker`. This is a plain SwiftUI composition, not a missing
  AppKit behavior, so it does not justify Introspect or SwiftUIX.
- **Used for:** dictation key, input behavior, model/variant, engine,
  decoding profile, processing mode, recording limit, hotkey choice, badge
  theme (built-in + custom, grouped).
- **Must not be used for:** a single boolean (use a native `Toggle`), free
  text, or an open-ended/unbounded list (use a dedicated list UI — Preset
  Selector assumes every option is enumerable and fits a menu or a row of
  chips without its own internal scrolling).

### 1.5 Status Indicator

A small, non-interactive readout of system- or app-derived state.

```swift
struct StatusIndicator: View {
    enum Level { case positive, caution, neutral, unavailable }
    let level: Level
    let text: String
    /// Paired SF Symbol — color is never the only signal (see §3.4).
    let symbolName: String?
    let accessibilityLabel: String
}
```

- **Used for:** login-item status (Enabled / Approval needed / Off /
  Unavailable), software-update status (Checking… / Up to date / vX.Y.Z
  available / Downloading… / Verifying… / Restarting… / Unable to check /
  Update failed), permission status (Granted / Not Granted).
- **Must not be used for:** anything tappable — a Status Indicator has no
  target. If the state needs an action attached (e.g. "Approval needed" next
  to an "Open System Settings" button), the button is a sibling view in the
  same row, not part of the indicator. Must not be used to report the
  in-progress phase of a long action with a determinate/indeterminate
  fraction — that is Test-Result Panel.

### 1.6 Informational Message

Small supporting text attached to a row or section.

```swift
struct InformationalMessage: View {
    enum Emphasis { case secondary, subtle }
    let text: String
    var emphasis: Emphasis = .secondary
    var accessibilityLabel: String? = nil
}
```

- **Used for:** the internal-dictionary draft preview ("Ready: …", "Already
  saved: 2"), the update status caption, permission explanations, one-line
  help text under a row.
- **Must not be used for:** a reason a *control* is disabled — that reason
  belongs on the control itself via `.disabled(because:)` (§2.4) so
  VoiceOver reaches it while focused on the control, not by wandering to a
  separate caption. Must not be used for multi-paragraph explanation (that
  belongs in the User Guide popover, out of this document's scope) or for
  anything requiring a retry/dismiss action (use Unsupported-Feature State or
  Test-Result Panel).

### 1.7 Unsupported-Feature State

The composite pattern for "this setting doesn't apply right now."

```swift
struct UnsupportedFeatureState<Content: View>: View {
    let reason: String
    /// true: the setting still holds meaningful, persisted data under the
    /// current configuration — show it, disabled, with the reason.
    /// false: the setting has no meaning at all under the current
    /// configuration — hide the row entirely instead of showing a lie.
    let persistsMeaning: Bool
    @ViewBuilder var content: () -> Content
}
```

- **Two ground-truth precedents, both preserved:** Decoding profile has no
  meaning on an engine without beam search, so the row is hidden outright
  (`persistsMeaning: false` — `decodingRow?.isHidden = !engine.usesWhisperDecoding`,
  with the comment "a disabled segmented control still paints its selection,
  which reads as 'this is on'"). Internal dictionary entries still apply on
  every whisper engine and remain saved while Parakeet is selected, so the
  row stays visible, disabled, with the reason inline
  (`persistsMeaning: true`).
- **The choice between the two is the state model's call (subagent B), not
  this component's** — this component only supplies the two presentations
  and requires a reason string whichever is chosen.
- **Used for:** any row whose applicability depends on another setting
  (engine, mode, installed files).
- **Must not be used for:** a control that is disabled because the whole page
  is read-only during setup (`configurationEnabled == false`) — that is a
  page-level disabled state, not a per-feature one, and does not need a
  reason beyond "Settings are locked while setup completes" stated once at
  the page level.

### 1.8 Advanced Disclosure

An inline, expand-in-place area for editing something that would clutter a
row-based layout at rest.

```swift
struct AdvancedDisclosure<Trigger: View, Detail: View>: View {
    @Binding var isExpanded: Bool
    @ViewBuilder var trigger: () -> Trigger
    @ViewBuilder var detail: () -> Detail
}
```

- **Used for:** the custom theme editor (create/edit), and any other
  create/edit surface a section needs without leaving the page.
- **Inline, not modal — preserved from ground truth.** The current editor is
  inserted directly into the settings stack next to its trigger
  (`customThemeEditorIsInlineForTesting` asserts `superview === settingsStack`
  and `window?.attachedSheet == nil`) and the revealed content is scrolled
  into view. This redesign keeps that inline placement but drops the
  window-resize special case (`expandSettingsWindowForEditor`): because
  Settings Page already owns one page-level scroll view (§1.1), the
  disclosure expands within that existing scroll region instead of resizing
  the window. This removes a one-off animation path without changing what
  the user sees expand.
- **Must not be used for:** a setting reached frequently (a disclosure adds a
  step; frequent settings get their own row), and must never present as a
  sheet, popover, or separate window — that would be a second surface with
  its own focus and dismissal rules to specify, which the "inline" contract
  exists to avoid.

### 1.9 Test-Result Panel

Reports progress and/or the terminal outcome of one user-triggered,
time-bound operation.

```swift
struct TestResultPanel: View {
    enum Phase {
        /// fractionComplete == nil renders an indeterminate spinner.
        case running(fractionComplete: Double?, detail: String)
        case succeeded(detail: String)
        case failed(reason: String)
    }
    let title: String
    let phase: Phase
    let onCancel: (() -> Void)?
}
```

- **Generalizes `ModelDownloadProgressPanel`,** which today is already
  "shared by the on-demand model download and the in-app update install, so
  both report the same way instead of appearing to hang." This component is
  that same visual language (determinate bar once a total is known,
  indeterminate before it is, a detail line, an optional Cancel), expressed
  once in SwiftUI instead of duplicated per feature.
- **Two presentation contexts, one contract:** *inline*, embedded directly
  below the row that triggered it, when the triggering row is already on a
  visible Settings Page (e.g. Update and Restart clicked from the Updates
  row — maps `SoftwareUpdateStatus.downloading` / `.verifying` /
  `.installing` / `.failed` / `.installationFailed` onto `.running` /
  `.failed`). *Floating*, in its own small utility panel, when the
  triggering action can happen with no Settings window open at all (the
  on-demand model fetch that can start mid-dictation, which today is exactly
  `ModelDownloadProgressPanel`'s job). Both render the same internal view;
  only the container differs.
- **Used for:** software-update download/verify/install, on-demand model
  download, and — if subagent B's recognition surface needs one — a
  recognition self-test, since the contract makes no assumption about what
  produced the fraction or the pass/fail. This document does not assert B
  needs one; it only guarantees the contract is available.
- **Must not be used for:** ambient status with no user-triggered start (use
  Status Indicator), or anything that repeats/loops without a fresh user
  action — a Test-Result Panel always terminates in `succeeded` or `failed`
  and is dismissed or replaced, never left cycling.

## 2. Layout system

### 2.1 Spacing scale

One 8-step scale. Every section adopts a step from this table; none invents
its own number.

| Token | Value | Use |
|---|---|---|
| `xs` | 4pt | icon-to-text gap inside a Status Indicator; chip internal padding |
| `sm` | 8pt | gap between a control and its immediately adjacent sibling control (e.g. draft field to preview label) |
| `md` | 12pt | row-to-row spacing within a Settings Section (matches today's `rowSpacing = 12`) |
| `lg` | 16pt | gap between a row's label column and its control column's *internal* sub-controls when more than one appears side by side |
| `xl` | 18pt | column gap between a row's label and control (matches today's `columnSpacing = 18`) |
| `2xl` | 20pt | space after a Settings Section, before the next section's title (matches today's `setCustomSpacing(20, after:)`) |
| `3xl` | 24pt | page top inset, page bottom inset |
| `4xl` | 32pt | page horizontal inset (leading/trailing), matching today's `stack.leadingAnchor … constant: 32` |

Today's numbers already sit almost exactly on this scale (18, 20, 24, 26, 32,
12) — the scale rationalizes the few off-grid values (26 → 24) rather than
inventing new rhythm.

### 2.2 Content width

- Label column: fixed **128pt** (preserved from `sizeColumns`), right-edge
  aligned against the control column's leading edge.
- Control column: minimum **300pt**, grows with the window, capped at
  **560pt** so a manually widened window doesn't stretch a popup or chip row
  edge-to-edge unreadably (matches today's fixed `410pt` plus headroom for
  wider labels like the theme controls row).
- Page content max width: **624pt** (128 + 18 + 560 + 2×`4xl` margins docked
  by SwiftUI's alignment guide, i.e. the same effective width as today's
  620pt window at its default size) — centered when the window is wider than
  this, matching how System Settings caps its own content width.
- Window minimum size: **620×520**, unchanged from today
  (`window.minSize`).
- A Settings Page is always vertically scrollable when content exceeds the
  available height (`SettingsPage` owns one `ScrollView`); it is never
  horizontally scrollable — every row must fit the capped content width.

### 2.3 Typography hierarchy

| Role | Font | Color | Notes |
|---|---|---|---|
| Page title | 22pt semibold | `.primary` (labelColor) | once per Settings Page |
| Section title | 11pt semibold, uppercase | `.tertiary` (tertiaryLabelColor) | VoiceOver heading trait; matches today's `INPUT`/`RECOGNITION` style |
| Row label | 13pt medium | `.primary` | left column of every Settings Row |
| Control text | system default per control | native | never overridden — a `Toggle`, `Picker`, or `Button` keeps its platform font |
| Informational Message (secondary) | 11pt regular | `.secondary` | update status caption, preview text |
| Informational Message (subtle) / meta | 10pt regular | `.secondary` | version string, byte counts, "42% · 12 MB of 40 MB" |
| Version / byte counts | 10pt monospaced digit | `.secondary` | preserves today's `.monospacedSystemFont` for the version label and progress detail so digits don't jitter in width as they update |
| Status text | 11–12pt medium | level-dependent (§2.4) | always paired with an SF Symbol, never color alone |

### 2.4 Semantic colors

No fixed hex values anywhere in Settings chrome (that is the point of §0).
Every color reference is a system semantic color or material, so light/dark
and Increased Contrast are automatic:

| Purpose | Token |
|---|---|
| Primary text | `Color(nsColor: .labelColor)` / SwiftUI `.primary` |
| Secondary text | `.secondaryLabelColor` / `.secondary` |
| Section headings | `.tertiaryLabelColor` |
| Separators / row dividers | `.separatorColor` |
| Page background | system window background material (`.background(.windowBackground)` or equivalent) |
| Grouped box background (e.g. Add/Existing panes) | `.controlBackgroundColor` / `GroupBox`'s native material |
| Interactive tint (toggles, buttons, selected chip) | `.accentColor` (respects the user's System Settings accent color) — **replaces** today's badge-theme-derived `waveform` tint applied to `loginItemToggle`, `keepLatestDictationToggle`, etc. |
| Status: positive | `.green` (systemGreen) |
| Status: caution | `.orange` (systemOrange) |
| Status: neutral / off | `.secondary` |
| Status: unavailable / failed | `.red` (systemRed) |

## 3. Accessibility

### 3.1 Focus states

Every interactive component uses the platform's native focus ring
(`.focusable()` / `@FocusState` in SwiftUI) — never a custom-drawn
substitute that could be dimmer, thinner, or omitted for a "quieter" look.
The ring is the 2pt system accent outline AppKit/SwiftUI draws by default. A
Status Indicator, Informational Message, and section title are never
focusable — they carry no action.

### 3.2 Keyboard navigation order

Tab order follows visual order: page title (not focusable) → first Settings
Section's rows top-to-bottom, left-to-right within a row (label is never a
tab stop, only its control is) → next section, in the order sections appear
on the page → footer/help controls last. `Preset Selector` in `chips`
presentation is one tab stop for the whole group; arrow keys move the
selection within it (native segmented/radio-group behavior). `Preset
Selector` in `menu` presentation is one tab stop; Space or Return opens the
menu, arrow keys move within it, Return commits, Escape cancels without
changing selection. `Advanced Disclosure`'s trigger is a tab stop that
toggles expansion with Space/Return; once expanded, its detail content joins
the tab order immediately after the trigger, before the next row. `Test
Result Panel`'s Cancel button, when present, is the panel's only tab stop
besides whatever dismiss action closes it.

### 3.3 VoiceOver labeling, per component

| Component | Label | Trait / behavior |
|---|---|---|
| Settings Page | page title read as the page's accessibility label | heading trait on the title |
| Settings Section | section title read as its own element | heading trait; `.accessibilityElement(children: .contain)` around the section so VoiceOver's heading rotor can jump section-to-section |
| Settings Row | the row's control carries `label` (or `accessibilityLabel` override) directly — never a silent adjacent label VoiceOver must discover separately | control's `accessibilityValue` reflects the current selection/state |
| Preset Selector | each option's `accessibilityTitle` (always the full name, even when the visible chip is abbreviated, e.g. "Large v3 Turbo, quantized" for the "Turbo" chip) | selected option carries the selected trait; a disabled option's label appends its `disabledReason` (e.g. "Base, not installed") |
| Status Indicator | `accessibilityLabel` states the full meaning, not just the word shown on screen (e.g. "Login item: approval needed. Open System Settings to approve.") | `.updatesFrequently` only while a value can change without user action in the current view (e.g. update status during a check); otherwise static |
| Informational Message | `accessibilityLabel` matches the visible text (or the override) | read as static text, never adjustable |
| Unsupported-Feature State | the reason is attached to the control(s) it disables via `.disabled(because:)`, not to a separate silent caption | disabled trait plus the reason, so focusing the control alone answers "why can't I use this" |
| Advanced Disclosure | trigger's `accessibilityLabel` is "Show advanced" / "Hide advanced" (or a caller-supplied verb pair) | button trait; `accessibilityValue` "expanded" / "collapsed" |
| Test-Result Panel | title plus current phase's detail string | progress announced via a throttled live-region update (see below), not on every byte — final `succeeded`/`failed` is announced exactly once |

`.disabled(because:)` is the single mechanism satisfying "disabled must
always be able to explain why": a view modifier applied directly to any
control.

```swift
extension View {
    /// Disables the control when `reason != nil` and attaches that reason to
    /// both the visual tooltip/caption and the accessibility tree.
    /// `reason == nil` leaves the control untouched and enabled.
    func disabled(because reason: String?) -> some View
}
```

This is the mechanism behind both Preset Selector's per-option
`disabledReason` and Unsupported-Feature State's `reason` — one primitive,
reused, so no component reinvents "greyed out with no explanation." It also
directly upgrades a real accessibility gap in the current build: today, a
failed login-item toggle only calls `NSSound.beep()` — silent for anyone not
listening for a system sound, and invisible to VoiceOver entirely. The
redesign attaches the failure as a `.disabled(because:)`-style inline reason
on the toggle's row (see `06-application-preferences.md` §1) instead.

### 3.4 Increased Contrast

Read via `@Environment(\.colorSchemeContrast)`. Because every color is
already a system semantic color (§2.4), text and separator contrast adapt
automatically with no per-component work. Two components need an explicit
increased-contrast addition because they otherwise rely partly on color to
carry meaning:

- **Status Indicator** always pairs its color with an SF Symbol and text
  (never color alone, per its contract in §1.5) — this is required at
  standard contrast already, not just increased, because color-only status
  fails colorblind users regardless of the system contrast setting.
- **Preset Selector** (`chips`) adds a visible 1pt border around the selected
  chip under Increased Contrast, rather than relying solely on the fill-tint
  difference between selected and unselected chips.

### 3.5 Reduced Motion

Read via `@Environment(\.accessibilityReduceMotion)`.

- **Advanced Disclosure**'s expand/collapse becomes an instant state change
  (no animated height/opacity transition) when reduce-motion is set;
  otherwise it uses a standard `withAnimation(.easeInOut)` height reveal.
- **Theme change** (badge preview swatch update, §0) is an immediate redraw
  under reduce-motion; otherwise a short crossfade.
- **Test-Result Panel**'s indeterminate spinner and determinate bar fill are
  *not* disabled under reduce-motion — Apple's HIG treats a progress
  indicator's own motion as informational, not decorative, so suppressing it
  would remove the only signal that work is happening.

### 3.6 Light and dark appearance

Automatic for every component, by construction: nothing in this document
uses a fixed color (§0, §2.4). The one component with real per-mode content
is Preset Selector's theme-picker instance, whose live swatch (added by this
redesign, see `06-application-preferences.md` §3) must render the selected
theme's own light/dark identity (`BadgeTheme.mode` / `CustomBadgeTheme.mode`)
regardless of the system's current appearance — the swatch previews the
*badge*, which is independent of Settings' own now-native chrome.

### 3.7 Disabled-control presentation

A disabled control uses the platform's default disabled treatment (SwiftUI's
built-in `.disabled()` dimming) — never a custom opacity value invented per
component. A disabled control's **current value stays visible**, dimmed, so
the user can see what is selected even while it's inert (e.g. a disabled
Decoding chip set, when shown at all per §1.7, still shows which profile is
selected — it just cannot be changed). The one exception is a row hidden
outright under Unsupported-Feature State's `persistsMeaning: false` branch,
where there is no current value to preserve because the setting has no
meaning at all in that configuration. Every disabled control carries a
reason via `.disabled(because:)` (§3.3) — there is no disabled control
without one.

## 4. Native tooling stance

No SwiftUI Introspect or SwiftUIX dependency is added. Every AppKit behavior
the current implementation relies on has a native macOS 14+ SwiftUI
equivalent:

- Per-segment enable/tooltip (`NSSegmentedControl.setEnabled(forSegment:)`,
  `.setToolTip(forSegment:)`) → Preset Selector's `chips` presentation is
  hand-built from `Button`s with `.disabled(because:)` and `.help(...)`, not
  `Picker(.segmented)` (§1.4). This is a composition choice, not a missing
  platform capability.
- Grouped, non-selectable menu headings (today's Dark/Light/Custom headers
  in the theme `NSPopUpButton`) → native `Picker` with `Section` headers,
  available since macOS 13.
- Precise two-column label/control alignment (today's `NSGridView`) → native
  SwiftUI `Grid`/`GridRow`, available since macOS 13.
- Tooltips → native `.help(_:)`.
- Scroll-into-view on disclosure expansion → native `ScrollViewReader` +
  `scrollTo`.

If a future section surfaces a genuine gap (an AppKit control with no
SwiftUI equivalent at all, not just a different composition), that gap must
be named explicitly against this list before either dependency is added.
