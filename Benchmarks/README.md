# Recognition benchmarks

The benchmark uses deterministic samples from the official
[LibriSpeech](https://www.openslr.org/12) `test-clean` and `test-other` splits
used by [OpenAI to evaluate Whisper](https://github.com/openai/whisper/blob/main/data/README.md).
LibriSpeech is distributed under CC BY 4.0.

Tracked benchmark assets are now kept in `Benchmarks/BenchmarkSuite/`. The large
audio and transient result artifacts still live under `Benchmarks/Data` and
`Benchmarks/Results` as before.

Downloaded audio and generated results stay in the ignored `Data/` and
`Results/` directories.

```sh
python3 Benchmarks/Scripts/download_librispeech.py
python3 Benchmarks/Scripts/benchmark_librispeech.py \
  --helper .build/arm64-apple-macosx/debug/WhisperModelHelper \
  --model ~/.cache/whisper/ggml-large-v3-turbo-q5_0.bin \
  --wav-root Benchmarks/Data/WAV
python3 Benchmarks/Scripts/benchmark_predecode.py \
  --helper .build/arm64-apple-macosx/debug/WhisperModelHelper \
  --model ~/.cache/whisper/ggml-large-v3-turbo-q5_0.bin \
  --wav-root Benchmarks/Data/WAV
```

Regenerate tracked suite assets when you refresh results:

```sh
python3 Benchmarks/BenchmarkSuite/scripts/sync_assets.py
python3 Benchmarks/BenchmarkSuite/tests/run_suite_asset_checks.py
```

The suite catalog of broader benchmark candidates is in:

```
Benchmarks/BenchmarkSuite/datasets/catalog.json
```

## Parakeet

The Parakeet engine is measured with a separate harness, kept in its own
package under `Parakeet/` so FluidAudio never links into a shipped bundle. It
transcribes the same WAVs the whisper benchmark uses, and `score_parakeet.py`
applies the same tokenizer and edit-distance math, so the two are comparable.

```sh
python3 - <<'EOF' > /tmp/wavlist.txt
import json, os
cases = json.load(open("Benchmarks/Results/latest.json"))["profiles"]["accuracy"]["cases"]
root = os.path.abspath("Benchmarks/Data/WAV")
print("\n".join(os.path.join(root, c["split"], c["id"] + ".wav") for c in cases))
EOF
swift build --package-path Benchmarks/Parakeet -c release
./Benchmarks/Parakeet/.build/release/parakeet-benchmark v2 /tmp/wavlist.txt \
  > /tmp/parakeet-v2.jsonl
python3 Benchmarks/Scripts/score_parakeet.py /tmp/parakeet-v2.jsonl
```

The variant argument is `v2` (the 0.6B model behind the Small, Medium, and
Turbo chips), `tdtCtc110m` (the 110M model behind the Base chip), or `v3` (the
multilingual 0.6B model the app does not select, since recognition is
English-only). The first run downloads the checkpoint. Two warm-up passes run
before timing so the measurement reflects a resident model, matching how the
whisper benchmark drives an already-loaded helper.

## Parakeet Unified

```sh
./Benchmarks/Parakeet/.build/release/parakeet-benchmark unified /tmp/wavlist.txt \
  > /tmp/unified.jsonl
python3 Benchmarks/Scripts/score_parakeet.py /tmp/unified.jsonl
```

Measured on the 100-utterance set, Apple M5 Pro, against the shipping engine:

| Engine | Combined WER | test-clean | test-other | Mean | p50 | p95 | Disk |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Parakeet Unified | **2.46%** | **1.44%** | **3.63%** | **50 ms** | **41 ms** | 105 ms | 594 MB |
| Parakeet TDT v2 | 2.62% | 1.54% | 3.86% | 56 ms | 53 ms | **78 ms** | 443 MB |

Unified wins every accuracy measure and both mean and median latency. Its only
regression is the tail: it transcribes audio longer than 15 s with overlapping
windows, and all seven files over that length in this set are slower than v2
(138 ms against 100 ms at the worst). Dictation phrases are far shorter than
that, so the median is the number that matters and the tail is bounded.

## Cohere Transcribe

The same harness benchmarks Cohere Transcribe, so its numbers are directly
comparable to Parakeet's rather than to a published leaderboard average.

```sh
./Benchmarks/Parakeet/.build/release/parakeet-benchmark cohere-download
./Benchmarks/Parakeet/.build/release/parakeet-benchmark cohere /tmp/wavlist.txt \
  > /tmp/cohere.jsonl
python3 Benchmarks/Scripts/score_parakeet.py /tmp/cohere.jsonl
```

Measured on the 100-utterance set, Apple M5 Pro:

| Engine | Combined WER | test-clean | test-other | Mean latency |
| --- | ---: | ---: | ---: | ---: |
| Parakeet Accurate | 2.62% | 1.54% | 3.86% | 56 ms |
| Cohere Transcribe | 2.57% | 1.13% | 4.21% | 629 ms |

Cohere ranks 0.63 WER ahead of Parakeet on the Open ASR Leaderboard's
seven-split mean, and that lead does not survive contact with this corpus: the
two tie overall, Cohere wins on clean read speech, Parakeet wins on noisy
speech, and Cohere costs eleven times the latency. Leaderboard rank is a
screening signal, not a decision.

The downloader pins the checksums published by OpenSLR. Results contain
aggregate and per-utterance timing, word-error counts, and numeric confidence
measurements, but never audio or transcript text. `--wav-root` must mirror the
split and utterance IDs from LibriSpeech and contain private-mode, 16 kHz, mono
PCM16 WAV files. The predecode benchmark simulates real-time chunk availability
to compare release-to-result latency while still executing recognition locally.
