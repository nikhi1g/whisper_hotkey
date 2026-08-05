# 3.5.0 Design — Settings State Model

Scope: the state model behind recognition settings — presets (Fastest /
Balanced / Most Accurate, presented by the Quick Setup doc) and the Advanced
Recognition controls specified in
[`03-advanced-recognition.md`](03-advanced-recognition.md) — that keeps
presets and advanced overrides from ever reaching a contradictory or invalid
combination. Type sketches below are Swift-shaped for precision, not an
implementation; they describe a contract, not a diff against
`Preferences.swift`.

## 1. Why a formal model

Every bug fixed in 3.3.6 (`docs/releases/3.3.6.md`) was the same defect
wearing different clothes: a surface reporting something other than what the
app was actually doing. Underneath each one, a value that belonged to one
category was read or written as if it belonged to another —

- a stored preference read as if it were live availability (the engine
  picker's greyed-out state, computed from the wrong thing),
- a UI control's option count trusted without recomputing it against the
  engine that had just changed (the freeze),
- a cost that should have been an explicit, visible step absorbed silently
  into a preference write (Parakeet's first-use download).

The fix is definitional, not a patch per surface: give every value exactly
one home among five categories, forbid any code path from reading a value as
if it were a different category, and route every write through one gate
(§4) so a new feature — presets — cannot reintroduce the same class of bug
through a second path.

## 2. The five categories

| Category | What it is | Persisted? | Who may write it | Recomputed |
|---|---|---|---|---|
| **User Preference** | Explicit user intent | Yes, `UserDefaults` | Only a user action | Never — it's the input, not an output |
| **Resolved Engine Configuration** | Exactly what the recognizer will run next | No | The recognizer, from preferences + filesystem | Every preload/dictation start |
| **Temporary Runtime State** | What's happening right now | **Never** | The recognizer/installer, in-process | Continuously; always starts quiescent on launch |
| **Engine Capability** | Static, engine-intrinsic facts | No — not a preference at all | Nobody; fixed in code (Core ML: fixed once, at launch, by a build marker) | Never changes at runtime |
| **Unavailable/Unsupported State** | Why a preference currently can't be honored | No | Nobody; derived | Every launch, every filesystem/install/build change |

The rule that matters most: **runtime status must never be persisted as a
preference.** `WhisperReadiness` (idle/loading/ready/failed), install
progress, and software-update status all reset to a quiescent value on every
launch. A crash while `.loading` must never be remembered as `.failed` on
the next launch — the recognizer always gets a clean attempt.

## 3. Type sketches

```swift
// 1. User Preference — the only thing that goes in UserDefaults.
// Superset-compatible with today's WhisperHotkeyPreferenceKeys; see §7.
struct RecognitionPreferences: Codable, Equatable {
    var engine: RecognitionEngine
    var whisperModel: DictationModel        // read only while engine uses it
    var parakeetVariant: ParakeetVariant    // read only while engine == .parakeetCoreML
    var decodingProfile: DecodingProfile    // read only while engine.usesWhisperDecoding
    var processingMode: ModelProcessingMode
    var internalDictionaryEntries: [String]
    // Display cache only — see §6. Never authoritative for "is a preset active."
    var lastAppliedPresetID: RecognitionPresetID?
}
```

```swift
// 2. Resolved Engine Configuration — computed at preload/dictation time,
// not stored. Mirrors WhisperRuntimeConfiguration's shape.
struct ResolvedRecognitionConfiguration {
    let engine: RecognitionEngine
    let modelURL: URL                        // or a Parakeet checkpoint directory
    let decodingProfile: DecodingProfile      // meaningless downstream unless usesWhisperDecoding
    let parakeetVariant: ParakeetVariant
    let promptConditioningActive: Bool        // == engine.supportsPromptConditioning
}
```

```swift
// 3. Temporary Runtime State — never persisted, always starts quiescent.
enum RecognitionRuntimeStatus: Equatable {
    case idle
    case preparing(EngineInstallPhase?)  // preload, OR an install/download
    case ready
    case failed(reason: String)
}

enum EngineInstallPhase: Equatable {
    case downloading(fractionCompleted: Double)
    case compiling   // Core ML compilation after transfer; no byte count
}
```

```swift
// 4. Engine Capability — static, code-defined, never mutated, never a
// preference. One instance per RecognitionEngine case, fixed in code.
struct EngineCapability {
    let usesWhisperDecoding: Bool
    let usesLocalHelper: Bool
    let supportsPromptConditioning: Bool
    let supportsCommandLineFallback: Bool   // true only for whisper.cpp Metal
    let modelUnit: ModelUnit                 // .sharedWhisperCheckpoints | .ownParakeetCheckpoints
    let modelSourcing: ModelSourcing          // .bundledOrInApp | .externalBootstrapOnly | .onDemandDownload
    let requiresBuildMarker: Bool             // true only for whisper.cpp Core ML Encoder
}
```

```swift
// 5. Unavailable/Unsupported State — derived, recomputed, never cached
// across a filesystem or build-capability change.
struct EngineReachability {
    let engine: RecognitionEngine
    let isBuildSupported: Bool                        // false only for a gated Core ML Encoder build
    let reachableModels: Set<DictationModel>          // may be empty
    let reachableParakeetVariants: Set<ParakeetVariant>
    var isSelectable: Bool {
        isBuildSupported
            && (!reachableModels.isEmpty || !reachableParakeetVariants.isEmpty)
    }
}
```

## 4. The selection gate — the one write path

Engine, model, decoding profile, processing mode, vocabulary, and preset
selection all funnel through one gate. This is what stops a preset from
reaching a state the advanced pickers themselves could never reach — the
new feature reuses the old constraint rather than adding a second path that
could drift from it.

```swift
enum RecognitionSelectionGate {
    /// Returns the accepted preferences, or nil if resolution failed
    /// outright (previous preferences remain in force).
    static func apply(
        _ target: RecognitionPreferences,
        reachability: [RecognitionEngine: EngineReachability],
        installIfNeeded: (RecognitionEngine, ModelReference) async -> Bool
    ) async -> RecognitionPreferences? {
        // 1. Resolve `target` to a runnable pairing. Never silently drop
        //    the user's engine choice onto some other engine; carry the
        //    chosen engine to a model/checkpoint it can run instead
        //    (mirrors resolvedModel(for:) today).
        // 2. If the resolved pairing needs an install (Medium, a Parakeet
        //    checkpoint), run the existing explicit progress/Cancel flow.
        //    Continue only on success; a cancel or failure returns nil.
        // 3. Write the full bundle atomically: engine, whisperModel or
        //    parakeetVariant, decodingProfile, processingMode together —
        //    never a partial diff. An interrupted write can then never
        //    strand two keys belonging to different presets.
        // 4. Recompute presetMatch (§6) against the new value before
        //    returning, so display state is never one step behind storage.
    }
}
```

Every mutation entry point in `WhisperHotkeyApplicationDelegate` today
(`selectEngine`, `selectModel`, `selectParakeetVariant`,
`selectDecodingProfile`, `selectProcessingMode`) already implements pieces
of steps 1–2 by convention, spread across five methods. The 3.5.0 model
formalizes that convention as one gate specifically *because* presets are
new: a preset is not a separate write path that happens to produce similar
results — it calls the identical gate with a fully-resolved bundle (§6), so
it inherits every rule below for free instead of needing its own copy of
them.

## 5. Rules that make specific states unreachable

- **An engine paired with a model it cannot run.** Gate step 1 is the only
  place `engine`, `whisperModel`, and `parakeetVariant` are ever written,
  and it never writes them independently of each other's compatibility.
  There is no code path — advanced picker or preset — that writes `engine`
  without also resolving the model.

- **Custom vocabulary shown as active on an engine that ignores it.** The UI
  must derive "vocabulary is active" from
  `ResolvedRecognitionConfiguration.promptConditioningActive`, never from
  "does the entry list have entries." The entry list is preference state
  (persists regardless of engine, per `03-advanced-recognition.md` §4);
  whether it's *effective* is resolved-configuration state. Reading the
  wrong one is exactly the 3.3.6 "row stayed fully interactive on Parakeet"
  bug.

- **A preset label still selected after overrides no longer match it.**
  `presetMatch` (§6) recomputes from live `RecognitionPreferences` after
  every gate write — it is never inferred from whichever preset button was
  last clicked. The moment an advanced-control write produces preferences
  for which no preset's bundle matches, the preset control must show an
  explicit "no preset selected" state on that same recomputation, not on
  some later refresh.

- **An engine picker with no reachable option.** `EngineReachability
  .isSelectable` is guaranteed non-empty in the ordinary case because
  whisper.cpp Metal + the bundled Base English model carry no build gate
  and no install dependency — they are always reachable from a clean
  install. The one case this can still fail (a corrupted installation with
  even the bundled model missing) is not a picker state at all: the whole
  Recognition section renders as disabled, reusing the pattern already
  present in code as `unavailableAdvancedSettingsState` (`availableModels:
  []`, `availableEngines: []`, `configurationEnabled: false`) — an explicit
  "Recognition unavailable" placeholder, never an interactive-looking
  control built against an empty option set. This is also what R5 in
  `03-advanced-recognition.md` §8 protects against for the *option count*
  case: rebuild the row before applying any selection to it.

## 6. Presets: what they resolve to, and override behavior

Scoped as backing model only. Names, presentation, and the Quick Setup
surface belong to that document; this defines what each name means as data.

```swift
enum RecognitionPresetID: String, Codable {
    case fastest, balanced, mostAccurate
}

struct RecognitionPreset {
    let id: RecognitionPresetID
    // engine + model-or-variant + decodingProfile + processingMode.
    // Vocabulary and every non-recognition preference are untouched.
    let bundle: RecognitionPreferences
}
```

| Preset | Engine | Model | Decoding | Processing Mode |
|---|---|---|---|---|
| Fastest | whisper.cpp Metal | Base English — bundled, labeled "Fast" in `DictationModel.menuTitle` | Smart Decode | Decode While Speaking |
| Balanced | whisper.cpp Metal | Large-v3 Turbo Q5 — labeled "Best Balance" | Smart Decode | Model Ready |
| Most Accurate | whisper.cpp Metal | Medium English — labeled "High Accuracy" | Precision | After Recording |

Rationale: all three anchor on whisper.cpp Metal because it is the only
engine with no build gate and a model that's either bundled or reachable by
an in-app download — a preset must always be reachable at first run without
requiring the external `run.sh` bootstrap or an unprompted network request.
Each model tier reuses the tradeoff language `DictationModel.menuTitle`
already assigns that checkpoint, rather than inventing a fourth taxonomy on
top of an existing one. WhisperKit, Core ML Encoder, and Parakeet stay
reachable only through Advanced Recognition, as deliberate opt-ins —
Parakeet in particular carries an explicit multi-hundred-megabyte download
that a one-click "Fastest" should not trigger silently on a user's behalf,
however favorably it might compare on paper.

Custom Vocabulary, the hotkey, activation mode, recording limit, badge
theme, and every other non-recognition preference are untouched by preset
selection. A preset's bundle is exactly the four fields in the table above.

```swift
func presetMatch(_ prefs: RecognitionPreferences) -> RecognitionPresetID? {
    RecognitionPreset.all.first {
        $0.bundle.engine == prefs.engine
            && $0.bundle.decodingProfile == prefs.decodingProfile
            && $0.bundle.processingMode == prefs.processingMode
            && ($0.bundle.engine == .parakeetCoreML
                ? $0.bundle.parakeetVariant == prefs.parakeetVariant
                : $0.bundle.whisperModel == prefs.whisperModel)
    }?.id
}
```

This runs after every gate write, not only at load. Its result is what
Quick Setup highlights. `lastAppliedPresetID` exists only to break a tie if
a future preset definition were ever to overlap another's resolved bundle
(not expected given the table above, kept honest rather than assumed) — it
never decides *whether* a preset is active, only which name to prefer among
multiple matches.

**Seeing an override:** the moment any advanced control's write produces
preferences for which `presetMatch` returns `nil`, the preset control shows
an explicit "Custom" state rather than continuing to highlight whichever
preset was last clicked. **Returning to a preset:** selecting one re-invokes
the gate (§4) with that preset's complete bundle. Because gate writes are
atomic and complete rather than incremental, this deterministically clears
every override in place — there is no partial-return path, and no advanced
control can be "half-returned" to a preset's value while another stays
overridden.

## 7. Migration from every preference key that exists today

| Existing key (`WhisperHotkeyPreferenceKeys`) | 3.5.0 disposition |
|---|---|
| `dictationModel` | unchanged; becomes `RecognitionPreferences.whisperModel` |
| `parakeetModel` | unchanged; becomes `RecognitionPreferences.parakeetVariant` |
| `recognitionEngine` | unchanged; becomes `RecognitionPreferences.engine` |
| `decodingProfile` | unchanged; becomes `RecognitionPreferences.decodingProfile` |
| `modelProcessingMode` + legacy `keepModelReady` | unchanged; both keys keep being written together on every change, exactly as `ModelProcessingMode.persist` already does, for downgrade compatibility |
| `internalDictionary` | unchanged; becomes `RecognitionPreferences.internalDictionaryEntries` |
| `dictationMode`, `recordingLimit`, `badgeTheme`, `customBadgeThemes`, `keepLatestDictation`, `automaticallyChecksForUpdates`, `firstRunDefaultsVersion`, `hasPresentedFirstRunSettings` | out of this document's scope — owned by the Quick Setup / IA and application-preferences docs; untouched by the recognition state model |
| *(new)* `recognitionPresetHint` | added key, optional, absent on upgrade; the on-disk form of `lastAppliedPresetID` — an untrusted display cache per §6, never authoritative |

No existing key is renamed, removed, or reinterpreted. A 3.5.0 build reads a
3.4.x (or earlier) defaults domain through the same `RecognitionEngine
.selected` / `DictationModel.selected` / etc. accessors already in
`Preferences.swift`, with their existing fallback-to-default behavior for
anything unrecognized (a missing key, an unknown raw value from a future
downgrade-then-upgrade). This is the same forward/backward-compatible
pattern the codebase already uses; 3.5.0 keeps it rather than replacing it
with a hard cutover, since deciding on a cutover is a release-process
question outside this task's scope.

**On every launch, not only the first:** the loaded `RecognitionPreferences`
is passed through the reachability check in §5 before anything trusts it —
this is not a one-time migration step, it is the same validation a live
selection goes through. If the persisted engine/model (or engine/variant)
pairing is not currently reachable — a model file went missing, a Parakeet
checkpoint's cache was cleared, a Core ML build marker present in a
previous build is gone in this one — the pairing is repaired using the same
"carry the engine to a model it can run" resolution the gate performs for a
live engine switch (§4, step 1), the repaired value is persisted back, and
no error is surfaced for this alone. It is a silent, deterministic downgrade
to the nearest runnable configuration — identical in kind to what
`resolvedModel(for:)` already does today for a live selection, just run
proactively at launch instead of only reactively on a click.

## 8. Upgrading mid-dictation-session

Installing an update is refused outright while a dictation is in progress —
`installAvailableUpdate` checks `!machine.phase.isBusy` before it will even
start a download, so an update's download and app-replacement can never
*begin* while the user is actively speaking.

One interruption is still possible: an update was armed and its
download/verify is running in the background when the user starts a
dictation, and the install finishes and calls `NSApp.terminate` mid-session.
`applicationShouldTerminate` observes `machine.phase.isBusy` and issues
`.cancel` before shutting the recognizer down — so an in-flight dictation is
*cancelled*, not silently dropped mid-transcript, and per the app's
ephemeral-audio contract its recording and any partial transcript are
deleted rather than carried across the relaunch. Nothing about that
transcript exists for the new process to find or restore.

When the new (3.5.0) version starts, it is a first launch of that binary, so
it runs the §7 migration/reachability path before Settings, Quick Setup, or
a preset match are computed from anything: the engine/model pairing the user
had selected under the old version is checked against 3.5.0's reachability
rules and silently repaired if 3.5.0 can't honor it — for example, if a
capability rule tightened between versions such that the old pairing is no
longer considered valid, or a model this build doesn't ship dropped out from
under a selection made against an older bundle. The user is not asked to
reconfigure recognition just because an update happened to land mid-session;
they see whichever engine/model 3.5.0 could actually resolve their prior
selection to, carried forward exactly as if they had made a live selection
that needed to fall back.

## 9. Cross-references

- Control-level specification (what each thing is, why it can be
  unavailable, cost of changing it): `03-advanced-recognition.md`.
- Preset naming, presentation, and Quick Setup surface: owned elsewhere in
  this design set; this document defines only what a preset resolves to
  (§6) and the invariants its resolution must satisfy.
- Visual component system and general application preferences: owned
  elsewhere in this design set; not addressed here.
