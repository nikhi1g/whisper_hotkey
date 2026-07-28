# Local models

Version 1.0.0 uses [whisper.cpp](https://github.com/ggml-org/whisper.cpp) with
Metal and flash attention. Recognition is English-only and entirely local.

| Menu choice | File | Download | Tradeoff |
| --- | --- | ---: | --- |
| Base English | `ggml-base.en.bin` | 141 MB | Fastest, lowest-memory, default |
| Small English | `ggml-small.en.bin` | 465 MB | Better accuracy, moderate latency |
| Medium English | `ggml-medium.en.bin` | 1.5 GB | Highest English-only accuracy, heaviest |
| Large-v3 Turbo Q5 | `ggml-large-v3-turbo-q5_0.bin` | 547 MB | Strong accuracy/speed balance |

Memory varies with whisper.cpp, Metal allocation, and recording length, so the
menu shows download size rather than promising a fixed RAM number. Models load
only for active dictation and unload afterward.

## Decoder

- Beam search width 5
- English forced
- Metal and flash attention enabled
- Half the logical CPUs, minimum 4 and maximum 8 threads
- No cloud refinement or live partial transcript

Beam search retains several plausible word sequences instead of committing to
one immediately. Width five improves ambiguous phrases and punctuation at a
modest latency cost.

## Install models

```sh
./run.sh                 # Base
./run.sh --model small
./run.sh --model medium
./run.sh --model turbo
./run.sh --all-models    # all four, about 2.7 GB
```

Files live in `~/.cache/whisper/`. Missing choices remain visible but disabled.
The normal application never downloads models.

## SHA-256

```text
a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002  ggml-base.en.bin
c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d  ggml-small.en.bin
cc37e93478338ec7700281a7ac30a10128929eb8f427dda2e865faa8f6da4356  ggml-medium.en.bin
394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2  ggml-large-v3-turbo-q5_0.bin
```

`run.sh` downloads from `ggerganov/whisper.cpp` on Hugging Face and refuses
mismatched content.
