# Future implementation notes

Forward-looking notes, newest first. Nothing below is built.

## 2026-08-07 — Voice adaptation for noisy environments

### The problem it solves

The recognizers the app ships — Parakeet transducers and Whisper, both run
locally through Core ML and Metal (`docs/MODELS.md`) — are trained on generic
speech and have no notion of who the user is. In a quiet room that is fine. In
a room with a TV on, a second conversation nearby, or background music,
generic acoustic models start transcribing the loudest or clearest voice in
the mix, not necessarily the user's. The existing energy gate (`-48 dBFS`,
100 ms of contiguous speech-like energy, described in `purpose.md`) decides
*whether* to run the model; it says nothing about *whose* voice to run it on.
Adapting recognition to one specific speaker is a different problem and needs
different building blocks.

### What would have to be stored

There is no way to bias a model toward one speaker without keeping something
that represents that speaker's voice. The realistic options, in increasing
order of what they require:

- A **speaker embedding**: a fixed-size vector summarizing the user's vocal
  characteristics, produced by a diarization/speaker-ID model from a short
  enrollment recording. Tens of kilobytes, not audio, not directly
  reconstructable into speech, but still biometric data.
- A **short reference clip**: raw enrollment audio kept on-device so the
  embedding can be regenerated if the isolation model changes. This is
  audio, and it is exactly what the current contract forbids retaining.
- **Adapted model weights**: a small LoRA-style delta or per-user acoustic
  adjustment, if fine-tuning per user turns out to be the mechanism rather
  than embedding-based isolation. Larger than an embedding, still not raw
  audio, but still user-specific and persistent by definition.

Any of these is new persistent, personally identifying state. None of it can
be "ephemeral" in the sense the app currently promises.

### Roughly how this could work

Two different mechanisms are plausible and are not mutually exclusive:

1. **Speaker isolation before recognition.** FluidAudio, already a dependency
   for Parakeet (`docs/MODELS.md`), ships speaker diarization and
   voice-activity detection. A diarization pass could label segments by
   speaker, and only the segment matching the user's stored embedding would
   be handed to the transducer or Whisper. This reuses a library already in
   the app rather than adding a new one, which matches the project's stated
   preference for minimal dependencies (`AGENTS.md`).
2. **Model adaptation.** Instead of filtering audio, the recognizer itself
   could be nudged toward the user's voice — via a stored embedding used as
   conditioning input, or via lightweight per-user fine-tuning. This is a
   heavier lift than isolation and would need its own evaluation; nothing
   here should be read as a claim that it is easy or that a given technique
   will meet accuracy targets. Where the tradeoffs land is genuinely unknown
   until someone prototypes it.

Isolation and adaptation could combine: isolate the speaker first, then run
the existing recognizer unchanged, deferring any weight-level adaptation
until isolation alone proves insufficient.

### The conflict this creates, stated plainly

This feature directly contradicts two things the app currently promises.
`AGENTS.md` states "Audio and transcripts are ephemeral. Logs must not
contain either." `purpose.md` states the app "stores no history, performs no
network requests by default, never downloads models, and removes audio state
after use." Storing a voice embedding, a reference clip, or adapted weights
to recognize a specific person later is retention by definition — it cannot
be built as a quiet extension of the current behavior. Anyone building this
must treat it as amending the product contract, not working around it.

### What would have to be true before this ships

- **Explicit opt-in, off by default.** The app must not begin recording an
  enrollment sample or retaining any derived data without a separate,
  affirmative action distinct from normal dictation use — not a checkbox
  buried in Settings that defaults on.
- **On-device only, no exceptions.** Enrollment audio, embeddings, and any
  adapted weights must never leave the device. This isn't a relaxation of the
  "no network request by default" line, it's a hard requirement that sits
  alongside it.
- **Visibility and deletion.** The user must be able to see that this data
  exists, see roughly what it is (e.g., "one voice profile, enrolled on
  <date>"), and delete it with one action that leaves no residue — matching
  the spirit of the existing "Keep latest transcript until quit" toggle,
  which already gives the user this kind of explicit control over retained
  state.
- **Contract amendment first, not after.** `purpose.md` and `AGENTS.md` would
  need to state plainly that this feature exists, what it stores, and how to
  turn it off, before any code implementing it lands — not as a changelog
  footnote after the fact.
- **A real accuracy case.** Before committing to either mechanism, there
  needs to be a working prototype showing isolation or adaptation actually
  improves recognition in the noisy cases described above, using the
  repository's existing LibriSpeech-based benchmark harness (`docs/MODELS.md`)
  or an equivalent noisy-condition benchmark. No number is asserted here
  because none has been measured.

Nothing described in this entry is implemented. No enrollment flow, storage
format, embedding model, or Settings surface exists yet.
