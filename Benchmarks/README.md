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
```

The downloader pins the checksums published by OpenSLR. Results contain
aggregate and per-utterance timing, word-error counts, and numeric confidence
measurements, but never audio or transcript text. `--wav-root` must mirror the
split and utterance IDs from LibriSpeech and contain private-mode, 16 kHz, mono
PCM16 WAV files.
