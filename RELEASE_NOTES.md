Version 3.4.1 turns recognition into one decision. Settings offers Fast and
Accurate; everything else folds away.

## Two presets

| Preset | Runs | Word error rate | Latency |
| --- | --- | ---: | ---: |
| Fast | Parakeet 110M | 3.88% | 34 ms |
| Accurate | Parakeet 0.6B | 2.62% | 56 ms |

Both run NVIDIA Parakeet on the Neural Engine, and **both checkpoints now ship
inside the app**, so the best configuration on accuracy and latency at once is
there on a fresh install with no download.

There are two presets rather than three because a third had nowhere to sit.
Parakeet 0.6B is simultaneously the most accurate option and answers in well
under a tenth of a second, so a "balanced" tier would have resolved to the same
configuration as "most accurate". A picker whose options are not distinct is a
picker that lies about having a choice.

## Advanced is still there

Engine, model, decoding profile, and processing mode live behind an Advanced
disclosure. A configuration matching neither preset reports **Custom**,
highlights no segment, and keeps those controls open, because they are the only
explanation for the state.

## The model lineup is smaller

Small and Medium English are retired.

- **Small** had no remaining niche: Parakeet Fast beats it on size, speed, and
  accuracy at once — 217 MB and 3.88% against Small's 466 MB and 8.59% — and
  Turbo beats it on accuracy for only 82 MB more.
- **Medium** was the largest and slowest model in the app and was not more
  accurate than Turbo.

A saved selection of either migrates to Turbo. Base English and Large-v3 Turbo
Q5 stay: Parakeet is a transducer and accepts no prompt, so the internal
dictionary only biases Whisper, and Base is the only genuinely lightweight tier.

Every model now ships inside the app. Nothing is fetched at runtime.

The app is signed with a stable Apple Development identity and is not
notarized, so the first launch still needs one approval through System
Settings > Privacy & Security > Open Anyway. Audio and transcripts remain
local, and every bundled Whisper model is verified against a pinned SHA-256.
