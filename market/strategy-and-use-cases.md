# Strategy and use cases

## Market thesis

Local inference is now table stakes, not differentiation. The market has split
into three broad offers:

1. cloud products that sell polished, contextual, real-time writing;
2. feature-rich local/hybrid products that sell model choice and workflows;
3. free open-source hotkey tools that sell privacy and control.

`whisper_hotkey` should occupy a fourth, deliberately narrow position:
**measured, faithful, low-friction local dictation**. It should win on the
boundary moments that determine whether dictation becomes habitual:

- the first syllable is captured;
- the user knows when recording is active;
- release produces text quickly;
- text lands in the intended field exactly once;
- cancellation leaves no text or audio behind;
- the app returns to idle and stays out of the way;
- the user can verify that no dictation crossed the network.

## Initial customer profiles

| Priority | Segment | Repeated job | Why it fits | Main objection | Recruit first through |
| ---: | --- | --- | --- | --- | --- |
| 1 | Developers, security engineers, and technical founders on Apple Silicon | Prompts, issue reports, reviews, docs, Slack, and email involving private code or plans | Comfortable with GitHub and an early non-notarized build; values local proof | Jargon accuracy and install permissions | GitHub, Show HN, local-first and Mac developer communities |
| 2 | High-volume solo writers and operators | Draft emails, briefs, posts, notes, and long prompts without breaking thought flow | High frequency makes latency and correction cost visible quickly | Wants polished prose or live text | Writing, productivity, and indie-founder communities |
| 3 | People reducing keyboard use because of strain or access needs | Replace high-volume prose typing while retaining keyboard/mouse for precise edits | Toggle and Pause modes may reduce sustained key holding | Activation method, correction burden, accessibility trust | Co-design through accessibility groups and individual referrals; never make medical claims |
| 4 | Privacy-sensitive legal, clinical, financial, and research professionals | Draft confidential material without adding a speech vendor | Strong local-only architecture | Security review, support, notarization, compliance, and liability | Discovery interviews only until packaging and security documentation mature |

### Beachhead recommendation

Start with privacy-conscious developers and technical founders. They can
survive the present install path, provide actionable bug reports, exercise
Terminal/Electron/browser insertion paths, and understand why a public network
audit matters. Expand only after unassisted activation is reliable.

## Concrete applications

The app is suitable today for English prose in a text field:

- speaking detailed prompts into Codex, Claude Code, Cursor, or web chat;
- drafting GitHub issues, pull-request explanations, test plans, and code
  comments (not symbol-heavy code generation);
- replying to email, Slack, Messages, forums, and customer support tools;
- capturing a private journal entry or thinking note directly in a chosen app;
- drafting outlines, articles, briefs, and meeting follow-ups;
- entering private research notes while offline or behind a restrictive
  network;
- reducing prose keystrokes in a hybrid voice-and-keyboard workflow.

Use caution around these applications:

- **Medical, legal, or regulated content:** local processing is useful, but the
  app has no formal compliance certification or enterprise administration.
- **Interview or meeting transcription:** this is a dictation utility, not a
  consent, diarization, or multi-speaker recording system.
- **Non-English dictation:** the current recognition path is English-only.
- **Verbatim records:** ASR can be wrong. “Faithful” means there is no
  intentional generative rewrite layer, not that recognition is infallible.
- **Accessibility:** involve users in design and testing; do not promise a
  treatment or health outcome.

## Positioning

### Category

Private local dictation for Apple Silicon Macs.

### One-sentence positioning

For Mac users who do not want their spoken thoughts sent to a server,
`whisper_hotkey` is a focused local dictation utility that begins capture at
the hotkey edge and places faithful text into the field they chose—without an
account, subscription, transcript library, or cloud cleanup step.

### Message hierarchy

1. **Nothing to upload:** audio and recognition stay local.
2. **The beginning matters:** capture is architected to start before model,
   UI, file conversion, or Accessibility work.
3. **Your words remain your words:** no default generative rewrite layer.
4. **Works where the cursor is:** hold, toggle, and pause behaviors for normal
   Mac text fields.
5. **Inspectable, measured, and open:** published source, reproducible model
   benchmark, privacy boundary, and forthcoming real-workflow scorecard.

### What not to lead with

- Whisper, Parakeet, beam widths, model sizes, or “four models.” Those are
  implementation choices; users buy a reliable outcome.
- “AI-powered.” Every competitor says it and the intended customer may see it
  as a privacy warning.
- 2.46% WER without the full benchmark qualifier.
- “100% accurate,” “zero latency,” “never fails,” or “HIPAA compliant.”

## What would make the product significantly better

This is a research roadmap, not an instruction to code everything.

### P0: proof and adoption blockers

1. **Measure the complete experience.** Publish hotkey-to-first-buffer,
   hotkey-to-visible-listening, release-to-insert, first-token retention,
   insertion success, stuck-UI rate, idle resource use, and outbound network
   results. Decode-only latency is insufficient.
2. **Resolve consumer installation.** The current ZIP requires Open Anyway,
   followed by Microphone, Accessibility, and Input Monitoring. A paid Apple
   Developer Program membership and Developer ID notarization would remove the
   first and most frightening hurdle. Until the owner chooses that cost, target
   technically sophisticated testers and measure every funnel step.
3. **Unify the public truth.** The README, purpose contract, release metadata,
   and website currently contain model/default/install wording that has changed
   over time. Build one release-specific claim sheet before every campaign.
4. **Prove compatibility.** Publish a tested matrix for TextEdit, Notes,
   Safari, Chrome, Slack, VS Code/Cursor, Terminal, Microsoft Word, and Google
   Docs, including cancellation and clipboard restoration.

### P1: correction cost and habit formation

1. **Make technical vocabulary effective on the default model.** The current
   internal dictionary biases Whisper Turbo, while the default Parakeet family
   cannot accept a prompt. Users care about names and jargon, not why the model
   cannot receive them. Test deterministic local replacements, user-confirmed
   corrections, or a vocabulary-aware local path without silently rewriting
   meaning.
2. **Make corrections cheap.** The lasting user metric is not raw WER but
   keystrokes needed to reach usable text. Test a local “copy last,” undo,
   retry, or correction workflow that never stores a history by default.
3. **Support alternate activation hardware.** Foot pedals, mouse buttons, or a
   local CLI trigger may matter more than another model for users avoiding
   keyboard strain. Validate demand before implementation.
4. **Give the user a safe readiness cue.** The recording should already be
   active; sound or visual feedback should confirm state rather than tell the
   user to wait.

### P2: expansion only after retention

1. Multilingual local recognition.
2. Local streaming preview for users who need reassurance while speaking.
3. Optional, clearly separated local cleanup modes with a visible “literal”
   default and a way to compare before/after.
4. Team deployment, managed settings, and security review material.

Do not rush into meeting bots, transcript libraries, cloud sync, general AI
agents, or automatic screen reading. Those are crowded categories and conflict
with the product’s minimal, ephemeral trust story.

## Offer and pricing experiments

The current open-source/free offer is attractive but not unique. Test value
without withdrawing the free build:

| Experiment | Offer | What it learns |
| --- | --- | --- |
| Free/open-source | Current signed release and source | Whether outcome alone creates adoption and contributions |
| Sponsor | Optional $5–10/month or one-time support | Whether users value continuity without gating privacy |
| Convenience license | $29–49 one-time for a notarized, auto-updating build plus support; source remains available | Whether nontechnical users pay to remove setup and maintenance risk |
| Team pilot | Paid onboarding/support for 5–20 seats; no claim of compliance | Whether privacy-sensitive teams value deployment help |

Never ask willingness-to-pay as a hypothetical alone. Present a real choice
after a user has completed at least 25 successful dictations.

## Defensible moat

The models are not a moat; competitors can download the same ones. A credible
moat would be the accumulated system and evidence around them:

- a public, reproducible first-word and cross-app reliability benchmark;
- a privacy threat model and release-verification story users can audit;
- a corpus of consented, non-sensitive application dictation covering real
  prompts, jargon, accents, noise, and immediate speech;
- a disciplined cohort of users whose correction cost and failure reports feed
  weekly product decisions;
- a reputation for literal, predictable behavior rather than feature volume.
