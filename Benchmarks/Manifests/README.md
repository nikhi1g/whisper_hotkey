# Frozen benchmark manifests

The manifest files define three independent tracks:

- `smoke-100.json` preserves the existing 100-utterance LibriSpeech
  `test-clean`/`test-other` selection. Its case-list checksum is frozen and
  the existing `Benchmarks/Scripts/benchmark_librispeech.py` command remains
  the smoke runner.
- `full-public.json` records the required public evaluation tracks. Entries
  marked `metadata-only` or `planned` are intentionally not downloaded by the
  application or benchmark tooling until upstream terms are verified.
- `application-corpus.json` is a synthetic, content-free descriptor fixture.
  A consented local corpus may replace it for an evaluation run, but ordinary
  user recordings are never an implicit source.

All tracks use the same frozen normalizer and report its implementation hash.
The application descriptor contains speaker/session-disjoint partitions and
protected slices for names, acronyms, numbers, units, homophones, pauses,
self-restarts, boundaries, and noise conditions. The descriptor has no audio
or transcript text.

Score a local, ephemeral JSONL run with:

```sh
python3 Benchmarks/Metrics/score_benchmark.py input.jsonl \
  --run-id example --commit "$(git rev-parse HEAD)" > result.json
python3 Benchmarks/Metrics/paired_bootstrap.py paired.jsonl > paired.json
python3 Benchmarks/Metrics/ablation_report.py ablations.jsonl > ablations.json
```

Benchmark result, dataset, paired-bootstrap, and ablation artifacts are
numeric/metadata-only. Do not put audio, references, hypotheses, or ordinary
user recordings in tracked files or generated result directories.
