# Local models

As of 3.7.0, [whisper.cpp](https://github.com/ggml-org/whisper.cpp) with
Metal and flash attention plus NVIDIA Parakeet on the Neural Engine are
available.
Recognition is English-only and entirely local.

| Menu choice | File | Size | Tradeoff |
| --- | --- | ---: | --- |
| Parakeet Unified | `parakeet-unified-en-0.6b` | 594 MB | Default; bundled |
| Parakeet Balanced | `parakeet-tdt-0.6b-v2` | 443 MB | Lowest tail risk at long dictation lengths |
| Parakeet Fast | `parakeet-tdt-ctc-110m` | 219 MB | Lowest latency and memory |
| Large-v3 Turbo Q5 | `ggml-large-v3-turbo-q5_0.bin` | 547 MB | Whisper; supports the internal dictionary |

Cohere Transcribe was removed in 3.5.9. It won exactly one measurement on
this corpus -- clean read speech, 1.13% against Parakeet Unified's 1.44% --
while losing on noisy speech, costing roughly twelve times the latency and a
2.4 GB download. A saved selection resolves to Parakeet Unified.

Whisper Base English is no longer surfaced in Settings, but remains a bootstrap
option for explicit `run.sh --model base` installs. Parakeet Fast is smaller,
faster and more accurate, and it is bundled in the current app packages.

Small and Medium English were retired in 3.4.1. Parakeet Fast beats Small on
size, speed, and accuracy at once, and Medium was the largest and slowest model
in the app without being more accurate than Turbo. A saved selection of either
migrates to Turbo.

Memory varies with whisper.cpp, Metal allocation, and recording length, so the
menu shows download size rather than promising a fixed RAM number.

## Phase 1 enhancement status

The app contains a bounded selective-repair pipeline, but the shipping policy
is currently **primary-only**. Repair is disabled unless a provider/model/profile
specific calibration artifact matches the runtime and the frozen benchmark,
safety, latency, memory, and thermal gates all pass. No verifier is downloaded,
loaded, or kept resident by this Phase 1 change.

The offline experiment matrix considers Parakeet Unified, full Whisper
large-v3, Parakeet 1.1B variants, and optional Qwen3-ASR as possible local
verifiers. Those artifacts/runtimes are not installed or pinned for production,
their additional disk and peak-memory costs are unmeasured on this checkout,
and the required consented application/public-recovery corpora are absent.
Consequently no candidate is promoted and no sub-1% WER claim is made. The
default `repairPolicy: .disabled` is the tested rollback: the selected primary
engine remains authoritative while deterministic lexical-invariant formatting
may still restore presentation without changing words.

## Processing

Settings provides three processing chips directly below the model picker:

- **Decode After Speaking** prepares the selected model while you speak,
  decodes only after you stop, and retains no model at idle.
- **Model Ready** keeps one selected model loaded between dictations.
- **Decode While Speaking** keeps that model loaded and decodes private bounded
  chunks concurrently with capture, then inserts the assembled transcript once.

Decode While Speaking uses one helper, not parallel model copies. Audio capture
and recognition form a pipeline while whisper.cpp performs its existing
CPU-thread and Metal parallel work. The microphone remains off at idle and no
choice adds idle polling.
The windowed mode can lose a small amount of context across chunk boundaries.
The full-context modes remain available when accuracy matters more than finish
latency.

## Decoder

- Beam search width 5
- English forced
- Metal and flash attention enabled
- Half the logical CPUs, minimum 4 and maximum 8 threads
- No cloud refinement or live partial transcript

Beam search retains several plausible word sequences instead of committing to
one immediately. Width five improves ambiguous phrases and punctuation at a
modest latency cost.

## Recognition engines

Settings presents one grouped list of named configurations rather than separate
engine and model rows, so an invalid pairing cannot be selected. The engines
behind that list are:

- **Metal** is the whisper.cpp GPU path.
- **Parakeet** runs NVIDIA Parakeet on the Neural Engine through
  [FluidAudio](https://github.com/FluidInference/FluidAudio), replacing whisper
  entirely rather than re-hosting it.

The whisper.cpp Core ML encoder and WhisperKit engines were retired in 3.5.7.
Neither could run in a shipped build: the Core ML encoder path was gated on a
`CoreMLEnabled` marker the release bundle never contained, and WhisperKit
needed a compiled model directory nothing shipped or downloaded. A saved
preference naming either now resolves to Metal, which runs the same weights.

### Parakeet

Parakeet is a FastConformer transducer and a different model family from
whisper, so it carries its own checkpoints and own saved selection. Choosing
Parakeet in the Engine row replaces the four whisper chips with three of its own:

| Chip | Checkpoint | Disk |
| --- | --- | ---: |
| Fast | `parakeet-tdt-ctc-110m` | 219 MB |
| Balanced | `parakeet-tdt-0.6b-v2` | 443 MB |
| Unified | `parakeet-unified-en-0.6b` | 594 MB |

Switching engines never overwrites the other engine's model choice. Selecting
Parakeet or one of its checkpoints for the first time shows progress and can be
cancelled; nothing is fetched during a dictation. Checkpoints live in
`~/Library/Application Support/FluidAudio/Models/`, so `run.sh` installs nothing
for this engine.

Measured on the repository's own LibriSpeech benchmark (100 utterances across
test-clean and test-other, Apple M5 Pro, warm model):

| Engine | Combined WER | test-clean | test-other | Mean | p50 | p95 | Disk |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Turbo Q5 + Metal (Precision) | 4.32% | 2.26% | 6.67% | 336 ms | 320 ms | 426 ms | 547 MB |
| Turbo Q5 + Metal (Smart Decode) | 4.04% | 2.15% | 6.20% | 316 ms | 303 ms | 365 ms | 547 MB |
| Parakeet Fast | 3.88% | 2.36% | 5.61% | 36 ms | 33 ms | **55 ms** | 219 MB |
| Parakeet Balanced | 2.62% | 1.54% | 3.86% | 60 ms | 56 ms | 88 ms | 443 MB |
| **Parakeet Unified** (default) | **2.46%** | **1.44%** | **3.63%** | **54 ms** | **45 ms** | 117 ms | 594 MB |

Unified is the shipping default and wins every accuracy measure and both mean
and median latency. Its one regression is the tail: it transcribes audio longer
than 15 s with overlapping windows, so its p95 is the worst of the three
Parakeet variants. A dictation phrase is far shorter than that, which is why
the median is the number that governs how the app feels.

Latencies were re-measured on the 4.2.3 build and run 8-10% above the figures
published with 3.5.0 across every engine, including the ones whose decode is
byte-identical. That is machine load, not a regression; the ordering and the
WER figures reproduce exactly.

Two behaviors differ from the whisper engines and are intentional:

- **The Decoding row disappears.** A transducer has no beam search, so the row
  is hidden rather than greyed out. The stored profile survives, so returning
  to Metal restores it.
- **Prompts are dropped.** Parakeet accepts no text prompt, so the internal
  dictionary and the Pause Mode context tail cannot bias a Parakeet decode.
  Both still apply on every whisper engine.

## Install models

```sh
./run.sh                                      # install/select Base + Metal
./run.sh --model small                        # install/select Small + Metal
./run.sh --model medium                       # install/select Medium + Metal
./run.sh --model turbo                        # install/select Turbo + Metal
./run.sh --all-models                         # install Base + Turbo; select Base + Metal
./run.sh --engine parakeet                    # select Parakeet (no download)
```

Files live in `~/.cache/whisper/`. Missing choices remain visible but
disabled. An explicit model or engine option is persisted before the installed app
launches. Rerun the bootstrap whenever you want to add another model.

## Decoding

**Precision** is the default. It always uses five-beam whisper.cpp decoding.

**Smart Decode** uses a one-candidate greedy pass and accepts it only when its
token confidence, no-speech probability, and repetition checks are strong. It
automatically retries uncertain audio with the same five-beam Precision
decoder. The setting is available for the whisper.cpp Metal engine. Parakeet
continues to use its native decoding behavior.

The app stores only the selected profile. Confidence values are used in memory
for the current inference and are not logged or retained.

## SHA-256

```text
a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002  ggml-base.en.bin
c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d  ggml-small.en.bin
cc37e93478338ec7700281a7ac30a10128929eb8f427dda2e865faa8f6da4356  ggml-medium.en.bin
394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2  ggml-large-v3-turbo-q5_0.bin
```

`run.sh` downloads from `ggerganov/whisper.cpp` on Hugging Face and refuses
mismatched content.
