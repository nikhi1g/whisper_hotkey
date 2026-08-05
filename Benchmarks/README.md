# Recognition benchmarks

The benchmark uses deterministic samples from the official
[LibriSpeech](https://www.openslr.org/12) `test-clean` and `test-other` splits
used by [OpenAI to evaluate Whisper](https://github.com/openai/whisper/blob/main/data/README.md).
LibriSpeech is distributed under CC BY 4.0.

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

The downloader pins the checksums published by OpenSLR. Results contain
aggregate and per-utterance timing, word-error counts, and numeric confidence
measurements, but never audio or transcript text. `--wav-root` must mirror the
split and utterance IDs from LibriSpeech and contain private-mode, 16 kHz, mono
PCM16 WAV files. The predecode benchmark simulates real-time chunk availability
to compare release-to-result latency while still executing recognition locally.
