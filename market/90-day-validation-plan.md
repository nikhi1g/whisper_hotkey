# 90-day validation plan

The objective is not a large launch. It is to identify one group that activates,
uses the product repeatedly, and can explain why it is better for them.

## Success at day 90

- 30 screened prospects;
- 15 completed discovery interviews;
- 20 install attempts;
- 12 people complete a first successful dictation;
- 8 use it in at least three real work sessions during week two;
- 5 are still active in week four;
- 600 scripted first-word trials completed with a published result;
- at least three public, permissioned testimonials tied to a concrete workflow;
- one audience/message pair beats the others on activation and retention;
- no dictated work content collected by default.

These are learning thresholds, not evidence of product-market fit.

## Phase 1 — truth and recruitment (days 1–14)

### Week 1

- Freeze a public claim sheet for the exact release being tested.
- Record an uncut install and permission walkthrough on a clean Mac account.
- Run the first-word protocol internally on three hardware tiers.
- Create a simple interest form using the screener in
  [user-research-kit.md](user-research-kit.md).
- Recruit individually; do not post a broad launch yet.

Targets: 30 screener responses, 10 interview bookings, 5 internal install
observations, and no unresolved data-handling ambiguity.

### Week 2

- Complete the first 10 interviews before pitching features.
- Observe five assisted installations over screen share.
- Code each failure as download, Gatekeeper, launch, permission, hotkey,
  recognition, insertion, or understanding.
- Give participants supplied safe text for their first test.

Gate: at least 60% of assisted attempts reach a successful dictation. If not,
stop recruitment and repair the dominant activation failure before expanding.

## Phase 2 — measured pilot (days 15–35)

### Week 3

- Enroll 12 activated testers: five technical, four writing/operations, three
  keyboard-reduction/accessibility co-design participants.
- Run the 20-utterance scripted pack with each participant.
- Ask testers to use the app naturally for one week without sharing content.
- Collect a 30-second local summary after each work session: attempted count,
  successful count, first-word loss count, app, mode, and top problem code.

### Week 4

- Complete the 600-trial dataset by adding devices or participants as needed.
- Run the end-of-week interview and correction-cost exercise.
- Publish the result even if the target fails; explain the next change.
- Ask what the participant would use tomorrow if this app disappeared.

### Week 5

- Choose the single highest-frequency failure and the single highest-value
  missing capability. Do not choose by vote count alone; weight frequency,
  severity, segment fit, and evidence quality.
- Prepare two message variants based on observed jobs, not demographic labels.

Gate: at least 8 of 12 testers have three or more successful work sessions in
week two. Otherwise revisit the job/segment before expanding features.

## Phase 3 — iteration and unassisted activation (days 36–63)

### Weeks 6–7

- Ship one narrow improvement to the pilot cohort.
- Compare before/after on the same task and device.
- Send a changelog that names the feedback signal and the measured effect.
- Run 10 unassisted installs from the public instructions.

Gate: >=40% of unassisted installs reach first dictation under the current
non-notarized path. If Gatekeeper dominates, keep outreach technical and make a
business decision on the $99/year Apple Developer Program rather than polishing
copy around the warning.

### Weeks 8–9

- Test the winning landing message with 100–200 relevant visitors, not generic
  paid traffic.
- Ask retained users for a one-sentence workflow-specific testimonial and
  permission to publish their role; never ask them to reveal dictated content.
- Offer a live 20-minute onboarding slot to the next cohort.

## Phase 4 — focused launch (days 64–90)

### Weeks 10–11

- Publish the benchmark protocol, privacy/data-flow page, compatibility matrix,
  and known limitations.
- Record the 30-second demo in [launch-copy.md](launch-copy.md).
- Prepare support capacity for installation and permission questions.

### Week 12

- Launch first to one community where the team has participated and learned.
- Reply to every substantive question with evidence or a clear “not measured.”
- Do not cross-post identical promotional copy to multiple communities on the
  same day.

### Week 13

- Review download-to-activation, week-one usage, failure reasons, and support
  burden.
- Choose: deepen the winning segment, change the offer, or stop broad outreach
  and return to validation.

## Channel sequence

| Order | Channel | Why | Asset |
| ---: | --- | --- | --- |
| 1 | Direct GitHub/technical-network invitations | Best fit for present install friction and detailed reports | Short outreach note + assisted install |
| 2 | Show HN | Technical audience values open source, benchmarks, and local privacy | Proof-led Show HN copy |
| 3 | r/macapps or similar Mac community | Strong category interest and frank product comparisons | Builder-disclosed beta post and video |
| 4 | Accessibility/RSI communities | High need, but requires respectful co-design and no health claims | Research invitation, free access, alternate activation questions |
| 5 | Security/privacy communities | Strong fit after the network audit and threat model are public | Reproducible audit rather than generic launch copy |
| 6 | Product Hunt | Useful only after onboarding and support can absorb nontechnical users | Polished demo, proof page, testimonials |

## Budget

| Item | Lean | Recommended |
| --- | ---: | ---: |
| 15 interview thank-yous | $0 with warm network | $375 at $25 each |
| 10 extended-pilot thank-yous | $0 | $200 at $20 each |
| Apple Developer Program, if owner chooses broad distribution | $0 while technical-only | $99/year |
| Microphone/device diversity | Borrow/tester-owned | $100 contingency |
| Paid acquisition | $0 | $0 until activation and retention gates pass |
| Total | $0 | $774 |

The $99 membership is not a marketing expense to hide; it is an explicit
conversion experiment. The project’s current release policy remains
non-notarized unless and until the owner purchases the appropriate membership.

## Weekly dashboard

Track only aggregate or de-identified fields:

- landing visitors;
- release-page clicks;
- download starts (if available from GitHub release counts);
- launch attempts;
- Gatekeeper completion;
- three permission completions;
- first successful dictation;
- week-one and week-four retained testers;
- successful/attempted dictations from opt-in summaries;
- first-word-loss events;
- correction count per supplied 100 words;
- top failure code;
- support minutes per activated user.

Do not add background product telemetry merely to make the dashboard easy.
Manual, opt-in reporting is sufficient at this cohort size.

## Stop conditions

- Pause if any private audio/transcript survives a cancellation or failure.
- Pause if a release introduces outbound traffic not disclosed in the claim
  sheet.
- Pause broad outreach if fewer than 4 of 10 unassisted users activate.
- Do not enter regulated-team sales if security review, deployment, support,
  or compliance questions cannot be answered precisely.
- Do not build a requested feature when the underlying job is seen fewer than
  three times and conflicts with the focused product contract.
