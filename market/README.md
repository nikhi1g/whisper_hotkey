# Private local dictation market kit

Research date: 2026-08-09

This folder turns `whisper_hotkey` from a technically strong project into a
testable market proposition. It is designed for finding a small set of real
users, learning from them without collecting their dictation, and earning the
right to make stronger product claims.

## Executive conclusion

Do not market this as merely “offline dictation.” That category is already
crowded. Apple includes Dictation in macOS; Superwhisper, MacWhisper, Spokenly,
and others offer local modes; and open-source projects such as Handy,
VoiceInk, OpenWhispr, Pindrop, MacParakeet, and VocaMac are active.

The defensible wedge is narrower:

> Private English dictation for Apple Silicon Macs that captures from the
> physical key-down edge, intentionally keeps audio and text off servers,
> stays small at idle, and inserts faithful text without an account or a
> cleanup model changing what the user meant.

That is a strong promise only after the first-word, end-to-end latency,
cross-app reliability, and privacy tests in [proof-scorecard.md](proof-scorecard.md)
pass. Until then, describe the architecture and invite people to help measure
it; do not advertise an unverified superlative.

### Day-zero distribution baseline

A live GitHub API check on 2026-08-09 found 1 repository star, 0 forks, and 0
open issues. Version 4.2.5 was the latest release; its ZIP counter showed 1
download. At this scale, a download may be the maintainer, automation, or a real
user, so it is not an activation metric. It does establish that the project is
starting without an existing audience and should favor direct recruitment over
interpreting passive release counters.

## What matters most now

1. **Prove first-word capture.** Startup delay and lost opening words are
   recurring complaints in competing tools. A repeatable, public test is more
   valuable than another feature.
2. **Make privacy verifiable.** Publish the local data-flow diagram, a network
   audit, ephemeral-file behavior, and exact exceptions for explicit update
   checks. “Trust the privacy policy” is weaker than “inspect and reproduce.”
3. **Remove installation fear.** The current Apple Development-signed,
   non-notarized ZIP and three permissions are the largest conversion risk.
   Run a small technical beta now. Treat paid Developer ID/notarization as a
   business gate before broad consumer outreach.
4. **Measure real dictation, not only read speech.** The existing 2.46% WER for
   Parakeet Unified is useful engineering evidence, but it is 100 LibriSpeech
   utterances on an M5 Pro with a warm model. It is not a universal user WER.
5. **Stay focused.** Competitors already bundle meetings, notes, agents,
   history, rewriting, and cloud sync. The opportunity is a calmer, auditable,
   one-job tool—not a smaller imitation of their suites.

## Asset index

- [strategy-and-use-cases.md](strategy-and-use-cases.md) — audience, jobs,
  positioning, product gaps, and pricing tests.
- [competitive-landscape.md](competitive-landscape.md) — company and
  repository analysis, recurring user pain, and implications.
- [competitive-matrix.csv](competitive-matrix.csv) — filterable factual market
  snapshot.
- [claim-audit.md](claim-audit.md) — exact public-message conflicts to resolve
  before sending traffic.
- [proof-scorecard.md](proof-scorecard.md) — metrics and claim gates for a
  materially better product.
- [90-day-validation-plan.md](90-day-validation-plan.md) — week-by-week route
  from zero audience to a measured pilot.
- [user-research-kit.md](user-research-kit.md) — screener, consent language,
  interview guide, usability tasks, and survey.
- [launch-copy.md](launch-copy.md) — landing page, demo, Show HN, Reddit,
  Product Hunt, and outreach copy.
- [feedback-operations.md](feedback-operations.md) — privacy-preserving intake,
  triage, prioritization, and learning cadence.
- [experiment-backlog.csv](experiment-backlog.csv) — ready-to-run growth and
  product experiments.
- [pilot-tracker.csv](pilot-tracker.csv) — anonymized cohort tracker with no
  transcript field.
- [funnel-model.csv](funnel-model.csv) — explicit hypothetical conversion
  scenarios; replace assumptions with observed values.
- [diagrams.md](diagrams.md) — reusable product and feedback-loop diagrams.
- [source-register.md](source-register.md) — source links, dates, and evidence
  limitations.

## The next seven days

1. Recruit 15 interviews: six developers/security-minded professionals, five
   high-volume writers/operators, and four people who already use dictation to
   reduce keyboard use.
2. Run five assisted first installs before sending an unassisted download to
   anyone. Record only funnel events and task outcomes, never their dictated
   content.
3. Complete 600 scripted first-word trials across 30 participants or devices.
   Zero failures would put the simple rule-of-three 95% upper bound near 0.5%.
4. Publish a 30-second, uncut demo: network disabled, hotkey down, immediate
   speech, text inserted in TextEdit, a browser, and an Electron app.
5. Choose one launch audience based on activation and week-two retention, not
   enthusiasm in interviews.

## Claim discipline

| Claim | Status on 2026-08-09 | Public wording |
| --- | --- | --- |
| Recognition is local | Supported by product architecture and documentation | “Audio and recognition stay on this Mac.” |
| No account or subscription | Supported by current distribution | Safe to say plainly. |
| Four local recognition choices | Supported | Lead with the default outcome, not model names. |
| 2.46% WER | Measured on a narrow, reproducible benchmark | Always include corpus, device, warm-model, and sample qualifiers. |
| Capture begins at physical key-down | Implemented and tested in code | Describe the design; measure user-observed latency before saying “instant.” |
| Never loses the first word | Not yet proven across real hardware/users | Proof-gated. |
| Faster or more accurate than competitors | No paired comparison exists | Do not claim yet. |
| HIPAA/GDPR compliant | No formal product assessment exists | Do not claim. Local processing may reduce exposure, but that is not certification. |
