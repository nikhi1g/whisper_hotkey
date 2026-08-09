# User research kit

Everything here is copy-ready. Replace bracketed fields. Do not collect
dictated work content by default.

## Recruitment screener

**Title:** Help test private, local Mac dictation

We are studying how people use voice instead of typing on Apple Silicon Macs.
The test build processes speech locally and is open source. This is research,
not a promise that the app is finished. A session takes about 45 minutes and
uses supplied, non-sensitive sentences.

1. Which Mac do you use? `[model/chip, RAM if known]`
2. Which macOS version do you use?
3. Which of these do you write most days? `[email/messages, code/technical
   docs, long-form writing, notes/prompts, client/professional material, other]`
4. Do you currently use dictation? `[daily, weekly, tried and stopped, never]`
5. Which product or built-in feature do you use or last try?
6. What made you try dictation?
7. What most often makes you stop using it?
8. Is keeping audio and text off external servers important for your work?
   `[required, preferred, not important, unsure]`
9. Would holding a key, toggling with two taps, or using another device be
   easiest for you?
10. Are you willing to install an Apple Development-signed test app that
    currently requires one Open Anyway approval plus macOS Microphone,
    Accessibility, and Input Monitoring permissions? `[yes/no/need explanation]`
11. May we contact you for a 45-minute session? `[email stored separately from
    test results]`

Selection rule: choose for workflow and need diversity, not only people already
enthusiastic about local AI.

## Plain-language consent script

> Today we are testing the product, not you. The app needs Microphone to hear
> supplied test sentences, Input Monitoring to detect the chosen hotkey, and
> Accessibility to insert the result into the chosen field. Normal recognition
> runs locally. We will record task outcomes and timing, not the private things
> you usually dictate. Please do not speak names, credentials, employer data,
> client information, health information, or anything you would not put in a
> public test document. Screen/audio recording of this research call is off by
> default. If we want to record a portion, we will ask separately and state how
> long it will be retained. You can stop, skip a question, or uninstall at any
> time. May we continue?

Keep identity/contact information separate from task rows. Use participant IDs
such as `P001`.

## Discovery interview — 25 minutes

Ask before showing the product.

1. Tell me about the last time typing felt slower, less private, or more
   physically difficult than speaking.
2. What were you trying to produce, in which app, and what happened next?
3. What do you use today? Walk me through the exact trigger-to-final-text flow.
4. Where does it fail: starting, knowing it is listening, recognition,
   formatting, correction, insertion, privacy, or cost?
5. What was the last error serious enough that you stopped dictating?
6. Which words does it consistently get wrong?
7. Do you want literal words, automatic cleanup, or different behavior by task?
8. What information would you never dictate to a cloud product?
9. How do you decide whether a “local” claim is trustworthy?
10. What permissions or install warnings would cause you to stop?
11. How often would this need to work before it became a habit?
12. If your current tool disappeared tomorrow, what would you do?

Do not ask “Would you use a private dictation app?” It invites politeness, not
evidence. Ask about the last real event.

## First-install observation — 15 minutes

Give only this instruction at first:

> Please install the latest test release and dictate the supplied sentence into
> TextEdit. Think aloud. I will stay quiet unless you are blocked for two
> minutes or encounter a destructive/security decision.

Observer codes:

- `DWN` — could not identify correct download;
- `ZIP` — archive/unzip confusion;
- `GTW` — Gatekeeper/Open Anyway block;
- `LCH` — app launched but could not find it;
- `MIC` — Microphone permission;
- `AX` — Accessibility permission/trust;
- `IM` — Input Monitoring permission/trust;
- `RST` — restart/relaunch confusion;
- `KEY` — hotkey/gesture confusion;
- `REC` — recognition failure;
- `INS` — insertion/target failure;
- `SUC` — first successful dictation.

Record time and code only. Ask after success: “At which moment were you least
confident, and what did you think the app was doing?”

## Scripted task test — 20 minutes

Use a new, empty, non-sensitive document.

### Task 1: immediate opening word

“Press the hotkey and begin the supplied sentence immediately, without waiting
for the badge: **Material improvements begin with measured behavior.**”

Repeat at randomized 0, 50, 100, and 200 ms cues. Record whether “Material” is
present, capture/visual/insert timings, and any hesitation.

### Task 2: ordinary shortcut discrimination

Use the selected modifier in two normal shortcuts, then dictate once. Record
any accidental recording, swallowed key, or duplicate result.

### Task 3: target at completion

Start in one safe text field, move focus to another while speaking, and finish.
Ask where the user expected text to land, then record the actual destination.

### Task 4: cancel

Begin the supplied sentence, press Escape, and verify that nothing is inserted,
the badge closes, and the app is ready again.

### Task 5: toggle lifecycle

Start and stop a toggle dictation. Verify one insertion and return to idle. Run
another dictation immediately.

### Task 6: cross-app

Repeat a short supplied sentence in TextEdit, a browser text area, an Electron
app, and the participant’s normal editor. Never use a password or secure field.

### Task 7: jargon and correction

Dictate:

> PostgreSQL streams JSON metadata to a Kubernetes worker named Aster Vale.

Count semantic errors, correction keystrokes, and time until the participant
says the text is usable.

## Post-session survey

Use 1 = strongly disagree and 7 = strongly agree.

1. I knew when recording had started.
2. I could begin speaking immediately.
3. The result arrived fast enough to preserve my flow.
4. The result reflected what I said rather than rewriting my intent.
5. I trusted where my audio and text went.
6. The permissions made sense.
7. Fixing errors took less effort than typing from scratch.
8. I would use this at least three days per week.

Then ask:

- What is the one reason you would not use this tomorrow?
- What current tool would this replace, if any?
- Which one task would you use it for first?
- After 25 successful dictations, which would you choose: continue with the
  free open-source build; pay $29–49 once for a notarized supported build; make
  an optional contribution; or stop using it? Why?

## Weekly beta check-in

> During the last seven days, approximately how many dictations did you
> attempt? How many inserted usable text? Did any lose the opening word, insert
> twice, land in the wrong field, leave the app stuck open, or require a
> restart? Which app and input/processing mode were involved? Please describe
> the behavior without pasting the transcript. What is the single change that
> would most increase your use next week?

## Privacy-safe bug report

- participant ID or GitHub handle (optional);
- app version and release hash;
- Mac chip/RAM and macOS;
- target app/version;
- input behavior, processing mode, recognition choice, microphone;
- exact gesture sequence and expected/actual state;
- whether first word was lost, insertion duplicated, target wrong, UI stuck,
  or restart required;
- reproducibility out of five attempts;
- sanitized logs that contain no audio or transcript;
- permission to follow up.

Explicitly say: **Do not attach private audio, transcripts, screen recordings,
credentials, or client/employer information.** If content is essential, first
reproduce with the supplied public sentence.

## Testimonial permission

> May we quote the following sentence publicly? We will show you the exact
> quote, role description, and location before publishing. Your dictated
> content will never be included. Choose one: full name and role; first name and
> general role; anonymous role; do not publish.

A useful testimonial names a job and result, for example: “I dictate technical
issue descriptions locally and no longer wait before the first word.” Do not
publish vague praise as proof.
