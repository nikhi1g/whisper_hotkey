# Reproducible baseline

`run_baseline.py` wraps the existing LibriSpeech smoke runners without changing
recognition behavior. It records one metadata JSONL line followed by aggregate
metric lines. The metadata keeps the current checkout separate from the audited
`v3.6.2` release (`317fced`), and records the commit, dependency pins, model
and helper checksums, Swift/runtime identifiers, macOS build, Apple hardware,
engine, the tracked corpus-manifest hashes, and all three product processing
modes. Known Whisper model pins from `docs/MODELS.md` are included even when a
live model cache is unavailable; a live run also records and verifies the
selected file's observed digest.

The output is content-safe by construction. Per-utterance cases are ignored,
and any input result containing a transcript, hypothesis, reference, prompt,
or audio-bearing field is rejected. Audio and transcript files are never copied
or written by this path. The runner captures benchmark subprocess output rather
than forwarding it to the terminal.

## Reproduce the existing smoke benchmark

Use the existing 100-utterance LibriSpeech set (50 `test-clean` plus 50
`test-other`) and the already-built local helper/model. The model filename must
match one of the SHA-256 pins in `docs/MODELS.md`; an unknown or mismatched
model is rejected before recognition starts.

```sh
python3 Benchmarks/Baseline/run_baseline.py \
  --run-smoke \
  --helper .build/arm64-apple-macosx/debug/WhisperModelHelper \
  --model ~/.cache/whisper/ggml-large-v3-turbo-q5_0.bin \
  --wav-root Benchmarks/Data/WAV \
  --output /tmp/whisper-hotkey-baseline.jsonl
```

`--run-smoke` invokes the unchanged `benchmark_librispeech.py` for Precision
(the runner's `accuracy` profile), greedy, and Smart Decode (adaptive), then
invokes `benchmark_predecode.py` for the Decode While Speaking hook. Results are
written to the existing ignored `Benchmarks/Results/` directory by those
runners and only aggregate fields are copied into the JSONL output. Omit
`--run-smoke` to collect an existing result file:

```sh
python3 Benchmarks/Baseline/run_baseline.py \
  --helper .build/arm64-apple-macosx/debug/WhisperModelHelper \
  --model ~/.cache/whisper/ggml-large-v3-turbo-q5_0.bin \
  --result Benchmarks/Results/latest.json \
  --predecode-result Benchmarks/Results/predecode-latest.json \
  --output /tmp/whisper-hotkey-baseline.jsonl
```

The JSONL contains no universal accuracy claim. The 100-utterance read-speech
set is a regression smoke track only; its WER must not be attributed to the
shipped release or generalized to ordinary dictation. Release and current-main
measurements must be collected separately by running from the corresponding
checkout and comparing the `revision.build_line` and `revision.commit` fields.

The tracked `BenchmarkSuite` case manifest is hashed and reported, but the
legacy runners currently accept only `--per-split` and reconstruct evenly spaced
cases from the extracted corpus. They do not consume `case_ids.txt`; the
missing manifest hook is called out in `benchmark_corpus.runner_hooks` and in
the Phase 1 report.

## Focused check

```sh
python3 -m unittest discover -s Benchmarks/Baseline/tests -p 'test_*.py'
```

No benchmark output, model, audio, transcript, or log belongs in this tracked
source directory. Use a private temporary output path for a run. The collector
writes its output owner-only and keeps benchmark subprocess output in memory;
it never forwards helper output to the terminal.
