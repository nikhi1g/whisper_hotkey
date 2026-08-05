# 3.5.0 Application Preferences

Owner: subagent C (system/visual). Scope: application-level preferences —
the things whisper_hotkey needs configured about *itself as a running macOS
app*, as distinct from dictation configuration (hotkey, engine, model,
decoding, internal dictionary, badge-appearance content), which belong to
subagents A and B. Every component referenced below (Settings Row, Preset
Selector, Status Indicator, Informational Message, Unsupported-Feature
State, Advanced Disclosure, Test-Result Panel, and the `.disabled(because:)`
modifier) is specified in `05-visual-system.md`; this document does not
redefine them, only applies them.

Ground truth referenced throughout: `LoginItemManager.swift`,
`AdvancedSettingsWindowController.swift`, `SoftwareUpdate.swift`,
`SoftwareUpdateInstaller.swift`, `ModelDownloadProgressPanel.swift`,
`Permissions.swift`, and `SetupWindowController.swift`, all in this
worktree.

## 0. Application vs. Appearance

Two tabs/pages own everything in this document. (Placement of any given tab
within the overall navigation — a sidebar, a segmented top switcher, or
otherwise — is information architecture and belongs to subagent A; this
table only says which page each preference lives on.)

| Preference | Page | Why |
|---|---|---|
| Launch at login | Application | app lifecycle, not dictation or appearance |
| Automatic update checks | Application | app lifecycle |
| Manual update check | Application | app lifecycle |
| Recording limit | Application (see §5 on placement) | a resource/session-length guard, not a recognition-quality parameter |
| Version and support information | Application | identifies the running app; links out |
| Permission status | Application | macOS-level authorization for the app as a whole, not a per-dictation setting |
| Theme selection (badge) | Appearance | governs only the runtime Listening/Transcribing/Error badge's look |

Appearance is deliberately narrow: it holds the badge theme picker (built-in
+ custom) and nothing else. It does **not** control Settings' own chrome —
see `05-visual-system.md` §0 for why that coupling is removed in this
redesign. If a future preference is purely about how something *looks*
(rather than how the app *behaves*), it joins Appearance; behavior joins
Application. Nothing in the current codebase besides the badge theme is a
pure appearance preference.

## 1. Launch at login

**Read `LoginItemManager.swift` first — there is no migration here.** The
app's minimum target is macOS 14+ (`AGENTS.md`), and
`LaunchAgentLoginItemService` already registers exclusively through
`SMAppService.agent(plistName:)` — there is no legacy `LSSharedFileList` or
manually-installed LaunchAgent code path in this codebase to migrate away
from. "Launch at login must follow SMAppService on macOS 13+" is already
true today, unconditionally, with no fallback branch. This document
therefore does not propose a migration; it specifies how the existing
five-state model is presented, and calls out the two things a rewrite must
not accidentally break.

**Do not change the plist name.** `agentPlistName =
"local.whisperhotkey.app.login-launcher.plist"` is the on-disk identity
`SMAppService` uses to recognize an existing registration. Changing it on
upgrade would silently orphan every user's current login-item registration
and re-prompt them for approval as if from scratch. The redesign must carry
this string forward unchanged.

**Preserve the `explicitlyDisabled` preference's semantics.** This is not
part of `LoginItemServiceState` (which mirrors `SMAppService.status`
directly) — it is a separate `UserDefaults` flag
(`"loginItemExplicitlyDisabled"`) that exists so first-run automatic
registration (`enableAutomaticallyIfReady`, called once setup completes)
never re-enables login-at-startup after a user has explicitly turned it off.
Any redesigned toggle must keep writing through `enableExplicitly()` /
`disableExplicitly()` (not a raw `register()`/`unregister()`), or a user who
turned the toggle off will find it silently back on after the next
first-run-readiness check.

### States and presentation

| `LoginItemStatus` | Meaning | macOS authorization | Presentation |
|---|---|---|---|
| `enabled` | registered and approved | none pending | Toggle on; Status Indicator "Enabled" (positive) |
| `requiresApproval` | app registered the agent, but the user has not approved it in System Settings → General → Login Items yet | **yes** — this state exists entirely because macOS gates the last step outside the app's control | Toggle on; Status Indicator "Approval needed" (caution); "Open System Settings" button visible (`SMAppService.openSystemSettingsLoginItems()`) |
| `notRegistered` | never registered, or explicitly turned off | none | Toggle off; Status Indicator "Off" (neutral) |
| `notFound` | agent plist not resolvable (unexpected install state) | none directly, but likely needs the same repair path as requiresApproval | Toggle off; Status Indicator "Off" (neutral) — treated the same as `notRegistered` in the toggle, since `unregisterIfNeeded`/`registerIfNeeded` already collapse these two |
| `unknown` | future `SMAppService.Status` case (`@unknown default`) | unclear | Toggle disabled via `.disabled(because: "Login item status is unavailable.")`; Status Indicator "Unavailable" (neutral); "Open System Settings" button visible as an escape hatch |

### External system change reflected back

There is no polling — this matches the product constraint against a resident
idle worker (`purpose.md`: "no resident model/helper... polling loop").
`LoginItemManager.status` is read fresh every time `refresh()` runs, and
`refresh()` is already triggered by `NSApplication.didBecomeActiveNotification`
(`applicationDidBecomeActive` → `refreshIfVisible()`). Concretely: if a user
opens System Settings → Login Items and manually disables or removes the
agent while whisper_hotkey's Settings window is open, the Status Indicator
and toggle do not update instantly — they update the next time the app
regains focus (e.g. the user switches back to it, including from System
Settings itself). This is the intended tradeoff (event-driven, not timed) and
should be stated as such in the row, not silently — the Status Indicator's
`accessibilityLabel` for `requiresApproval`/`unknown` states should make
clear that its value reflects the last time whisper_hotkey was active, not
live system state.

### Feedback after an action

Toggling calls `enableExplicitly()`/`disableExplicitly()` synchronously; both
can throw (`SMAppService.register()`/`.unregister()` do throw in practice —
e.g. if the app isn't in a trusted install location). Today, failure is
`NSSound.beep()` only — no visible or VoiceOver-reachable signal. This is a
concrete accessibility gap this redesign closes: on failure, attach the
error to the row via `.disabled(because:)`-style inline text for one refresh
cycle (e.g. "Couldn't change login item: \(error)"), not a silent system
beep, then let the next `refresh()` clear it once status is re-read.

### Visible but noninteractive

The Status Indicator text is always visible, in every state, not only when
an action is needed — a user should be able to see "Enabled" without
wondering whether something is wrong. The "Open System Settings" button is
the only conditionally-hidden element (hidden for `enabled`/`notRegistered`/
`notFound`, since there's nothing to approve there).

## 2. Automatic update checks and manual update check

Both are driven by the same `SoftwareUpdateStatus` state machine and are
specified together because their presentation is coupled: the manual-check
button's label and action change depending on what the automatic/manual
check most recently found.

### States

| `SoftwareUpdateStatus` | Display text | Component |
|---|---|---|
| `idle` | (empty) | — |
| `checking` | "Checking..." | Status Indicator (neutral) |
| `current` | "Up to date" | Status Indicator (positive) |
| `available(version, installable)` | "vX.Y.Z available" | Status Indicator (caution if not installable — release exists but is missing the DMG/checksum asset pair; positive-leaning otherwise) |
| `downloading` | "Downloading..." | Test-Result Panel, inline, `.running(fractionComplete:, detail:)` — determinate once `SoftwareUpdateInstaller`'s progress handler reports a total byte count, indeterminate before that |
| `verifying` | "Verifying..." | Test-Result Panel, inline, `.running(fractionComplete: nil, detail: "Verifying…")` — indeterminate; checksum/codesign/notarization-adjacent checks have no meaningful fraction |
| `installing` | "Restarting..." | Test-Result Panel, inline, `.running(fractionComplete: nil, detail: "Restarting…")` |
| `failed` | "Unable to check" | Status Indicator (unavailable/red) — the check itself failed (network, parse) |
| `installationFailed` | "Update failed" | Test-Result Panel, inline, `.failed(reason:)` — the install pipeline failed after a check succeeded |

The manual-check button (`checkForUpdatesButton`) already changes its title
contextually — "Check for Updates" normally, "Update and Restart" when
`case .available(_, true)` — and this redesign keeps that behavior exactly,
including its accessibility label tracking the visible title (already true
today via `setAccessibilityLabel`).

### macOS authorization

Checking requires none — a plain GET to the GitHub releases API for
metadata only (no audio, no transcript; this is compliant with the "never
downloads a model or sends audio/transcripts remotely" constraint in
`purpose.md`, since the DMG itself is application binary, not
user content). Installing requires no explicit in-app authorization prompt —
`SoftwareUpdateInstaller` verifies checksum, bundle identifier, version
ordering, code signature, and either matching designated requirement or a
passing `spctl` assessment, all silently. **One external prompt is outside
the app's control and must be designed around:** after the one-shot launcher
replaces the bundle and reopens it, macOS may show its standard "app
downloaded from the internet" Gatekeeper dialog on that first relaunch if
the replaced bundle's quarantine attribute state triggers it. The interface
cannot suppress or predict this — the design must simply tolerate the app
being briefly backgrounded by that system dialog right after an update
completes, and must not treat "app didn't reactivate immediately" as a
failure state.

### External system change reflected back

None — there is no external toggle for this preference the way there is for
login items. The only "external" factor is network reachability, which
surfaces as `.failed` (mapped from a thrown error in `GitHubReleaseUpdateChecker.check`)
rather than a distinct state; the retry path is simply clicking "Check for
Updates" again, which is always enabled once `.failed` is reached (busy-gate
below only applies to true busy states).

### Feedback after an action

Automatic check (once per launch, off by default —
`AutomaticUpdateCheckPreference.defaultValue == false`) runs silently unless
it finds `.available`, at which point the Status Indicator updates in place;
it never interrupts with a dialog. Manual check shows the full state
sequence above inline. Update-and-Restart uses the Test-Result Panel's inline
presentation, embedded directly below the Updates row (per
`05-visual-system.md` §1.9), with Cancel omitted — the current
`SoftwareUpdateInstaller` pipeline has no mid-flight cancellation path, so
offering a Cancel button that can't actually stop the download/verify/replace
sequence would be a lie the component contract explicitly forbids.

### Visible but noninteractive

The automatic-check toggle stays visible and interactive during a busy state
(it only affects the *next* app launch, not the check in progress). The
manual-check button becomes `.disabled(because: "A check is already in
progress.")` during any busy state (`softwareUpdateStatus.isBusy`), matching
today's `checkForUpdatesButton.isEnabled = configurationEnabled &&
!isBusy` gate but now with the reason attached per §3.7 of the visual system
doc, rather than a bare disabled button.

## 3. Theme selection (Appearance)

Scope reminder: this is the **badge** theme — the caret-attached
Listening/Transcribing/Error indicator — not Settings' own chrome (§0 of
`05-visual-system.md`).

### Model, preserved in full

23 built-in themes (`BadgeTheme`, 12 dark + 11 light, grouped by
`BadgeThemeMode`) plus up to 32 user-created custom themes
(`CustomBadgeTheme`: name, mode, three hex colors — background/text/accent).
Nothing here drops or restructures that model; `BadgeThemeSelection` remains
`.builtIn` / `.custom`, keyed by the same identifier scheme
(`"custom:\(uuid)"`) so existing persisted selections keep resolving.

### Presentation

Preset Selector, `menu` presentation, grouped by `groupHeading`: "Dark",
"Light", then "Custom" (only present when `customThemes` is non-empty) —
directly matching today's `rebuildThemePopup` structure (mode-grouped
built-ins, then an unlabeled-if-empty custom section, sorted
case-insensitively by name). 23+ options with three group headings is well
past the chip threshold (§1.4 of the visual system doc), so `menu` is the
only correct presentation here, exactly as today.

**New: a live preview swatch next to the picker.** Today the popup is
names only — a user picks "Rosé Pine Dawn" blind. This redesign adds a small
swatch (a miniature rendering of the badge's background/text/accent, using
`BadgeThemePalette.palette(for:)` directly) beside the selector that updates
the instant a new option is highlighted or committed, so the choice is
visually confirmed before and after selection. This is a genuine UX
addition, not a preserved behavior — called out explicitly since it's new
scope, not implied by the acceptance criteria's silence.

### Custom theme editing

Advanced Disclosure (`05-visual-system.md` §1.8), inline, triggered by "New"
(create) or "Edit" (edit — only enabled when `selectedTheme.customTheme !=
nil`, unchanged from today). The disclosure's detail content is the same
name/mode/three-hex-color fields `CustomThemeEditorViewController` collects
today; this document does not redesign that editor's internals (that detail
belongs to whichever screen hosts Appearance, per A's IA), only its
container (Advanced Disclosure) and its trigger row (a Settings Row holding
the theme Preset Selector plus New/Edit as sibling buttons).

**32-theme cap is an Unsupported-Feature State, not a silent limit.** When
`customThemes.count == CustomBadgeTheme.maximumCount`, "New" becomes
`.disabled(because: "You've reached the limit of 32 custom themes. Delete one to add another.")`
rather than doing nothing when clicked or (worse) silently failing to
persist a 33rd theme past the `prefix(maximumCount)` truncation in
`CustomBadgeTheme.persist`.

### macOS authorization / external reflection

None for either — themes are pure app-owned preference data. The one
genuinely external factor is the *system* light/dark appearance, which
affects Settings' own now-native chrome automatically (§0) and requires no
explicit handling in this preference's logic — it's a consequence of the
decoupling decision, not a new mechanism.

## 4. Recording limit

Values: 30s, 1, 2, 5, 10, 15, 30 minutes, 1 hour
(`RecordingLimit.allCases`); default 10 minutes
(`RecordingLimit.defaultLimit`).

**On placement:** this preference lives in the Recognition section in the
current build (`recordingLimitPopup` is a row in `AdvancedSettingsWindowController`'s
`recognitionGrid`). It is specified in *this* document because it is not a
recognition-quality parameter — it doesn't change what gets transcribed or
how, it caps how long a single capture is allowed to run before an automatic
stop, which is a resource/session-length safety guard independent of engine,
model, or decoding choice. Whether it is presented on the Application page or
elsewhere in the tab structure is subagent A's call as IA owner; the
contract below applies wherever it lands.

- **Component:** Preset Selector, `menu` presentation — 8 options exceeds
  the chip threshold (§1.4 of the visual system doc), so this is a popup,
  not a segmented control, matching today.
- **macOS authorization:** none.
- **External reflection:** none — pure app preference.
- **Feedback after an action:** selection applies immediately; no
  confirmation, test, or preview is needed — the value only takes effect on
  the next capture, not retroactively.
- **Visible but noninteractive:** none beyond the selected value itself.

## 5. Version and support information

### Version

Read from `Bundle.main`'s `CFBundleShortVersionString` ("Development" when
absent, e.g. running unsigned from `swift build`), shown as "Version X.Y.Z"
in monospaced digits (§2.3 of the visual system doc, preserving today's
`.monospacedSystemFont`). This is static text — not a control — always
visible, never interactive beyond standard text selection (`.textSelection(.enabled)`
in SwiftUI is a low-cost, fully native addition worth keeping so a user can
copy the exact version string into a bug report without retyping it; nothing
like it exists today).

No special refresh logic is needed after an in-app update: the Settings
window controller (and its state) is reconstructed fresh on every app
launch, and Update-and-Restart always ends in a full relaunch — so the
version label naturally reads the new bundle's `Info.plist` the next time
Settings is built, with no stale-version risk to design around.

### Support and documentation links

Two links, kept distinct rather than collapsed into one, because they serve
different needs:

- **In-app User Guide** (existing Help button → transient, scrollable
  popover, two tables — "your complete active path" and "everything else" —
  rebuilt from current state on every open, per `purpose.md`). No network
  request, works offline, answers "what does my current configuration mean."
  Per §0/§3.6 decoupling, this popover also renders in native chrome now,
  not the badge theme.
- **GitHub repository** (existing "GitHub ↗" button, opens
  `https://github.com/nikhi1g/whisper_hotkey` via `NSWorkspace`). External,
  requires network and a browser, answers "where's the source / how do I
  file an issue." The trailing arrow glyph is the existing, sufficient
  external-link affordance — no separate icon system is introduced.

Both together satisfy "links to documentation": one in-app, one external, no
redundant third link.

### macOS authorization / external reflection

None for either.

## 6. Permission status

**New to Settings.** Today, Microphone, Accessibility, and Input Monitoring
permission status is surfaced only in the one-time `SetupWindowController`
(`SetupReadiness`: `microphoneGranted`, `accessibilityGranted`,
`inputMonitoringGranted`, plus model/helper/login-item readiness rows) —
Settings itself has no permission UI today. This redesign adds a read
(mostly) status surface for the same three permissions to the Application
page, so a user doesn't have to re-trigger the full Setup flow just to check
or repair one permission after, say, an OS upgrade resets Accessibility
trust.

**Relationship to Setup, stated explicitly so it isn't duplicated by
another subagent:** Setup remains the blocking, first-run,
all-of-microphone-and-accessibility-and-input-monitoring-and-model-and-helper
gate — that ownership and its five-row layout (`SetupWindowController.Row`)
is untouched by this document. This section adds a lightweight, ongoing
*status-and-repair* surface inside Settings for the same three permissions
only (not model/helper/login-item, which aren't macOS authorizations) —
narrower in scope, always available after first run, not a second onboarding
flow.

### States, per permission (`SystemPermissionState`: `granted` / `notGranted`)

| Permission | macOS authorization | Repair action when `notGranted` |
|---|---|---|
| Microphone | yes — `AVCaptureDevice` authorization, first-request shows the system's native permission alert | "Request" button, calling the same in-app re-request path Setup uses (`requestMicrophone`) — the system alert can still be shown again if the user has never explicitly denied it |
| Accessibility | yes — `AXIsProcessTrusted`, gated in System Settings → Privacy & Security → Accessibility | "Open System Settings" button (`openAccessibilitySettings`) — once denied or dismissed, `AXIsProcessTrustedWithOptions` will not re-prompt; only System Settings can grant it |
| Input Monitoring | yes — `CGPreflightListenEventAccess`, gated in System Settings → Privacy & Security → Input Monitoring | "Open System Settings" button (`openInputMonitoringSettings`) — same one-shot-prompt caveat as Accessibility |

Each permission is one Settings Row: a Status Indicator ("Granted" positive /
"Not Granted" caution) plus the repair action as a sibling button, visible
only when `notGranted` (mirroring the login-item row's pattern of hiding the
repair affordance once nothing needs repairing).

### External system change reflected back

Same event-driven pattern as login items (§1): permissions are re-read via
`SystemPermissionController.preflight()` on `refresh()`, triggered by the app
becoming active — not polled. If a user revokes Accessibility in System
Settings while whisper_hotkey's Settings window is open, the row updates the
next time the app regains focus, not instantly. State this in the row's
accessibility label the same way as §1, so VoiceOver users aren't told a
stale "Granted" is currently true.

### Feedback after an action

Clicking "Request" for Microphone triggers the system's native permission
alert (out of the app's visual control entirely — no custom UI to design,
the OS owns that dialog) and `refresh()` re-reads status once the app
regains focus after the user responds. Clicking "Open System Settings" for
Accessibility or Input Monitoring deep-links directly to the relevant
System Settings pane; same refresh-on-reactivate pattern applies.

### Visible but noninteractive

The Status Indicator for each permission stays visible in the `granted`
state too — a user should be able to confirm all three are granted at a
glance without hunting for what's missing.
