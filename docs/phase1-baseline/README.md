# Phase 1 baseline and reproduction

This is the W00 repository baseline for the Phase 1 accuracy work. It records
the current-main source at commit `210009e607e70e2b7c506144a230a82e1447b37f`,
keeps it separate from the audited `v3.6.2` release (`317fced`), and does not
claim a universal WER result.

## Artifacts

- [`baseline.jsonl`](baseline.jsonl) is machine-readable, aggregate-only
  provenance and metric output. It contains no audio, transcript, hypothesis,
  reference, prompt, or per-utterance text.
- [`audit-diff.json`](audit-diff.json) and [`audit-diff.md`](audit-diff.md)
  compare the nine facts in the packet's `MD/02_CURRENT_REPOSITORY_AUDIT.md`
  with the source actually present in this checkout.
- The archived aggregate inputs are the tracked
  `Benchmarks/BenchmarkSuite/datasets/merged/librispeech-100/whisper-latest.json`
  and `whisper-predecode.json` files. Their SHA-256 values are recorded in the
  JSONL; their per-case records are not copied into the baseline artifact.

## Reproduction commands

From a macOS checkout with the ignored corpus, a pinned helper, and a verified
Turbo model present:

```sh
python3 Benchmarks/Scripts/download_librispeech.py
swift build --product WhisperModelHelper
python3 Benchmarks/Baseline/run_baseline.py \
  --run-smoke \
  --helper .build/arm64-apple-macosx/debug/WhisperModelHelper \
  --model ~/.cache/whisper/ggml-large-v3-turbo-q5_0.bin \
  --wav-root Benchmarks/Data/WAV \
  --output "$(mktemp -t whisper-hotkey-baseline).jsonl"
```

The wrapper invokes the existing full-recording and predecode runners with
captured subprocess output. It verifies the selected model against the pinned
SHA-256 before running, records the helper digest, and writes only aggregate
metrics. The output path should be private; the wrapper also applies owner-only
permissions.

This checkout does not contain `Benchmarks/Data/WAV` or a built
`WhisperModelHelper`, so a live 100-utterance inference run was not performed
here. The verified local Turbo model is present; its observed digest is
recorded in the JSONL metadata. The checked-in JSONL therefore uses the tracked
aggregate inputs as a reproducible source-compatible extraction and labels the
live application smoke coverage explicitly. No archived number below is a new
inference measurement from this turn.

## Archived smoke-track metrics

The existing 100-utterance LibriSpeech selection is a regression smoke track,
not a product accuracy claim. Values below are preserved from the archived
inputs and are also represented in `baseline.jsonl`:

| Hook | Profile | WER | p50 | p95 | Notes |
| --- | --- | ---: | ---: | ---: | --- |
| Full recording | Precision | 4.3169% | 304.9 ms | 412.4 ms | 50 `test-clean` + 50 `test-other` |
| Full recording | Smart Decode | 4.0437% | 289.3 ms | 363.8 ms | 2% adaptive fallback |
| Decode While Speaking | Precision, full | 4.3169% | 450.2 ms | 839.5 ms | archived predecode comparison |
| Decode While Speaking | Precision, predecoded | 5.4098% | 383.3 ms | 716.0 ms | 1.59 mean chunks |

The archived predecode comparison reduces mean release latency from 527.5 ms
to 448.2 ms while increasing the smoke-track WER. That tradeoff is a baseline
observation, not a promotion decision.

## Mode and corpus coverage

| Product mode | Existing hook | W00 status |
| --- | --- | --- |
| After Recording | `benchmark_librispeech.py` full recording | helper-path smoke only; no app lifecycle exercise |
| Model Ready | `benchmark_librispeech.py` full recording | helper-path smoke only; no resident-model lifecycle exercise |
| Decode While Speaking | `benchmark_predecode.py` | archived predecode comparison; no app lifecycle exercise |

The legacy benchmark scripts select evenly spaced files using `--per-split`.
They do not accept the tracked `case_ids.txt`/manifest, so the corpus hook is
recorded as missing rather than silently treating the two selections as
identical. There is also no existing benchmark hook for the app's hotkey,
permission, cancellation, or all mode-combination lifecycle. Those are follow-up
dependencies for the benchmark/metrics and integration workers.

The report records the current pinned versions: Swift tools 6.0, macOS target
14, FluidAudio 0.15.5 (revision
`19600a485baa4998812e4654b70d2bab8f2c9949`), and whisper.cpp 1.9.1 at commit
`f049fff95a089aa9969deb009cdd4892b3e74916`. The four Whisper model SHA-256
pins are copied from `docs/MODELS.md` and repeated in the JSONL metadata. Host
OS/runtime identifiers are captured at collection time; hardware fields that
the host does not expose remain null rather than being guessed.
