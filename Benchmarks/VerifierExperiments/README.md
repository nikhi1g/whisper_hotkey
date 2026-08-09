# Bounded verifier experiments

This harness is an offline analysis and preflight layer for W06. It does not
download, invoke, or install a model. A local engine runner may provide an
aggregate-safe measurement exchange, but the exchange must contain only:

- opaque `sha256:<64 hex>` case identifiers;
- aligned integer word positions for primary/verifier error sets;
- accepted/rejected guard decisions; and
- numeric latency, span, RSS, contention, and thermal observations.

Transcript text, references, prompts, tokens, word strings, audio bytes, audio
paths, and waveform data are rejected recursively. The output contains only
aggregate metrics and provenance. It never copies or opens an audio file.

## Preflight-only run

From the repository root, run:

```sh
python3 Benchmarks/VerifierExperiments/run_experiments.py \
  --output "$(mktemp -t whisper-hotkey-verifier).jsonl"
```

The command performs local existence, privacy, version, and SHA-256 checks. It
does not fetch a missing model or corpus. `--candidate-artifact
candidate-id=path` supplies an already-installed local artifact for a future
run; an observed candidate checksum remains `present_unpinned` until it is
added to the pinned configuration. The application and public corpus
manifests/audio roots are explicit arguments and are required for promotion.

## Measurement exchange

`--measurements` accepts one JSON object using
`whisper_hotkey_verifier_measurements_v1`. Every item needs an opaque case
digest, a reference word count, primary/verifier error positions, edit guard
decisions, audio/span durations, and completion latency. Cold/warm load, RSS,
CPU/Metal/ANE, and thermal fields are optional; omitted values are reported as
unmeasured rather than inferred.

The analyzer enforces the bounds in `experiment_config.json`: an 8-second
normal verifier span, 25% maximum verifier-audio coverage, eight spans per
item, 64 spans per run, one concurrent call per runtime, and bounded item,
position, edit, context, and audio-duration counts. A violation aborts the
run before output is written.

An input intended for promotion must also include numeric application primary
and candidate WERs, paired-support/public-regression booleans, and the
protected-regression count. If that accuracy block is omitted, the result is
explicitly `unmeasured` and cannot become eligible for promotion.

## Metrics

The result schema (`verifier-result-v1.schema.json`) includes:

- `errorOverlap`: primary/verifier error-set intersection, union, Jaccard,
  and primary overlap rate;
- `oracleRepair`: errors the verifier could fix if every verifier-correct
  position were accepted;
- `guardedRepair`: accepted edits, true repairs, introduced errors, repair
  precision/recall, unsafe accepts, and high-confidence corruption count/rate;
- `latency`: completion p50/p95/p99 plus cold and warm-load p50/p95;
- `rss`: observed peak and mean peak RSS; and
- `spanBudget` and `contention`, with `null`/`unmeasured` values when the
  local runner did not collect them.

The harness does not turn a model-card WER or a baseline number into a W06
measurement. A promotion decision requires local candidate output, pinned
artifact checksums, the frozen application corpus, public recovery tracks, and
the configured safety/resource gates.

## Current checkout

The current W00 checkout has the tracked LibriSpeech-100 manifest and case-ID
hash, but no local smoke audio, helper, or model file. It also has no full
Parakeet Unified model directory for the Stage 1 cross-engine check, full
Whisper large-v3 artifact, Parakeet 1.1B/parakeet.cpp runtime, Qwen3-ASR local
runtime, consented application corpus, or public recovery corpus. The default
report therefore records explicit blockers and a no-promotion decision. See
[`docs/phase1-verifier/verifier_decision.md`](../../docs/phase1-verifier/verifier_decision.md)
and the aggregate-only raw output at
[`docs/phase1-verifier/results.jsonl`](../../docs/phase1-verifier/results.jsonl).

Candidate licenses and upstream references are pinned in
`experiment_config.json`; artifact checksums are intentionally `null` until a
local artifact is supplied and verified. The runtime pins are whisper.cpp
1.9.1 (`f049fff95a089aa9969deb009cdd4892b3e74916`) and FluidAudio 0.15.5
(`19600a485baa4998812e4654b70d2bab8f2c9949`) where applicable. Qwen3-ASR is
optional and cannot be promoted without an Apple-compatible local runtime.
