# Local models

Version 3.0.5 offers [whisper.cpp](https://github.com/ggml-org/whisper.cpp) with
Metal and flash attention, whisper.cpp with a Core ML encoder, and native
WhisperKit Core ML recognition. Recognition is English-only and entirely local.

| Menu choice | File | Download | Tradeoff |
| --- | --- | ---: | --- |
| Base English | `ggml-base.en.bin` | 141 MB | Fastest, lowest-memory, default |
| Small English | `ggml-small.en.bin` | 465 MB | Better accuracy, moderate latency |
| Medium English | `ggml-medium.en.bin` | 1.5 GB | Highest English-only accuracy, heaviest |
| Large-v3 Turbo Q5 | `ggml-large-v3-turbo-q5_0.bin` | 547 MB | Strong accuracy/speed balance |

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

The Engine chips in Settings are independent of model size:

- **Metal** is the default whisper.cpp GPU path.
- **Core ML Encoder** runs the encoder through Core ML while whisper.cpp
  performs decoding.
- **WhisperKit** performs native Core ML recognition using Apple GPU and Neural
  Engine compute units.

Core ML choices are enabled only when the selected model's complete verified
artifacts are installed. The running app never downloads missing files and
never silently switches engines.

## Install models

```sh
./run.sh                 # Base
./run.sh --model small
./run.sh --model medium
./run.sh --model turbo
./run.sh --all-models    # all four, about 2.7 GB
./run.sh --model turbo --engine coreml
./run.sh --model turbo --engine whisperkit
```

Files live in `~/.cache/whisper/`. Missing choices remain visible but disabled.
The normal application never downloads models.

## Decoding

**Precision** is the default. It always uses five-beam whisper.cpp decoding.

**Smart Decode** uses a one-candidate greedy pass and accepts it only when its
token confidence, no-speech probability, and repetition checks are strong. It
automatically retries uncertain audio with the same five-beam Precision
decoder. The setting is available for the whisper.cpp Metal and Core ML
encoder engines. WhisperKit continues to use its native decoding behavior.

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
