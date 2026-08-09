# Proof scorecard

This scorecard defines what “materially better” means. It prevents the team
from substituting decoder benchmarks for the experience a person has when they
press the hotkey and speak immediately.

## Claim levels

| Level | Meaning | Allowed wording |
| --- | --- | --- |
| 0 — designed | Architecture exists, but no representative measurement | “Designed to…” or a concrete description of the mechanism |
| 1 — lab verified | Deterministic scripted test passes on named hardware | “In our test on…” with device, version, corpus, and sample size |
| 2 — cohort verified | Representative users and apps meet a preregistered threshold | “Across N testers / N trials…” with protocol link |
| 3 — comparative | Paired, same-audio comparison beats named alternatives with uncertainty reported | “Lower/faster than…” with result and confidence interval |

No superlative should be public below Level 3.

## Complete latency model

Measure separate clocks; never collapse them into “latency.”

- `capture_start`: physical key-down to first usable microphone buffer;
- `visual_start`: physical key-down to visible listening state;
- `audio_commit`: physical key-down to first sample committed to the canonical
  private recording;
- `release_to_insert`: completion edge to final text present in the target;
- `speech_end_to_insert`: last voiced frame to final text present;
- `cold_first_use`: first accepted dictation after launch;
- `warm_repeat`: second through twentieth dictations with the selected policy.

Report p50, p95, p99, maximum, sample count, Mac model, RAM, macOS, microphone,
input behavior, processing mode, recognition choice, and app. A mean alone
hides the tail failures that break trust.

## Proposed cohort and protocol

Recruit 30 participants or independently configured Macs:

- 10 base-generation/low-memory systems (for example M1/M2, 8–16 GB);
- 10 mid-generation systems (M3/M4, mixed memory);
- 10 current/high-end systems (M5 family, mixed memory).

Each runs 20 short, supplied utterances, for 600 total dictations. Randomize
the start of speech after physical key-down at 0, 50, 100, and 200 ms—five
trials per offset. The pack should include:

- plain email prose;
- a technical prompt with product names and acronyms;
- numbers, punctuation, and proper names;
- quiet room and moderate prerecorded background noise;
- at least three English accent groups, with participants self-describing only
  if they choose.

Use supplied non-sensitive text. Do not ask participants to dictate work,
patient, client, source, credential, or personal content.

For cross-app reliability, each participant completes at least one task in
TextEdit, Safari or Chrome, Slack or another Electron app, and VS Code/Cursor
or Terminal. A smaller internal lab matrix should also cover Notes, Microsoft
Word, Google Docs, and a secure text field that must reject insertion.

## Material advantage gates

| Outcome | Metric | Minimum gate before public claim | Stretch outcome |
| --- | --- | ---: | ---: |
| Immediate capture | `capture_start` | p95 < 100 ms and p99 < 150 ms on every supported device tier | p95 < 50 ms |
| First-word retention | Opening reference token preserved | 0 losses in 600 immediate-speech trials | 0 losses in 2,000 trials |
| Visible readiness | `visual_start` | p95 < 100 ms | p95 < 50 ms |
| Warm completion | `release_to_insert`, utterances <=10 s, default choice | p50 < 250 ms and p95 < 500 ms | p95 < 300 ms |
| Cold completion | First dictation after launch | p95 < 1.5 s while capture still retains the opening | p95 < 750 ms |
| Exact delivery | One final insertion in intended target | >=99.5% of 600 trials; no double insertions | >=99.9% over 2,000 |
| UI lifecycle | Returns to idle with no stuck badge/session | 0 stuck states in 600 trials | 0 in 2,000 |
| Cancellation | No insertion and private audio deleted | 100% in 100 forced abort/failure cases | 100% plus external file audit |
| Privacy | Outbound connections during dictation | 0 across 1,000 sessions; explicit update action tested separately | Independent reproducible audit |
| Idle behavior | Microphone/helper/CPU under Decode After Speaking | Mic inactive, no helper, average CPU <0.1% over 10 min | Publish RSS/energy comparison |
| Accuracy | WER on the consented application pack | No worse than best tested local comparator by >0.5 percentage points | >=15% relative WER reduction with paired 95% CI excluding zero |
| Correction cost | Edits needed per 100 dictated words | Median <=2 semantic corrections / 100 words | 25% fewer correction keystrokes than comparator |
| Activation | Install to first successful dictation | >=60% assisted; >=40% unassisted while unnotarized | >=70% unassisted after notarization |

### Why 600 trials matters

If an event is observed zero times in `n` independent trials, the simple
rule-of-three approximation puts its 95% upper rate near `3/n`. With zero
first-word losses in 600 trials, the upper bound is about 0.5%. With zero in
2,000, it is about 0.15%. This does not prove the event is impossible, and
correlated trials on the same machines weaken the interpretation; report both
participant and trial counts.

## Recognition measurement

The shipping benchmark currently reports these warm decode-only results on 100
LibriSpeech test-clean/test-other utterances on an Apple M5 Pro:

| Recognition choice | Combined WER | p50 decode | p95 decode |
| --- | ---: | ---: | ---: |
| Parakeet Unified | 2.46% | 45 ms | 117 ms |
| Parakeet Balanced | 2.62% | 56 ms | 88 ms |
| Parakeet Fast | 3.88% | 33 ms | 55 ms |
| Whisper Turbo Smart Decode | 4.04% | 303 ms | 365 ms |

These numbers are useful but do not include microphone startup, finalization,
insertion, user accent distribution, spontaneous speech, jargon, or app
behavior. Version 4.2.5 did not lower these WER values; it changed capture and
lifecycle integrity.

### Application corpus scoring

For every utterance, store only the supplied reference ID and the output from
that supplied, non-sensitive script with consent. Score:

- WER for general words;
- character error rate for proper names, email addresses, and code-like terms;
- first-token retention separately from WER;
- semantic error count (negation, number, name, or action changed);
- correction keystrokes and time-to-usable-text;
- unintentional rewrite rate.

Use the exact same audio for paired model/product comparison where permitted.
Bootstrap by utterance and participant; publish confidence intervals, not just
the winning point estimate.

## Four-choice lab matrix

Do not make 30 users test every configuration. Run a lab matrix first:

- 4 recognition choices;
- 3 processing modes;
- 3 input behaviors;
- 3 hardware tiers;
- 20 utterances per cell.

That is 2,160 lab dictations. Use it to locate regressions and select a default.
The user cohort should test the default plus only one relevant alternative.

## Comparator protocol

Compare against Apple Dictation, one polished cloud product, and two serious
local alternatives. Use the same Mac, microphone, application, reference text,
and audio replay where the product accepts replayed input. Disclose that vendor
settings and model versions can change.

Useful comparisons:

- Apple Dictation: baseline installation and live insertion;
- Aqua or Wispr Flow: polished cloud speed and correction burden;
- Handy or Spokenly local: free cross-platform local baseline;
- Pindrop or MacParakeet: notarized native local baseline.

Do not publish a ranking from one paragraph or from incompatible settings.

## Evidence package to publish

1. frozen utterance manifest and consent statement;
2. hardware/software/configuration manifest;
3. raw de-identified timing and outcome rows;
4. scoring definitions and uncertainty method;
5. screen recording of the first-word protocol;
6. network and temporary-file audit procedure;
7. failures and exclusions, not only the winning result;
8. exact release hashes.
