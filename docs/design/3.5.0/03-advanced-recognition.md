# 3.5.0 Design — Advanced Recognition Settings

Scope: the controls inside Advanced Recognition that Quick Setup's presets
(Fastest / Balanced / Most Accurate — owned and presented by the Quick Setup
design doc) resolve into and that a user can also set individually. This
document specifies what each control is, what it supports, why it can be
unavailable, and what changing it costs. It does not specify layout, copy, or
the preset UI itself; those belong to the Quick Setup and visual-system docs.
The state guarantees that keep these controls from ever expressing a
contradictory combination are specified in
[`04-settings-state.md`](04-settings-state.md); this document is the catalog
of controls those guarantees apply to.

Ground truth: `Sources/WhisperHotkeyCore/Preferences.swift`,
`Sources/WhisperHotkeyASR/WhisperRecognition.swift`,
`Sources/WhisperHotkeyASR/ParakeetModelInstaller.swift` /
`ParakeetRuntime.swift`, `Sources/WhisperHotkeyApp/
WhisperHotkeyApplicationDelegate.swift`, `run.sh`, and
`docs/releases/3.3.6.md` for the failure modes this redesign must make
structurally impossible rather than fix case by case.

## 1. Recognition Engine

**Best suited for:** choosing the underlying speech engine architecture —
this is the one choice that changes everything downstream (decoding
strategy, prompt support, process model, and which models are even relevant).

**Supports:** four engines, each with a fixed capability profile (§7):
whisper.cpp Metal, whisper.cpp Core ML Encoder, WhisperKit, Parakeet.

**Why it may be unavailable:**
- **whisper.cpp Core ML Encoder** only exists in builds carrying a build-time
  Core ML marker (`WHISPER_HOTKEY_COREML=1` in the process environment, or a
  bundled `CoreMLEnabled` resource). This is fixed for the life of the running
  process — it is not something Settings can turn on, and it cannot become
  available mid-session no matter what the user installs.
- Any engine (including the two that have no build gate) is unavailable
  when it cannot run *any* whisper model or Parakeet checkpoint the app knows
  about. This is evaluated across every model, never only the one currently
  selected — see the "dead end" failure mode in §7.3 of `04-settings-state.md`
  and its root cause in `docs/releases/3.3.6.md`.

**Changing it:** no app restart. It is a live reload of the recognizer's
runtime configuration — the current model unloads and the new one loads
lazily on the next preload or dictation. If the target engine's model or
checkpoint is not yet installed, an explicit install/download step (progress,
size, Cancel) runs first, and the engine only actually changes if that step
succeeds; a cancelled or failed install leaves the previous engine selected.

## 2. Recognition Model

**Best suited for:** trading download size and memory against transcription
accuracy, within whichever engine is active.

**Supports:** whisper.cpp Metal, whisper.cpp Core ML Encoder, and WhisperKit
all select from the same four whisper checkpoints (Base / Small / Medium /
Large-v3 Turbo Q5) through one shared preference. Parakeet selects from its
own two checkpoints (Fast / Accurate) through a separate preference, so
switching engines never overwrites the other family's choice — this is
deliberate in the current code (`WhisperHotkeyPreferenceKeys.parakeetModel`'s
doc comment) and the 3.5.0 model keeps it.

**Why it may be unavailable:** a whisper model is unavailable for a
*specific* engine when that engine's required file layout is missing for it:
- whisper.cpp Metal needs the plain `ggml-*.bin` file, bundled (Base, Small,
  Large-v3 Turbo Q5) or installed.
- whisper.cpp Core ML Encoder needs that same file *and* a compiled Core ML
  encoder directory under `~/.cache/whisper/coreml`.
- WhisperKit needs a five-file model folder under `~/.cache/whisperkit`
  (`AudioEncoder.mlmodelc`, `MelSpectrogram.mlmodelc`, `TextDecoder.mlmodelc`,
  `tokenizer.json`, `tokenizer_config.json`).

A Parakeet checkpoint is unavailable when it has not been downloaded and
Core-ML-compiled yet.

**Changing it:** no restart. Picking an installed model/checkpoint is a live
reload, same as an engine change. Picking one that isn't installed:
- For the whisper.cpp Metal plain file, Medium is fetchable in-app (Base,
  Small, and Large-v3 Turbo Q5 already ship bundled; Medium alone is
  downloadable because all four together exceed GitHub's release-asset
  limit) — same explicit, cancellable, checksum-verified flow as Parakeet.
- Core ML Encoder and WhisperKit models have **no in-app download path at
  all**. They are only ever produced by the external `run.sh` bootstrap
  script with pinned SHA-256 verification, per the product's no-background-
  network-request rule. If a user selects Core ML Encoder or WhisperKit
  without having run that bootstrap for the target model, Settings can only
  say so — it cannot offer a download button the way it can for Medium or
  Parakeet.

## 3. Processing Mode

**Best suited for:** trading idle memory and finish latency against
cross-chunk transcript context.

**Supports** all four engines uniformly — this governs the recognizer
actor's lifecycle (`WhisperRecognizer.setKeepsModelReady` /
`reloadSelectedModel`), not any engine's internal decode step, so it applies
the same way regardless of which engine is active:
- **After Recording** — loads and decodes only during transcription; lowest
  idle memory.
- **Model Ready** — keeps the resolved model loaded between dictations;
  no per-dictation load latency.
- **Decode While Speaking** — also predecodes rotating chunks during capture
  for the shortest finish time, at the cost of slightly less cross-chunk
  context (each chunk decodes with only its own audio, not the whole
  session).

**Why it may be unavailable:** never categorically unavailable. It is always
offered for whatever engine/model pairing is currently resolved.

**Changing it:** no restart. Takes effect starting with the next session. If
the new mode keeps the model ready, the recognizer preloads immediately in
the background (visible only as a brief loading readiness state, not a
blocked picker).

## 4. Custom Vocabulary

**Best suited for:** biasing decoding toward names, jargon, and phrases the
model would otherwise mis-transcribe.

**Supports:** whisper.cpp Metal, whisper.cpp Core ML Encoder, and
WhisperKit — anywhere `supportsPromptConditioning` is true for the active
engine. Entries fold into one bounded prompt string (≤ 320 characters, ≤ 64
entries) passed as the decode prompt.

**Why it may be unavailable:** the active engine is Parakeet. Parakeet is a
transducer with no prompt or prefix-conditioning input whatsoever — there is
no "worse" version of vocabulary biasing for it to fall back to, the input
does not exist. Per the fix already made in 3.3.6, the list itself is never
cleared, disabled for editing, or hidden when Parakeet is active — entries
persist and resume affecting decoding the instant the user switches back to
a prompt-capable engine. What must not happen is the row reading as "on"
while Parakeet silently ignores it; it must visibly present as inert
whenever `supportsPromptConditioning(selectedEngine) == false` (§4, R2 of
`04-settings-state.md`).

**Changing it:** no preparation, no restart. Persists immediately and is
live for the very next dictation.

## 5. Decoding Strategy

Not separately named in this document's brief but load-bearing enough to
specify: this is the whisper.cpp-only Precision / Smart Decode control
(`DecodingProfile`).

**Best suited for:** trading a small chance of a lower-quality fast pass for
shorter latency, strictly within whisper.cpp's own beam search.

**Supports:** **Precision** (fixed five-beam decoding, consistent accuracy)
and **Smart Decode** (a confident fast pass, with a five-beam retry when the
fast pass is uncertain) — whisper.cpp Metal and whisper.cpp Core ML Encoder
only (`usesWhisperDecoding`).

**Why it may be unavailable:** the active engine doesn't run whisper.cpp's
decode loop at all. WhisperKit owns its own decoder with fixed parameters
(temperature 0, two-step fallback, top-K 5) that this control has no lever
into. Parakeet's transducer has no beam search to configure — there is
nothing this control could mean for it. Same inert-not-hidden treatment as
Custom Vocabulary: the stored value is untouched so a user's choice is
restored the moment they return to a whisper.cpp engine.

**Changing it:** no restart, live reload of the next helper launch's
strategy argument. Ignored entirely (and must render inert, not simply
absent) when `usesWhisperDecoding(selectedEngine) == false`.

## 6. Engine Availability

Not a preference — a derived indicator the Engine picker consults to decide
what is selectable and what explanation to show for what isn't.

**Best suited for:** telling the user, inline, *why* an engine is greyed
out, distinguishing "not installed yet" (fixable from Settings) from "not
supported by this build" (not fixable from Settings at all) from "no bundled
model reaches it" (fixable only via `run.sh`).

**Supports:** computed per engine as "can this engine run at least one model
or checkpoint the app knows about" — never gated on whichever model happens
to be selected for a *different* engine. This is the direct fix for the
3.3.6 dead end where an uninstalled whisper model greyed out every whisper
engine at once, with no way back once Parakeet was active.

**Why it may be unavailable:** see §1's build-gate and no-reachable-model
cases; the degenerate all-engines-unavailable case (a corrupted install with
even the bundled Base model missing) is not a picker state at all — see
`04-settings-state.md` §5, R4.

**Changing it:** not user-set. Recomputed at launch, after any install or
download completes, and whenever Settings regains focus — never cached
across a change to the filesystem or a build capability.

## 7. Model Readiness

A derived runtime status, distinct from the Processing Mode *preference*
that requests it. Model Readiness is *what is currently true*; Processing
Mode is *what was asked for*.

**Best suited for:** a small status affordance near Processing Mode, showing
whether the recognizer is currently idle, warming up, ready, or failed —
so "Model Ready" reads as a request whose fulfillment can be inspected, not
a black box.

**Supports:** idle / loading / ready / failed
(`WhisperReadiness`), reported per the currently active engine's own runtime
object — the owned helper subprocess for whisper.cpp, the in-process
`WhisperKit` instance, or the in-process `ParakeetRuntime`/`AsrManager`.

**Why it may be unavailable:** reports `.failed` after a helper crash, a
WhisperKit load failure, or a Parakeet load failure (for example, an install
that completed but whose cached files were later removed externally). This
is always transient — the next successful preload clears it.

**Changing it:** not user-set, and critically **never persisted**. It always
starts `.idle` on launch regardless of what it was when the app last quit;
persisting a runtime status is exactly the class of bug this redesign rules
out (§2 of `04-settings-state.md`).

## 8. Compatibility Restrictions — Capability Matrix

| | whisper.cpp Metal | whisper.cpp Core ML Encoder | WhisperKit | Parakeet |
|---|---|---|---|---|
| Decoding control | whisper.cpp beam/greedy — Precision / Smart Decode | same as Metal | none: WhisperKit's own fixed decoder | none: transducer, no beam search |
| Prompt / custom vocabulary | yes | yes | yes | **no** — accepts no prompt at all |
| Process model | owned helper subprocess | owned helper subprocess | in-process | in-process |
| Helper-crash fallback | retries via the bundled `whisper-cli` command line | **none** — fails outright; there is no CPU/CLI Core ML equivalent shipped | n/a (no helper) | n/a (no helper) |
| Model unit | 4 shared whisper checkpoints | 4 shared whisper checkpoints + a per-model Core ML encoder directory | 4 shared whisper checkpoints, WhisperKit folder layout | **its own 2 checkpoints** (Fast / Accurate), separate preference key |
| Model sourcing | bundled (Base, Small, Large-v3 Turbo Q5) or in-app download (Medium) | **external only** — `run.sh` bootstrap with pinned SHA-256, never from within the running app | **external only** — same `run.sh` path | **downloads on demand** — explicit in-app install step, cached by FluidAudio outside the whisper model directories |
| Build gating | none | requires a build-time Core ML marker, fixed per process | none | none |

Read this matrix as the source of truth for §1–§5's capability claims; if a
future control's spec disagrees with a row here, the row wins.

### Restriction rules

These are phrased as rules a control must obey, not just facts about the
engines — each is the direct antidote to a class of bug named in
`docs/releases/3.3.6.md`.

- **R1 — no unrunnable pairing.** An engine may only be selected together
  with a model/checkpoint it can actually run. Nothing may write an engine
  preference and a model preference independently; a change to either must
  resolve the other to a compatible value (or trigger an install) before
  either is persisted. Formalized in `04-settings-state.md` §4.
- **R2 — inert, not hidden, not silently ignored.** Decoding Strategy and
  Custom Vocabulary remain visible and keep their stored values when the
  active engine doesn't use them; they render as inert rather than either
  disappearing (which loses the user's setting from view) or staying fully
  interactive while doing nothing (the 3.3.6 "surfaces that lied" bug).
- **R3 — build-unsupported is not the same message as not-yet-installed.**
  Core ML Encoder being absent from this build and Core ML Encoder simply
  lacking an installed model must read as different explanations, because
  only one of them is something Settings can fix.
- **R4 — availability is computed against every model, not the selected
  one.** The Engine picker's availability check must range over all models
  known to the app for each candidate engine, never only whichever model the
  *currently selected* engine happens to have chosen. This is the exact
  defect that produced the 3.3.6 dead end.
- **R5 — rebuild before you select.** Any control whose option set depends
  on the active engine (the Model row: four segments for whisper engines,
  two for Parakeet) must have its option set rebuilt for the *new* engine
  before any selection is applied against it, and every write to it must be
  bounds-checked against its current option count. This is the direct fix
  for the 3.3.6 freeze, where selection was applied before the row was
  rebuilt and a two-segment control was asked for segment three.
