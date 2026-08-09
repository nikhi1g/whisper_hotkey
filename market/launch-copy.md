# Launch and recruitment copy

Use only the **safe now** copy until the corresponding scorecard gate passes.
Replace `[VERSION]`, `[RESULT]`, and `[LINK]` with current facts. Do not copy a
proof-gated line into production merely because it sounds better.

## Landing page

### Recommended hero — safe now

**Your voice stays on your Mac.**

Private, local English dictation for Apple Silicon. Press your key, speak, and
put faithful text into the field you chose—without an account, subscription,
transcript library, or cloud transcription step.

Primary action: **Join the measured beta**

Secondary action: **Inspect the source and privacy path**

Support line:

> Four local recognition choices. Hold, toggle, or pause. Audio is temporary,
> recognition runs on-device, and explicit update checks are the only normal
> network exception.

### Proof-led hero — use only after cohort gate

**Start speaking with the key—not after it.**

Across `[N]` immediate-speech trials on `[devices]`, `whisper_hotkey [VERSION]`
captured the opening word `[RESULT]`. Audio and recognition stayed on the Mac.

Link “See the protocol, failures, and raw de-identified results.”

### Alternative for technical users

**Local dictation with a boundary you can inspect.**

The microphone starts on the physical key edge. Recognition happens on Apple
Silicon. Temporary audio is deleted. No account, cloud rewrite, transcript
history, or hidden dictation telemetry is required.

## Three proof blocks

### Capture first

The hotkey edge queues capture on a dedicated runtime before model preparation,
badge placement, Accessibility lookup, audio conversion, or file writing.
Early microphone buffers are held in order. See the measured startup protocol.

### Local by construction

Audio and recognition remain on this Mac. Dictation uses private temporary
files and does not create a transcript history. An update request occurs only
after a manual check or an opt-in once-per-launch check, and carries no audio,
text, dictionary, or device identifier.

### Faithful, not “improved”

The default path does not send your words through a generative cleanup service.
It inserts the recognized text rather than silently changing tone or meaning.

## Honest limitation block

**Know before you install**

- Apple Silicon Mac running macOS 14 or newer;
- English recognition;
- current public ZIP is signed but not Apple-notarized, so first launch needs
  one Open Anyway approval in Privacy & Security;
- Microphone hears speech, Input Monitoring detects the selected global key,
  and Accessibility inserts text in another app;
- speech recognition can be wrong; do not use it as an authoritative record;
- no formal HIPAA, legal, or enterprise compliance certification.

Putting this beside the download increases trust even if it lowers unqualified
downloads.

## 30-second uncut demo storyboard

Do not use a montage. Keep the clock and network state visible.

1. `0–3 s`: Turn Wi-Fi off or show a blocked-network monitor. Open Activity
   Monitor/network view and a blank TextEdit document.
2. `3–8 s`: Press the configured key and immediately say, “Material
   improvements begin with measured behavior.” Do not wait for the badge.
3. `8–12 s`: Release; show the full first word and final insertion.
4. `12–18 s`: Repeat in a browser text area.
5. `18–24 s`: Use Toggle mode in an Electron app; stop and show the badge return
   to idle.
6. `24–27 s`: Begin a dictation and press Escape; show that no text is inserted.
7. `27–30 s`: End on “Local audio. Faithful text. Measured behavior.” plus the
   benchmark/source link.

Include the Mac model, app version, recognition choice, processing mode, and
whether the model was warm in the caption.

## Beta invitation

### Short

I am recruiting 15 Apple Silicon Mac users to test a private local dictation
app. I am specifically measuring whether it captures the first word when you
start speaking immediately, returns text quickly, and behaves reliably across
apps. The session uses supplied non-sensitive text; I do not need your real
dictations. The current build is open source and non-notarized, so the first
launch involves Open Anyway plus macOS permissions. If you use dictation for
technical writing, high-volume prose, or reducing keyboard use, apply here:
`[LINK]`.

### Security-minded

I need five people who will challenge a local-only dictation claim. The app is
open source, uses local Parakeet/Whisper recognition, retains no transcript
history, and should make no dictation-time network request. I will provide a
reproducible network/temp-file test and would value attempts to falsify it. Do
not use confidential content; the test pack is public. `[LINK]`

## Show HN

**Title:** Show HN: whisper_hotkey – measured, private local dictation for Apple
Silicon Macs

**Body:**

I built `whisper_hotkey` because the moment that kept breaking dictation for me
was not model inference—it was the boundary around it. If recording starts only
after UI, model, Accessibility, or file setup, speaking on the key edge loses
the opening words.

The current Mac app queues microphone capture from the physical key-down edge
onto a dedicated runtime. Conversion, VAD, file writes, and recognition are
separate; audio and recognition remain local; temporary audio is deleted; and
the default path does not use a cloud cleanup model. It supports hold, toggle,
and pause behavior plus four local recognition choices.

The honest limitations: Apple Silicon/macOS 14+, English only, and the current
public build is Apple Development-signed but not notarized, so first launch
needs Open Anyway and three explained permissions.

I am not claiming “instant” or “most accurate.” I am recruiting a measured beta
to publish physical-key-to-first-buffer, opening-word retention, release-to-
insert, cross-app reliability, and network results. The existing 2.46% WER
number is only a 100-utterance LibriSpeech/warm-M5-Pro result, not a universal
claim.

Source: `[REPO]`

Protocol: `[PROOF LINK]`

Beta: `[LINK]`

I would especially value criticism of the protocol and privacy boundary.

## r/macapps-style post

**Title:** I am testing a private local dictation app that starts capture at the
hotkey edge—looking for 15 honest testers

Builder disclosure: this is my project.

There are already many good local dictation apps, so I am not posting another
“Whisper, but offline” claim. The behavior I am trying to prove is narrower:
when you press the hotkey and start talking immediately, does the app keep the
first word, finish quickly, insert once into the right place, and return to
idle every time?

`whisper_hotkey` is an open-source Apple Silicon Mac app. Audio and recognition
stay local, there is no account or transcript history, and it supports hold,
toggle, and pause. I need testers willing to run a supplied 20-sentence pack
and then use it for a week. I do not want private dictations or audio.

Current caveat: the ZIP is signed but not notarized, so first launch needs the
Open Anyway path plus Microphone, Accessibility, and Input Monitoring. I explain
why each permission is used before asking for it.

If interested: `[LINK]`. I will publish the protocol and results, including
failures.

Questions I most want answered:

- Do you lose the opening word with your current tool?
- Do you want literal text or automatic cleanup?
- Which activation method causes the least friction?
- Which permission or install warning stops you?

## Product Hunt

**Tagline:** Private local dictation that starts with the hotkey, not after it.

**Description:** A focused, open-source English dictation utility for Apple
Silicon Macs. Audio and recognition stay local. Hold, toggle, or pause; insert
faithful text into the field you chose. No account, subscription, transcript
library, or cloud cleanup required.

Do not launch on Product Hunt until the unassisted activation and support gates
in the 90-day plan pass.

## Direct outreach email

**Subject:** Could you break a local Mac dictation beta?

Hi `[name]`,

I am testing an open-source Apple Silicon dictation app around one specific
question: if someone starts speaking at the exact hotkey edge, do we preserve
the first word and still insert the result reliably in their normal apps?

I thought of you because `[specific workflow/reason]`. The session is 45
minutes, uses supplied non-sensitive sentences, and does not require sharing
real dictations. I will be transparent about a current rough edge: the build is
signed but not notarized, so the first install uses macOS Open Anyway and three
explained permissions.

Would you be willing to test it? It is completely fine to say no. `[LINK]`

Thanks,

`[name]`

## FAQ / objections

### Why not use Apple Dictation?

Apple Dictation is the right baseline and may be enough. `whisper_hotkey` is
for people who want an explicitly local third-party recognition path, a choice
of local models and input behaviors, an inspectable data boundary, and no
server-dependent workflow. Test both on your vocabulary.

### Is it more accurate than Aqua, Wispr Flow, or Superwhisper?

Not established. The current public WER measurement is on a narrow LibriSpeech
sample. The beta is building a paired application corpus before making a
comparative claim.

### Why three permissions?

Microphone captures speech. Input Monitoring recognizes the configured global
key. Accessibility places the finished text into the chosen application. None
of these permissions proves privacy; the source, network audit, and data-flow
documentation explain what the app actually does with them.

### Why is it not notarized?

The project currently has no paid Apple Developer Program membership. It uses
a stable Apple Development signature, so macOS requires one manual Open Anyway
approval. This is a real adoption limitation, not a feature.

### Does it store history?

No transcript library is created. Audio is temporary and deleted on normal
completion, cancellation, failure, and termination paths. A bounded last-result
fallback may exist in memory until the app quits if that setting is enabled;
check the exact release claim sheet.

### Is “local” automatically compliant for my company?

No. Local processing reduces a data-transfer surface, but compliance also
depends on deployment, access, policy, contracts, support, and your
organization’s assessment.

## Search/education pages to create later

- “Private local dictation for Mac: what ‘local’ should mean”
- “How to test whether a dictation app loses the first word”
- “Apple Dictation vs local Parakeet/Whisper: a reproducible workflow test”
- “Literal dictation vs AI cleanup: which creates fewer corrections?”
- “Why Mac dictation apps need Accessibility and Input Monitoring”
- “Offline alternative to Wispr Flow: privacy and workflow trade-offs”

Comparison pages must cite current primary sources, show limitations, and avoid
impersonating or denigrating competitor trademarks.
