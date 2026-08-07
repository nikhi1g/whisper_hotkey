# Can we stack layers to get below 1% WER? — an honest assessment

## 1. The question, and the headline answer

The ask: stack roughly five passes on top of the shipping recognizer to push
word error rate below 1% (99%+ word accuracy), covering both word accuracy
and punctuation, robust to slurred speech, at latency low enough for
interactive dictation.

**No — not as a single number across all conditions, and not with five
layers.** Sub-1% WER is achievable on clean, unhurried, read-style speech,
because the shipping engine is already close: Parakeet Unified measures
1.44% on LibriSpeech test-clean today, with no extra layers
(`docs/releases/3.5.0.md`). It is not achievable on real dictation in typical
rooms, and it is very unlikely to be achievable on slurred or heavily
accented speech at interactive latency, because the errors left in that
regime are increasingly acoustic and increasingly resistant to
post-processing — you cannot punctuation-restore your way out of a
mis-transcribed word, and no permissively licensed on-device rescoring LM is
going to reliably fix a substitution the acoustic model was confident about.
Human transcribers, working carefully, land around 4–5% WER on conversational
speech with real disfluency and cross-talk
([Saon et al. 2017](https://arxiv.org/pdf/1610.05256); LDC inter-transcriber
agreement figures in
[Xiong et al. 2017](https://arxiv.org/pdf/1708.08615)). Asking an on-device
model to beat that by 4–5x on hard audio is not a target this project can
promise.

The realistic framing: treat "below 1%" as achievable only on the easy end of
the input distribution (quiet room, clear articulation, common vocabulary),
where the current engine is already there or close. For everything else, the
honest goal is *smaller, well-targeted gains on specific error classes* —
punctuation as a genuinely separate, measurable axis; formatting; a handful
of proper nouns via biasing if it becomes technically possible — not a
uniform "1% everywhere" claim. Five layers is very likely more than pays for
itself; two, maybe three, do.

## 2. What the current numbers actually mean

The 3.5.0 benchmark (`docs/releases/3.5.0.md`) measures Parakeet Unified —
now the bundled default, not a download — at 2.46% combined WER (1.44%
test-clean, 3.63% test-other) over 100 LibriSpeech utterances on an Apple M5
Pro, with 50 ms mean / 41 ms median / 105 ms p95 latency. Parakeet Accurate is
close behind at 2.62% (1.54% / 3.86%), 56 ms mean.

Two things about that number need to be stated plainly before any layer plan
makes sense:

**It says nothing about punctuation.** LibriSpeech reference transcripts are
lowercase and unpunctuated by construction — they come from Project
Gutenberg audiobook alignments normalized for ASR training, not from a
human-annotated punctuation standard. Standard WER scoring normalizes case
and punctuation out of both the hypothesis and the reference before
alignment, and this repository's harness is no exception: `score_parakeet.py`
tokenizes with `[a-z0-9]+(?:'[a-z0-9]+)?` over `casefold()`, so every mark of
punctuation and every capital is discarded before the edit distance is
computed. It has to be — otherwise a transcript that correctly inserts a
comma LibriSpeech does not expect would be scored as an insertion error, and
scoring would actively *penalize* correct punctuation. So 2.46% WER is a
measurement of word identity and word order only. It is entirely possible
for a system to hit 1% word-identity WER and still produce punctuation and
capitalization that reads as unusable — Parakeet's transducer output includes
basic punctuation/casing from training, but nothing here has *measured* it,
because LibriSpeech structurally cannot. Any punctuation quality claim in
this document, or in a future benchmark run, requires a separate
punctuated reference corpus (e.g. Common Voice with its original casing/
punctuation intact, or a hand-punctuated slice of the existing corpus) and a
scoring metric that treats punctuation tokens as first-class edits rather
than normalizing them away.

**It says nothing about slurred, noisy, or spontaneous speech beyond what
test-other already represents.** test-other exists precisely because it is
harder — accents, noisier recording conditions, more acoustic ambiguity — and
the model is already 2.5x worse on it (3.63% vs. 1.44%). LibriSpeech is read
audiobook speech either way: no disfluencies, no false starts, no
overlapping talkers, no genuinely slurred articulation. Real dictation and
"slurred speech" both sit further along that same difficulty curve than
test-other does, and there is currently zero measurement of where on that
curve this app's users actually fall.

## 3. Error taxonomy — what is failing in the remaining ~2.5%

Not all of the residual WER is the same kind of error, and layers that fix
one class do nothing for another. Stacking two layers that address the same
class is close to wasted latency.

- **Acoustic substitution/deletion errors** — the model mishears a phoneme
  sequence as a different word. Dominant cause of the test-clean/test-other
  gap. Fixed only by better acoustics: denoising, a stronger acoustic model,
  or (partially) an LM that makes the wrong word implausible in context.
- **Proper-noun and jargon errors** — out-of-vocabulary or rare words the
  training data underrepresents (names, product names, technical terms).
  Structurally different from generic substitutions: no amount of general
  language modeling fixes a name the model has never heard, but a small
  biasing mechanism that knows the user's own vocabulary can.
- **Formatting / punctuation / capitalization** — entirely unmeasured by the
  current benchmark (see §2). Almost certainly the largest *perceived*
  quality gap for a dictation product even where word-identity WER is
  excellent, because unpunctuated correct words still read as broken output.
- **Disfluency and spontaneous-speech artifacts** — false starts, filler
  words, self-corrections ("the — I mean the other one"). LibriSpeech has
  essentially none of this; real dictation will have some. Not really an
  "error" to fix acoustically — it's a decision about what the transcript
  *should* contain, which is a product/UX question as much as an ASR one.
- **Segmentation/boundary errors specific to this app** — the existing
  Unified overlapping-window regression on audio over 15 seconds
  (`docs/releases/3.5.0.md`) is its own, narrower class: stitching error at
  chunk boundaries, not a general acoustic failure.

## 4. Candidate layers

### 4.1 ROVER / confusion-network voting across multiple systems

Combines 1-best (or n-best) outputs from independent ASR systems by
majority-voting per aligned word slot
([ROVER, Fiscus 1997](https://www.researchgate.net/publication/2397671_A_Post-Processing_System_To_Yield_Reduced_Word_Error_Rates_Recognizer_Output_Voting_Error_Reduction_ROVER);
survey of confusion-network combination showing 0.5–7.3 absolute-point WER
gains in various setups,
[arXiv:1706.07238](https://arxiv.org/pdf/1706.07238)). The gain is real but
depends entirely on the component systems making *different, somewhat
uncorrelated* errors — voting among systems that fail the same way buys
nothing.

- Error class fixed: acoustic substitutions, and only where systems disagree.
- Expected WER delta: hard to state a number without measuring it on this
  corpus specifically; published gains cluster in the 0.5–2 point absolute
  range for well-chosen system pairs, but this app has only two genuinely
  independent architectures available (Parakeet transducer family, Whisper
  encoder-decoder) — running both for every utterance roughly doubles
  latency and adds Whisper's own decode time on top.
- Added latency: running two engines serially or in parallel, plus alignment
  — realistically the slower engine's latency becomes the floor (Whisper
  discovery/decode is already a separate, heavier path in this codebase per
  `Sources/WhisperHotkeyASR/WhisperRecognition.swift`).
- Model size: no new model, reuses what's shipped.
- License: n/a, algorithmic.
- On-device path: yes, this is pure post-processing over text.
- Verdict: only pays for itself if Parakeet and Whisper's remaining errors
  are meaningfully uncorrelated on this corpus, which is unverified. Running
  both engines per utterance is a real latency cost for short dictation
  phrases where median latency is already 41 ms — doubling that is
  proportionally large even if the absolute number stays under typical
  perception thresholds.

### 4.2 N-best rescoring / shallow fusion with an external LM

Either rescores a fixed n-best list post-hoc, or fuses LM log-probabilities
into the transducer's beam search at each step
([overview of the fusion literature and its accuracy/latency tradeoffs,
arXiv:2104.04487](https://www.arxiv-vanity.com/papers/2104.04487/); shallow
fusion for RNN-T specifically,
[arXiv:2012.00133](https://arxiv.org/pdf/2012.00133)). Shallow fusion couples
inference latency directly to LM size because the LM is queried at every beam
step (noted explicitly in
[NVIDIA's NeMo LM fusion docs](https://docs.nvidia.com/nemo-framework/user-guide/latest/nemotoolkit/asr/asr_language_modeling_and_customization.html)),
which is the opposite of what an interactive-latency product wants.

- Error class fixed: acoustic substitutions that are also linguistically
  implausible in context; helps somewhat with rare-word disambiguation when
  the LM has seen the word.
- Expected WER delta: literature reports vary widely by domain and LM size,
  commonly low-single-digit relative improvement on top of a strong acoustic
  model; there is no published number for Parakeet TDT/Unified specifically
  and none should be assumed here without measuring it.
- Added latency: n-best rescoring (score candidates after decode) is cheap
  if the LM is small and the candidate list is short — single-digit
  milliseconds is plausible for a compact CoreML LM. Shallow fusion (LM
  queried every beam step) is much more expensive and directly at odds with
  the low-latency requirement; it should be ruled out for this use case.
- Model size: a usable n-gram or small neural LM is tens to low hundreds of
  MB; large enough to help is large enough to notice in the download size
  budget already under pressure from the 594 MB / 2.4 GB entries in
  `docs/releases/3.5.0.md`.
- License: depends entirely on the LM chosen; needs to be checked per model
  (many capable open LMs are not permissively licensed).
- On-device path: n-best rescoring, yes, in principle, with a compact CoreML
  LM. No specific pre-built model for this exact purpose was found during
  this research; it would need to be trained or adapted.
- Verdict: n-best rescoring (not shallow fusion) is the only version worth
  considering, and only if it is proven, on this corpus, to move the needle
  beyond what Unified already gets from its own training. Not part of the
  recommended stack below because there's no existing, licensed, on-device
  component ready to plug in — it would be a research project, not an
  integration.

### 4.3 Two-pass decoding — fast first pass, selective expensive second pass

Run the cheap path (Unified, ~41 ms median) always; only re-run a slower/more
accurate path when needed. This is a *pattern*, not a specific technique — it
composes with 4.4 below.

- Error class fixed: whatever the second pass is better at (depends on which
  second model is chosen — see 4.4's gating logic).
- Expected WER delta: bounded by the accuracy gap between the two passes.
  Between Unified and Accurate that gap is tiny (2.46% vs 2.62% combined,
  and Unified already *wins* on both accuracy and latency per
  `docs/releases/3.5.0.md`) — so a two-pass Unified→Accurate cascade buys
  essentially nothing, since Accurate is strictly worse on this benchmark.
  Between Unified and Whisper or Cohere Transcribe the gap is larger on
  clean speech (Cohere: 1.13% vs Unified's 1.44% on test-clean) but Cohere is
  629 ms mean — eleven times slower — and *worse* than Parakeet on noisy
  speech (4.21% vs 3.86% test-other), which is exactly the regime where a
  second pass would be triggered. That is close to a contradiction: the
  case where you'd want to spend the extra latency is the case where the
  slow model doesn't actually help.
- Added latency: only on the gated subset of utterances, which is the entire
  point — see 4.4.
- Model size / license: whatever the second-pass model is.
- On-device path: yes, all candidate second-pass models already ship in this
  app.
- Verdict: the pattern is sound but the current set of second-pass
  candidates doesn't clearly help in the regime (noisy/slurred) where you'd
  reach for it. Worth keeping in mind if a genuinely stronger noisy-speech
  model appears later; not actionable today with what's measured.

### 4.4 Confidence-gated selective re-decode

Only re-run the expensive path on segments where the first pass is
uncertain, using token-level confidence rather than always re-decoding
everything. FluidAudio's Parakeet output already exposes token-level
confidence scores per the `tokenTimings` array
([FluidAudio docs](https://github.com/FluidInference/FluidAudio)), so the
gating signal exists in the current dependency without new plumbing.

- Error class fixed: acoustic substitutions specifically in the segments the
  model itself flags as uncertain — a reasonably well-correlated proxy for
  where errors actually are (this is the mechanism explored generally in
  [Confidence-Guided Error Correction for Disordered Speech,
  arXiv:2509.25048](https://arxiv.org/pdf/2509.25048), aimed at disordered/
  slurred speech specifically, which is directly relevant to this ask).
  Note that arXiv:2509.25048 targets *disordered* speech (a clinical/
  pathological category — e.g. dysarthria), which is a narrower and more
  severe condition than "slurred" in the colloquial sense this app's users
  likely mean (tired, mumbled, fast, or accented speech); the technique
  transfers in spirit but the reported gains are not directly applicable
  numbers here.
- Expected WER delta: plausible small improvement over always-run-fast, at a
  fraction of always-run-slow's latency cost, but no number can be stated
  without instrumenting confidence-vs-error correlation on this repo's own
  corpus first — that's a cheap, concrete measurement this repo could run
  before committing to the layer.
- Added latency: bounded — only paid on the fraction of segments below the
  confidence threshold. If that fraction is small (which it should be, given
  Unified is already at 1.44%/3.63%), the amortized cost stays close to the
  fast-path latency.
- Model size: none new if gating triggers into an already-shipped engine.
- License: n/a.
- On-device path: yes — the confidence signal is already emitted by the
  dependency in use.
- Verdict: the most defensible layer in this document. It's cheap to
  prototype (confidence scores already exist), it targets the right error
  class for "slurred speech," and it doesn't cost latency on the common case.
  Recommended, conditional on first measuring that confidence actually
  correlates with error on this corpus (§7).

### 4.5 Punctuation / capitalization restoration as a separate stage

A dedicated model (or rule-based/small-LM system) that adds punctuation and
fixes casing on the raw transducer output, addressing the error class the
current benchmark cannot see at all (§2, §3). This is the layer most likely
to move a user's *perceived* accuracy the most, because unpunctuated correct
text reads as low-quality regardless of word-identity WER.

- Error class fixed: formatting/punctuation/capitalization only — does not
  touch word identity.
- Expected WER (word-identity) delta: none by construction; the metric that
  matters here is a separate punctuation-specific score (e.g.
  punctuation-restoration F1), not WER. This needs its own benchmark corpus
  and metric before any number can be claimed (§7).
- Added latency: a well-scoped restoration model is small relative to the
  ASR model itself; sequence-labeling models for this task are typically
  tens of MB and run in single-digit milliseconds on short utterances (see
  the survey [Păiș & Tufiș, arXiv:2111.10746](https://arxiv.org/pdf/2111.10746)
  for the range of architectures used, from BiLSTM-CRF up to transformer
  taggers). No pre-built, license-clear, CoreML-ready model for this exact
  task was located during this research — candidates found (e.g. general
  on-device LLMs) are heavier than a purpose-built tagger would need to be.
  Note also that NVIDIA's Nemotron streaming ASR models were found to have
  native punctuation/capitalization built into the acoustic model itself
  rather than as a separate stage — worth checking whether Parakeet's own
  training already includes some of this before building a bolt-on (the
  question in §7).
- Model size: purpose-built taggers are small (tens of MB); using a general
  on-device LLM for this single task would be substantial overkill both in
  size and latency.
- License: depends on model chosen; a purpose-built tagger trained in-house
  or from a permissively licensed base avoids the risk entirely.
- On-device path: architecturally straightforward (CoreML sequence tagging
  is a solved problem on Apple Silicon), but no ready-made permissively
  licensed model for this specific task was found — this would likely need
  to be trained or fine-tuned rather than adopted off the shelf.
- Verdict: highest expected user-facing value in this entire document,
  precisely because it addresses the one axis the current benchmark cannot
  measure at all. Recommended as the first thing to build a *measurement*
  for, even before deciding on a specific model, because right now there is
  no way to know if the transducer's built-in punctuation is already good
  enough to skip this layer entirely.

### 4.6 Contextual biasing / hotword boosting from the internal dictionary

The app already has an internal dictionary intended to bias recognition
(referenced in the welcome-window doc's `deliversToInternalDictionaryDraft`
flow), but `Sources/WhisperHotkeyASR/ParakeetRuntime.swift` states explicitly:
"There is no prompt, so the internal dictionary and the Pause Mode context
tail cannot bias the decode; both are dropped before the call." Parakeet is a
transducer, and transducers architecturally have no prompt/context input the
way encoder-decoder models (like Whisper or Cohere Transcribe) do — this is a
real architectural constraint, not a missing feature flag.

- Error class fixed: proper-noun/jargon errors specifically — the one class
  nothing else in this document touches.
- What would actually be required: since the decoder can't be biased
  in-line, the only path is post-hoc — a phonetic or edit-distance match
  between what the model heard and the user's known-vocabulary list, applied
  as a correction pass after decode (e.g. did it output something that
  sounds like a stored proper noun but decoded as a similar-sounding common
  word). This is fuzzy string/phoneme matching over a small user-specific
  list, not a model.
- Expected WER delta: potentially large *for the specific words in the
  dictionary*, and zero for everything else — a narrow, high-value fix
  rather than a general one.
- Added latency: negligible; fuzzy matching over a short user dictionary is
  cheap.
- Model size / license: none needed beyond a phonetic-distance function
  (e.g. a small library or hand-written Soundex/metaphone-style comparator).
- On-device path: yes, trivially — no model at all, just text/phonetic
  post-processing.
- Verdict: worth doing, but scope it honestly — it's a targeted correction
  for a small, known vocabulary, not a general accuracy layer. Cheap enough
  that it's arguably not one of the "five layers" in the spirit the user
  meant, more a small enhancement alongside whatever the main stack is.

### 4.7 Speaker adaptation / voice enrolment

Already covered in full in
`docs/design/future-implementation-notes.md` (2026-08-07 entry). That
document is thorough and should be treated as the canonical source rather
than duplicated here; the short version relevant to this plan: it directly
contradicts the app's current ephemeral-data/no-retention contract, requires
storing a persistent voice embedding or adapted weights, and has no
measured accuracy case yet. It is explicitly framed there as amending the
product's data contract, not a drop-in accuracy layer, and this document
defers to that framing. It's the layer most likely to help with slurred
speech specifically (a model conditioned on one known speaker should handle
that speaker's mumbling better than a generic model), but it's the layer
with the highest cost outside pure ASR engineering — product, privacy, and
consent design all have to happen first.

### 4.8 Audio front-end: denoising, VAD tuning, AGC, dereverberation

The most directly relevant layer to the "slurred speech" and "robust to
noise" part of the question, because it acts *before* any acoustic model
sees the audio rather than trying to fix its output after the fact.

- Error class fixed: acoustic substitutions caused by low SNR, room
  reverb, or clipping/gain issues — not slurring itself (slurred
  articulation is a property of the speech signal, not noise contaminating
  it, so denoising doesn't directly fix mumbled words), but it does address
  the "noisy input" half of the ask and likely a meaningful share of what
  reads as "robust to slurred speech" in practice, since fatigue-mumbling
  and quiet/far-mic speech often co-occur.
  FluidAudio, already a dependency, ships VAD (used today for the app's
  existing energy gate per `docs/design/future-implementation-notes.md`'s
  reference to the -48 dBFS gate) and speaker diarization; a stronger VAD
  pass, AGC, or a denoising front end would sit alongside audio already
  flowing through the app's capture pipeline.
- Expected WER delta: this is genuinely dependent on how noisy this app's
  actual usage is today, which is unmeasured — the LibriSpeech benchmark
  corpus doesn't represent typical dictation acoustic conditions (built-in
  mic, room noise, distance from mic) at all. No number should be claimed
  without first measuring current failure modes on realistic audio.
- Added latency: a lightweight denoiser/AGC running once per utterance
  before the ASR call is typically single-digit milliseconds on short clips;
  this is the cheapest layer in this document, latency-wise.
- Model size: small if a lightweight DSP-based approach (AGC, spectral
  gating) is used instead of a neural denoiser; larger and slower if a
  neural denoiser (e.g. RNNoise-class or a CoreML equivalent) is chosen.
- License: depends on the specific denoiser; several permissively licensed
  options exist (RNNoise is BSD).
- On-device path: yes, well-trodden — this is standard mobile/embedded audio
  engineering, not a research problem.
- Verdict: recommended, and arguably should have been done before any of
  the ASR-side layers, because it's the only layer that could plausibly help
  with input that's bad *before* it reaches the model, which is a
  precondition for anything downstream working well. Needs its own
  measurement (§7) since nothing about the app's actual noise conditions has
  been characterized.

## 5. Recommended stack

The user proposed roughly five layers. This document recommends **two**,
tentatively a **third pending measurement**, and explicitly rejects the rest
for now:

**Recommended:**
1. **Audio front-end hardening (4.8)** — AGC/lightweight denoising ahead of
   the existing VAD gate. Cheapest layer here, addresses input quality
   directly, and is a precondition for everything downstream being
   meaningful.
2. **Punctuation/capitalization restoration as a separate, separately
   measured stage (4.5)** — highest expected user-facing value, and the
   layer that closes the actual gap in what's currently measured (§2). Build
   the measurement (a punctuated reference corpus + punctuation-specific
   scoring) before or alongside the model, because it's currently unknown
   whether Parakeet's built-in punctuation already covers most of this.

**Conditionally recommended, pending a cheap measurement:**
3. **Confidence-gated selective re-decode (4.4)** — the confidence signal
   already exists in the shipped FluidAudio dependency, so the cost to find
   out if this pays for itself is just an offline analysis of
   confidence-vs-error correlation on the existing 100-utterance corpus, no
   new model or integration required to test the hypothesis.

**Rejected, with reasons:**
- **ROVER/multi-system voting (4.1)** — doubles latency by requiring a
  second full engine run per utterance, and there's no evidence yet that
  Parakeet's and Whisper's errors are uncorrelated enough on this corpus to
  make voting worthwhile. Revisit only if 4.4's confidence analysis shows
  many high-confidence wrong answers (which voting could catch but
  confidence-gating alone cannot).
- **N-best rescoring / LM fusion (4.2)** — no ready-made, license-clear,
  on-device LM component exists for this today; would be a research project,
  not integration work, and shallow fusion specifically is latency-hostile
  by construction.
- **Two-pass fast→accurate cascade using existing engines (4.3)** — the
  existing "accurate" alternatives don't actually win in the regime (noisy)
  where a second pass would be triggered; Unified beats Accurate outright
  and beats Cohere on test-other. Nothing to cascade to yet.
- **Contextual biasing (4.6)** — real and worth building, but it's a narrow,
  cheap correction for a small known vocabulary, not a general accuracy
  layer; it doesn't really belong in a "five layers to sub-1% WER" plan
  because its effect is bounded to whatever words are in the user's
  dictionary.
- **Speaker adaptation (4.7)** — already fully scoped in
  `docs/design/future-implementation-notes.md`; not rejected outright, but
  gated on a product/privacy decision (persistent biometric-adjacent data)
  that sits outside a pure accuracy-engineering plan, and has no accuracy
  case measured yet.

That's two firm layers, one conditional, out of the five implied by the ask.
The other three are either not ready to build (4.2), don't clearly help
given what's measured (4.1, 4.3), or are narrower/differently-scoped than a
general accuracy layer (4.6, 4.7).

## 6. Expected end state — stated as ranges, not single numbers

These are reasoned ranges, not measurements — everything here needs the
verification work in §7 before being treated as a claim about the shipped
app.

- **Clean, quiet, read-style dictation (the LibriSpeech test-clean regime):**
  word-identity WER is already close to or at the 1% target today —
  1.44% measured, and it's plausible that audio-front-end hardening plus
  removing any avoidable formatting confusion nudges this toward, at, or
  slightly below 1% on the easiest inputs. Latency stays in the tens-of-ms
  range if confidence-gating rarely triggers on clean audio (it shouldn't).
- **Realistic everyday dictation (typical room, built-in or headset mic,
  normal speaking pace):** somewhere between test-clean and test-other,
  unmeasured today. A reasonable expectation after front-end hardening is
  low-to-mid single digits, i.e. 1.5–3.5% word-identity WER — not
  sub-1%. This is a range, not a number, because nothing about this app's
  actual usage acoustics has been characterized yet.
  Punctuation quality in this regime is currently *unknown even
  directionally* — there is no baseline to state a delta against.
- **Slurred, fatigued, fast, or heavily accented speech:** likely closer to
  or above test-other's 3.63%, possibly noticeably worse depending on
  severity, and this is the regime where confidence-gated re-decode (4.4)
  has the best chance of buying something, bounded by whatever the
  second-pass model's own ceiling is (currently no on-device model
  measured on this repo's corpus meaningfully beats Unified on test-other).
  Getting this regime under ~2% would be a good outcome; sub-1% here is not
  a credible target with technology available today, and is likely not a
  credible target even with meaningfully more engineering investment, given
  that careful human transcribers land at 4–5% on merely conversational
  (not slurred) speech.
- **Latency:** the recommended stack (front-end hardening + punctuation
  stage + conditional confidence-gating) should keep the common case within
  roughly 1.5–2x today's median (41 ms), i.e. still comfortably under 100 ms
  for most utterances, with the gated re-decode path applying only to the
  minority of segments below the confidence threshold. This is a target to
  design toward, not a measured number.

## 7. What would have to be measured to verify any of this

In priority order, cheapest/highest-leverage first:

1. **Confidence-vs-error correlation on the existing 100-utterance corpus.**
   FluidAudio already emits token-level confidence; run it once, bucket
   errors by confidence, and see whether low-confidence tokens are actually
   where the WER lives. This alone determines whether 4.4 is worth building.
2. **A punctuated reference set.** Either hand-punctuate a slice of the
   existing corpus or source a corpus that keeps original casing/punctuation
   (e.g. Common Voice sentences before normalization), and define a
   punctuation-specific scoring metric (edit distance over punctuation
   tokens specifically, not folded into word WER). Without this, nothing
   about 4.5's value is knowable, including whether it's needed at all.
3. **Whether Parakeet's own output already includes usable
   punctuation/casing**, independent of a restoration model — check what
   `ParakeetRuntime.swift` actually returns today before assuming a bolt-on
   stage is necessary. NVIDIA's Nemotron streaming models were found during
   this research to build punctuation into the acoustic model itself,
   which raises the question of whether Parakeet does something similar
   that's currently going unmeasured.
4. **A realistic-noise-conditions benchmark set**, distinct from
   LibriSpeech — recorded on the app's actual capture path (built-in mic,
   typical room), not a curated audiobook corpus. This is the only way to
   get real numbers for §6's "everyday dictation" range instead of a
   reasoned guess.
5. **A correlated-error check between Parakeet and Whisper** on the existing
   corpus (do they get the same utterances wrong?) before investing in 4.1
   — if their errors overlap heavily, ROVER is a dead end regardless of
   latency cost.
6. **Latency under the recommended stack, measured, not estimated** — once
   front-end hardening and confidence-gating exist even as prototypes, the
   50 ms / 41 ms / 105 ms numbers need to be re-run the same way 3.5.0's
   were, on the same corpus, for a fair before/after comparison.

## 8. Open questions and risks

- **Is "slurred speech" in the ask about dysarthria/pathological speech, or
  about ordinary mumbled/fatigued/fast speech?** These have very different
  answers. The confidence-guided correction literature found during this
  research (arXiv:2509.25048) specifically targets disordered speech and
  reports gains in that narrower clinical context; those numbers should not
  be assumed to transfer to "tired and mumbling" use.
- **Risk of measuring the wrong thing.** Every WER number in this document
  and in the shipping benchmark is a word-identity number. If the actual
  user complaint driving this ask is about punctuation or formatting rather
  than misheard words, the entire "get below 1% WER" framing is solving the
  wrong problem, and §4.5's measurement work should happen first, not last.
- **Risk of the front-end layer masking rather than fixing.** AGC and
  denoising can introduce their own artifacts (over-compression, musical
  noise from aggressive spectral gating) that hurt WER on already-clean
  audio while helping on noisy audio. Needs A/B measurement on both
  conditions, not just the noisy one.
- **Confidence is a proxy, not ground truth.** A model can be confidently
  wrong — high confidence on a plausible-sounding wrong word is exactly the
  case 4.4 cannot catch, and is one of the few cases 4.1 (voting across
  independently-trained systems) actually could. If §7's confidence analysis
  shows a nontrivial rate of confident errors, that's the signal to revisit
  the ROVER rejection above.
- **License risk compounds with every new model.** Each layer that adds a
  model (LM for rescoring, punctuation tagger, denoiser) reopens the
  license-and-Apple-Silicon-availability search that `docs/releases/3.5.0.md`
  already shows is not a given — several strong candidates in that survey
  had no CoreML path or were CC-BY-NC. Nothing in this document should be
  treated as "and a suitable model exists" until one is actually found and
  verified, license included.
- **This document makes no latency claims that have been measured on this
  repo's benchmark harness.** Every latency figure in §4 and §6 beyond the
  already-shipped 3.5.0 numbers is a reasoned estimate from general
  knowledge of model classes, not a run of `Benchmarks/`. Treat them as
  planning inputs, not commitments.
