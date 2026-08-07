# Guided welcome window — designed, not yet built

Deferred from 3.5.5. The settings restructuring shipped; this did not. It is
the larger half of making the app usable by someone non-technical, and it is
written down here so the reasoning is not lost.

## The problem it solves

Traced through `applicationDidFinishLaunching`
(`Sources/WhisperHotkeyApp/WhisperHotkeyApplicationDelegate.swift`), a
brand-new user currently meets three surfaces before dictating once:

1. an alert offering to move the app into `/Applications`
2. the Setup window — six permission rows (`SetupWindowController.swift`)
3. the Settings window, opened automatically by
   `showFirstRunSettingsIfNeeded()`

That is roughly twenty rows across three windows, none of which answers the
only question a new user has: *does this work?* There is no "try it" affordance
anywhere in the app. Someone who cannot get a first success has no path to one,
which is the moment an app gets deleted.

## Shape

A single window, shown once on first launch **in place of** the Settings
window, with four steps:

1. **Permissions** — only the ones actually missing, each with its action
   button. Reuse `SetupReadiness` and the row/action pattern already in
   `SetupWindowController.swift`; do not build a second permissions surface.
2. **Dictation key** — confirm Right Option or pick another, from
   `HotkeyKey.allCases`.
3. **Try it** — a focused text view and one instruction: "Hold Right Option and
   say something." Success is non-empty text arriving. On failure, offer Retry
   with the reason from the existing badge-error mapping.
4. **Done** — "You're ready. whisper_hotkey lives in your menu bar."

Settings must stop opening automatically. Keep the existing
`hasPresentedFirstRunSettings` key so upgrading users never see this. The Setup
window stays for the something-broke-later case, reachable from the menu bar.

## The Try it step needs no new dictation plumbing

This was the main risk when the flow was first designed, and it is already
solved in shipped code. Dictating into the app's own window does **not** go
through Accessibility insertion. `WhisperHotkeyApplicationDelegate` sets
`deliversToInternalDictionaryDraft` on hotkey press when the settings draft
field is focused, and on a successful transcript calls
`appendDictatedInternalDictionaryDraft(_:)` **directly**, bypassing the
insertion path entirely.

Try it should reuse exactly that: a `deliversToWelcomeTryIt` flag set the same
way, and a direct call into the welcome controller. No AX round-trip, no focus
fragility, and it follows a pattern that already works in production rather
than inventing one.

## Files it would touch

- New: `Sources/WhisperHotkeyShell/WelcomeWindowController.swift`
- `WhisperHotkeyApplicationDelegate.swift` — replace the `showAdvancedSettings()`
  call inside `showFirstRunSettingsIfNeeded()`, and add the delivery flag
  alongside the existing `deliversToInternalDictionaryDraft`

## How to verify it

Delete the preference domain and relaunch, which is the only way to exercise
the real path:

```sh
~/bin/whisper_hotkey stop
defaults delete local.whisperhotkey.app
open -a /Applications/whisper_hotkey.app
```

Expect the welcome window, Settings not opening, and the Try it step accepting
a live dictation. Then confirm an existing install upgrades without seeing it
and with no preference rewritten.

## Still open

Whether the install-into-Applications alert should move inside this flow rather
than preceding it. Three windows became two; it could reasonably become one.
