# 3.5.0 settings redesign: integration and acceptance

Reconciles `01`–`06`. Where those documents disagree, this one wins. Written
after all three workstreams landed, against an independently built inventory of
the 3.3.6 settings surface.

3.5.0 replaces the AppKit settings window outright, so the binding constraint
throughout is that no setting may be lost by omission.

## 1. Conflicts resolved

### D1 — Presets must be able to reach Parakeet

`02` and `04` both resolve all three presets to `whisperCppMetal`. Neither
mentions Parakeet in any preset. That is the largest gap in the combined
design, and it is a product error rather than a stylistic one.

The repository's own benchmark (`Benchmarks/Parakeet/`, 100 LibriSpeech
utterances, Apple M5 Pro, scored with the same word-error math as the whisper
benchmark) measures:

| Configuration | WER | Mean latency |
|---|---:|---:|
| Turbo Q5 + Metal, Precision | 4.32% | 321 ms |
| Turbo Q5 + Metal, Smart Decode | 4.04% | 305 ms |
| Parakeet Fast | 3.88% | 34 ms |
| Parakeet Accurate | 2.62% | 56 ms |

Parakeet Fast beats every whisper model the app ships on accuracy while being
roughly nine times faster. Presets are the only recognition control a
nontechnical user ever sees, so resolving them exclusively to whisper makes the
best available configuration reachable only by users who open Advanced
Recognition and understand engine terminology — precisely the users presets
exist to serve.

**Resolution.** Presets resolve over *installed* configurations. Ranking within
each preset prefers Parakeet where its checkpoint is already present, and falls
back to the whisper resolution in `02` §7 otherwise. Where Parakeet would win a
preset but is not installed, Quick Setup shows an optional, dismissible upgrade
offer that names the size and uses the existing 3.3.6 install flow
(confirmation, progress panel, working Cancel). It is never silent and never
blocks completion of Quick Setup.

This keeps `02`'s one-minute path intact: a user who ignores the offer still
gets a working, fully local configuration from bundled models.

### D2 — Most Accurate must not resolve to Medium English

`04` §7 resolves Most Accurate to Medium English. `02` §7 explicitly refuses
to. `02` is correct and this is not a close call.

Medium is the one model not bundled; selecting it triggers a 1.5 GB download.
`AGENTS.md` states the running app never downloads a model, and a preset that
silently pulls 1.5 GB is the exact defect class 3.3.6 was released to fix, in
which Parakeet fetched several hundred megabytes behind a Transcribing badge.

Most Accurate resolves to the best already-installed configuration. Medium
stays reachable through Advanced Recognition, where its size and download
prompt are shown honestly.

### D3 — Balanced keeps RAM tiering

`04` fixes Balanced to Large-v3 Turbo Q5. `02` tiers it by installed RAM,
mirroring `FirstRunPerformanceProfile.recommended`, which is already shipped
and tuned. A fixed Turbo assignment regresses 8 GB machines. `02` wins.

### D4 — Smart Decode for Fastest and Balanced, Precision for Most Accurate

`02` assigns Precision to Balanced; `04` assigns Smart Decode. `04` wins, on
measurement rather than preference: in `Benchmarks/Results/latest.json` the
adaptive profile scores 4.04% WER at 305 ms mean against Precision's 4.32% at
321 ms. Smart Decode is better on both axes for this corpus, because it accepts
a confident greedy pass and retries only uncertain audio with the five-beam
decoder.

Most Accurate keeps Precision, which is deterministic five-beam with no greedy
shortcut. That is a defensible meaning for the label even though the aggregate
number favors adaptive.

### D5 — Recording Limit stays in Dictation Behavior

`06` argues for Application; `01` places it in Dictation Behavior. It bounds a
single capture, which is dictation behavior, not an app-level preference.
`01` wins.

### D6 — Settings chrome decouples from the badge theme

`05` decouples Settings and User Guide chrome from the badge theme; today they
are coupled, and `docs/ARCHITECTURE.md` documents that coupling. Accepted: a
native `Settings` scene that repaints itself to a dictation-badge palette is the
opposite of the platform-native direction this redesign exists to take. The
badge keeps its themes; Settings uses semantic system colors.

`docs/ARCHITECTURE.md` and `purpose.md` must be updated in the same change that
implements it. Flagged by `05` rather than done silently, which was correct.

### D7 — One permission surface, not two

`01` folds the Setup window's permission rows into Quick Setup. `06` adds a
Settings-resident permission status. Unified: permissions are presented once,
in Quick Setup, rendered with `05`'s status indicator component. `06`'s
authorization-state rules still govern how each state is described.

### D8 — Dictation Behavior control design is unassigned

`01` §6 correctly flags that Custom Words, Recording Limit, and Keep Last
Dictation are placed but not designed by any workstream. The orchestrator owns
them at implementation, reusing `05`'s row and section components. No new
component is required.

## 2. Inventory completeness

`01`'s inventory was validated line by line against an independently built list
of the 3.3.6 surface: 11 settings-window rows across 4 sections, 15 persisted
keys, and 5 adjacent surfaces. It is complete, and more complete than the
independent list in one respect — `dictationHotkey` is a real persisted key
that lives as a bare string literal in the delegate rather than in
`WhisperHotkeyPreferenceKeys`. Migration must handle it, and the redesign
should move it into the keys enum.

Two removals accepted, both argued rather than assumed:

- Footer summary chips. A tabbed scene shows each pane's own values.
- The Setup window's duplicate login toggle. Two live controls for one
  `SMAppService` registration can disagree with each other.

Not settings, but touched by the redesign and easy to leave dangling:

- The menu bar's "Open Setup" item, if Setup folds into Quick Setup.
- The model download progress panel, which must remain reachable from both
  Quick Setup (D1's upgrade offer) and Advanced Recognition.

## 3. Acceptance criteria

- A new user completes setup without opening Advanced Recognition, and without
  encountering the words engine, model, decoding, checkpoint, or beam search.
- Every setting in `01`'s inventory is reachable, except the two documented
  removals.
- Advanced users retain direct engine, model, decoding, and processing control.
- No unsupported combination is selectable, per `03`'s capability matrix and
  `04`'s selection gate. Specifically: no engine paired with a model it cannot
  run, no custom vocabulary shown active on an engine that ignores it, no
  preset label left selected after overrides diverge from it.
- Every disabled control explains why it is disabled.
- Runtime status is never persisted as a preference.
- Full keyboard traversal and VoiceOver labeling per `05`.
- Layout holds at the minimum supported window size.
- Recognition status changes do not refresh the whole settings scene.
- A cancelled or failed model install leaves the previous configuration intact,
  preserving the 3.3.6 behavior.

## 4. Implementation sequencing

1. Settings state model and migration (`04`), behind no UI. Includes moving
   `dictationHotkey` into the keys enum.
2. Component system (`05`).
3. Quick Setup (`02` + D1), the pane that must be right.
4. Advanced Recognition (`03`).
5. Dictation Behavior (D8).
6. Application and Appearance (`06`), including the SMAppService migration.
7. Delete the AppKit settings window; update `ARCHITECTURE.md` and
   `purpose.md` per D6.

Each step ships with tests for state transitions and for the invalid states
`04` makes unreachable. The AppKit window is removed only in step 7, so no
intermediate commit leaves settings worse than 3.3.6.
