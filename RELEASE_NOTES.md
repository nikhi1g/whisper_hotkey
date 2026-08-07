Version 3.5.0 adds two recognition engines. Both are additions — every existing
engine, model, preset, and decoding profile behaves exactly as it did in 3.4.2,
and no saved selection changes.

## Parakeet Unified

A third Parakeet model, and the only one evaluated that beats the shipping
engine on this project's own benchmark rather than only on a public leaderboard
average. Measured over the same 100 LibriSpeech utterances on an Apple M5 Pro:

| Model | Combined WER | test-clean | test-other | Mean | Median |
| --- | ---: | ---: | ---: | ---: | ---: |
| Parakeet Unified | **2.46%** | **1.44%** | **3.63%** | **50 ms** | **41 ms** |
| Parakeet Accurate | 2.62% | 1.54% | 3.86% | 56 ms | 53 ms |

It wins every accuracy figure and both mean and median latency. Its one
regression is the tail: audio longer than 15 seconds is transcribed with
overlapping windows, so long recordings run about 138 ms against Accurate's
100 ms. Dictation phrases are far shorter, so the median is the number you
feel.

Downloaded on demand at 594 MB. Select it under Advanced Options.

## Cohere Transcribe

The highest-ranked permissively licensed model with an Apple Silicon path —
Apache-2.0, and fourth on the Open ASR Leaderboard. On this corpus that ranking
does not hold up:

| Engine | Combined WER | test-clean | test-other | Mean latency |
| --- | ---: | ---: | ---: | ---: |
| Cohere Transcribe | 2.57% | **1.13%** | 4.21% | 629 ms |
| Parakeet Accurate | 2.62% | 1.54% | **3.86%** | **56 ms** |

The two tie overall. Cohere is meaningfully better on clean speech and worse on
noisy speech, and it costs eleven times the latency because it decodes one
token at a time. It is offered for anyone who dictates in quiet conditions and
prefers accuracy there, and the confirmation dialog states that tradeoff before
the 2.4 GB download rather than after.

## Also

The benchmark harness measures all three engines through the same word-error
math, so a published leaderboard number can be checked against this corpus
before it is believed. Both of the above are cases where it did not survive
that check.

The app is signed with a stable Apple Development identity and is not
notarized, so the first launch still needs one approval through System
Settings > Privacy & Security > Open Anyway. Audio and transcripts remain
local, and every bundled Whisper model is verified against a pinned SHA-256.
