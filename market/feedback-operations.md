# Feedback operations

The product’s privacy posture should survive the feedback process. Do not build
a cloud transcript collection system to improve a local dictation app.

## Data minimization

Collect by default:

- anonymous participant/test ID;
- app version and release hash;
- Mac chip/RAM, macOS, target app, microphone;
- input behavior, processing mode, recognition choice;
- timestamps or latency buckets;
- attempted/successful count;
- first-word loss, double insertion, wrong target, stuck UI, cancellation, or
  restart as booleans;
- sanitized failure code and steps;
- optional satisfaction/correction count.

Do not collect by default:

- audio;
- transcript text;
- clipboard contents;
- screen content;
- app document content;
- dictionary entries;
- filenames, contacts, employer/client identity, credentials, or medical/legal
  information;
- continuous background analytics.

Supplied public test sentences may be stored with consent because the content
is known in advance. Keep participant contact information in a separate table.

## Separate exceptional-content consent

If a bug cannot be reproduced with public text, ask for a separately consented,
purpose-limited artifact. State exactly:

- which audio/text/screen portion is needed;
- who can access it;
- where it is stored and encrypted;
- the deletion date (default no more than 30 days);
- that refusal does not remove beta access;
- how the participant can withdraw it early.

Never make content upload the default bug-report path.

## Intake lanes

| Lane | Use | Response target |
| --- | --- | --- |
| Safety/privacy | Audio/text retention, undisclosed network, secure-field insertion, permission misuse | Acknowledge same day; pause release if credible |
| Data loss/lifecycle | Lost opening, missing result, double insertion, wrong target, stuck recording/UI | Acknowledge within one business day |
| Recognition quality | Supplied-script error, jargon, number/name error | Batch weekly by workflow/model |
| Activation | Download, Gatekeeper, permission, restart, first-use confusion | Review after every five attempts |
| Enhancement | New mode, language, integration, cleanup, trigger | Validate job/frequency before roadmap |
| Research insight | Workaround, competitor comparison, reason for adoption/churn | Synthesize weekly |

## Normalized problem codes

- `CAP-FIRST` — opening token/syllable lost;
- `CAP-GAP` — missing middle audio or overflow;
- `HOT-CONFLICT` — ordinary shortcut or click interfered;
- `HOT-MISS` — intended trigger ignored;
- `REC-WORD`, `REC-NAME`, `REC-NUM`, `REC-PUNCT` — recognition class;
- `INS-NONE`, `INS-DUP`, `INS-TARGET`, `INS-CLIP` — delivery class;
- `UI-STUCK`, `UI-LATE`, `UI-WRONG` — presentation/lifecycle;
- `PRV-NET`, `PRV-FILE`, `PRV-LOG`, `PRV-PERM` — privacy class;
- `ACT-DOWNLOAD`, `ACT-GATEKEEPER`, `ACT-PERM`, `ACT-MODEL`, `ACT-KEY` — activation;
- `PERF-COLD`, `PERF-WARM`, `PERF-IDLE` — performance.

One report may have one primary and up to two secondary codes.

## Weekly evidence review

Every week, produce a one-page synthesis:

1. cohort and exposure: how many users/sessions could have seen the problem;
2. new signals by code and severity;
3. reproduced vs unconfirmed reports;
4. the top three jobs affected;
5. qualitative quotes stripped of content/identity;
6. metrics before and after the last change;
7. decision: fix, test, watch, decline, or ask for more evidence;
8. what will be communicated back to reporters.

Publish a short “You said / We measured / We changed / Result” note to the
cohort. Closing the loop is a retention mechanism and a trust signal.

## Priority score

Use a transparent score rather than raw request count:

`priority = reach × severity × segment_fit × confidence / effort`

Score each 1–5, except effort 1–8.

- **reach:** share of observed users/exposures;
- **severity:** 5 for privacy/data loss/unusable, 1 for cosmetic;
- **segment fit:** importance to the chosen beachhead;
- **confidence:** reproducibility and evidence quality;
- **effort:** relative engineering, testing, documentation, and support cost.

Privacy/safety findings bypass the formula. A credible privacy leak or silent
audio loss is a release blocker even if one user found it.

## Decision rules

- Fix lifecycle, data loss, privacy, and exactly-once failures before accuracy
  tuning or new features.
- Require three independent observations or a clear strategic job before an
  enhancement enters discovery.
- Require paired before/after evidence before declaring an iteration better.
- Decline features that require default transcript history, cloud processing,
  idle polling, or product sprawl unless the product contract is deliberately
  changed by the owner.
- A model self-report or vendor benchmark is not comparative proof.

## Cohort cadence

- **After first install:** 5-minute activation check.
- **After first 25 dictations:** correction-cost and value interview.
- **Weekly for four weeks:** aggregate success/failure check-in.
- **After a relevant fix:** same supplied task, same device, before/after.
- **At week four:** retention/churn interview and real offer choice.
- **Monthly:** optional 45-minute user council with 5–8 varied retained users.

Avoid daily surveys and gamification that pressure accessibility participants.

## Repository workflow

Suggested labels:

- `safety/privacy`, `capture`, `hotkey`, `recognition`, `insertion`, `lifecycle`,
  `activation`, `performance`, `accessibility`, `research-needed`;
- severity `S0` privacy/data-loss, `S1` blocks core task, `S2` material
  friction, `S3` minor;
- evidence `reproduced`, `needs-repro`, `supplied-script`, `cohort-signal`.

Issue title template:

> `[S1][CAP-FIRST][4.2.5] Opening token missing at 0 ms start on M1 / USB mic`

The issue body should link to an anonymized test row, never a private transcript.

## Learning repository

Maintain five living pages:

1. jobs and segments;
2. problem-code frequency and exposure;
3. decisions and rejected alternatives;
4. claim/evidence register;
5. experiment results.

This folder provides the initial forms. Replace hypotheses with observed facts
rather than appending an ever-growing wishlist.
