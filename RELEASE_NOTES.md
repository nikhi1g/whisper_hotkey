Version 3.3.6 fixes the interface bugs that shipped alongside Parakeet in
3.3.0. Every one of them is the same defect in a different place: a surface
reporting something other than what the app was actually doing.

## Highlights

- **Settings no longer wedges when you switch engines.** Going from Parakeet
  back to a whisper engine applied the model selection before the Model row was
  rebuilt, so a two-segment control was asked for its third segment. AppKit
  raised an exception from inside the click handler, the refresh was abandoned
  half-done, and every later click hit the same wall. Nothing crashed, which is
  exactly why it looked like a freeze.
- **Parakeet checkpoints install before they are selected.** Choosing Parakeet
  used to succeed instantly and defer the real cost to your first dictation,
  which then downloaded several hundred megabytes behind a Transcribing badge
  with no progress, no cancel, and no timeout. It is now an explicit step with
  a size confirmation, a progress panel, and a Cancel that leaves your previous
  engine in place.
- **Cancelling an install is no longer reported as a failure**, and a Parakeet
  problem is no longer described as a whisper helper failure.

## Surfaces that now describe what is running

- The **User Guide** named the whisper model and offered Precision and Smart
  Decode even on Parakeet, which is a transducer with no beam search.
- The **internal dictionary** stayed fully interactive on Parakeet, saving
  entries that never reached the recognizer because a transducer accepts no
  prompt. The row now says so. Entries are kept, not cleared, because they
  still apply on every whisper engine.
- The **Setup window** reported a ready whisper model and a ready whisper
  helper for an engine that uses neither.
- The **engine picker** could strand you: engine availability was computed
  against the selected whisper model, so one uninstalled model greyed out every
  whisper engine at once, with no way back from Parakeet.

## Also

- An app already running from ~/Applications is no longer offered a reinstall
  it does not need.

Nothing about recognition itself changed. The measured numbers from 3.3.0 still
stand: Parakeet Accurate at 2.62% word error rate and 56 ms per utterance
against Large-v3 Turbo Q5's 4.32% at 321 ms, on the benchmark in
`Benchmarks/Parakeet/`.

The app is signed with a stable Apple Development identity and is not
notarized, so the first launch still needs one approval through System
Settings > Privacy & Security > Open Anyway. Audio and transcripts remain
local, and every bundled and downloaded whisper model is verified against a
pinned SHA-256.
