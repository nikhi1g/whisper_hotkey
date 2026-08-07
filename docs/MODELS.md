# Local models

Version 3.5.7 offers [whisper.cpp](https://github.com/ggml-org/whisper.cpp) with
Metal and flash attention, NVIDIA Parakeet on the Neural Engine, and Cohere
Transcribe. Recognition is English-only and entirely local.

| Menu choice | File | Size | Tradeoff |
| --- | --- | ---: | --- |
| Parakeet Accurate | `parakeet-tdt-0.6b-v2` | 443 MB | Default; bundled |
| Parakeet Unified | `parakeet-unified-en-0.6b` | 594 MB | Most accurate and fastest; on-demand download |
| Parakeet Fast | `parakeet-tdt-ctc-110m` | 217 MB | Lowest latency and memory |
| Large-v3 Turbo Q5 | `ggml-large-v3-turbo-q5_0.bin` | 547 MB | Whisper; supports the internal dictionary |
| Cohere Transcribe | `cohere-transcribe-03-2026` | 2.4 GB | Best on clean speech; ~11x slower; on-demand download |

Whisper Base English left the picker in 3.5.7: Parakeet Fast is smaller,
faster and more accurate, and it is bundled. The file still ships as the
discovery fallback when Turbo is unavailable.

Small and Medium English were retired in 3.4.1. Parakeet Fast beats Small on
size, speed, and accuracy at once, and Medium was the largest and slowest model
in the app without being more accurate than Turbo. A saved selection of either
migrates to Turbo.

Memory varies with whisper.cpp, Metal allocation, and recording length, so the
menu shows download size rather than promising a fixed RAM number.

## Processing

Settings provides three processing chips directly below the model picker:

- **After Recording** loads and decodes after capture for minimal idle memory.
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
whisper, so it carries its own two English checkpoints and its own saved
selection. Choosing Parakeet in the Engine row replaces the four whisper chips
with two of its own:

| Chip | Checkpoint | Disk |
| --- | --- | ---: |
| Fast | `parakeet-tdt-ctc-110m` | 219 MB |
| Accurate | `parakeet-tdt-0.6b-v2` | 443 MB |

Switching engines never overwrites the other engine's model choice. Selecting
Parakeet or one of its checkpoints for the first time offers the download,
shows progress, and can be cancelled; nothing is fetched during a dictation.
Checkpoints live in `~/Library/Application Support/FluidAudio/Models/`, so
`run.sh` installs nothing for this engine.

Measured on the repository's own LibriSpeech benchmark (100 utterances across
test-clean and test-other, Apple M5 Pro, warm model):

| Engine | Combined WER | test-clean | test-other | Mean latency | Speed | Disk |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Turbo Q5 + Metal (Precision) | 4.32% | 2.26% | 6.67% | 321 ms | 21.5x | 547 MB |
| Turbo Q5 + Metal (Smart Decode) | 4.04% | 2.15% | 6.20% | 305 ms | 22.7x | 547 MB |
| Parakeet Fast | 3.88% | 2.36% | 5.61% | 34 ms | 206x | 219 MB |
| Parakeet Accurate | 2.62% | 1.54% | 3.86% | 56 ms | 123x | 443 MB |

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
./run.sh --all-models                         # install all; select Base + Metal
./run.sh --engine parakeet                    # select Parakeet (no download)
```

Files live in `~/.cache/whisper/`. Missing choices remain visible but disabled.
An explicit model or engine option is persisted before the installed app
launches. Rerun the bootstrap whenever you want to add another model.

## Decoding

**Precision** is the default. It always uses five-beam whisper.cpp decoding.

**Smart Decode** uses a one-candidate greedy pass and accepts it only when its
token confidence, no-speech probability, and repetition checks are strong. It
automatically retries uncertain audio with the same five-beam Precision
decoder. The setting is available for the whisper.cpp Metal engine. Parakeet
and Cohere continue to use their native decoding behavior.

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
