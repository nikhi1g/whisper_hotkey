# W06 verifier decision

Decision: **no promotion**.

This is a pinned preflight result from the W00 baseline head
`7990de553f6c4753f22ab38b7746d99ca2c3b639`, using the bounded experiment
configuration in
[`Benchmarks/VerifierExperiments/experiment_config.json`](../../Benchmarks/VerifierExperiments/experiment_config.json).
No candidate inference was run in this checkout. No model-card WER, archived
baseline number, or external claim is treated as a verifier measurement.

## Evidence boundary

The harness checks only local artifacts and accepts only aggregate-safe
measurements. It never downloads a model, opens audio, stores audio or
transcripts, or emits per-case text. The raw result path is
[`results.jsonl`](results.jsonl); it contains metadata, blocker checks,
candidate statuses, and aggregate metric slots only.

The repository smoke manifest is present and verified:

| Artifact | Version/license | SHA-256 status | W06 use |
| --- | --- | --- | --- |
| LibriSpeech-100 manifest | OpenSLR, CC BY 4.0 | `68a5faba032d266e415ab17b933e690803505e6a18222f4d5c91426af92123bb` verified | smoke metadata only |
| LibriSpeech-100 case-ID manifest | OpenSLR, CC BY 4.0 | `aad0550ac8a92e44163b0ed6f151c50c6cdeb6038ee843095b13c411835b1d5f` verified | selection provenance only |
| Turbo primary model pin | `ggml-large-v3-turbo-q5_0.bin` | `394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2` recorded; local file absent | baseline reference only |

The archived W00 smoke values remain reference-only: Turbo Precision
combined WER 4.3169% (p50 304.9 ms, p95 412.4 ms) and Smart Decode combined
WER 4.0437% (p50 289.3 ms, p95 363.8 ms). They were not rerun by W06 and do
not establish verifier overlap or repair quality.

## Candidate matrix

| Candidate | Runtime/model provenance | Local artifact/checksum | Error overlap | Oracle repair | Guarded repair | Latency/RSS/contention | Decision |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Existing Parakeet Unified 0.6B | FluidAudio 0.15.5 at `19600a485baa4998812e4654b70d2bab8f2c9949`; NVIDIA model card, CC-BY-4.0 | local model directory absent; checksum `null` | not measured | not measured | not measured | not measured | blocked |
| Full Whisper large-v3 | whisper.cpp 1.9.1 at `f049fff95a089aa9969deb009cdd4892b3e74916`; OpenAI model card, Apache-2.0 | artifact absent; checksum `null` | not measured | not measured | not measured | not measured | blocked |
| Parakeet TDT-CTC 1.1B hybrid | parakeet.cpp revision/runtime absent; NVIDIA model card, CC-BY-4.0 | artifact and runtime absent; checksum `null` | not measured | not measured | not measured | not measured | blocked |
| Parakeet TDT 1.1B | parakeet.cpp revision/runtime absent; NVIDIA model card, CC-BY-4.0 | artifact and runtime absent; checksum `null` | not measured | not measured | not measured | not measured | blocked |
| Qwen3-ASR 1.7B (optional) | Apple-local runtime absent; Qwen model card, Apache-2.0 | artifact/runtime absent; checksum `null` | not measured | not measured | not measured | not measured | not run |

The report includes schemas for error-set overlap, oracle repair, actual
guarded repair, cold/warm latency, p50/p95/p99 completion latency, peak RSS,
span coverage, and Apple Silicon contention. Every candidate metric is
`null`/unmeasured because no candidate output was supplied.

## Blocking prerequisites

- The verified Turbo model file and `WhisperModelHelper` are not present for a
  local primary run.
- LibriSpeech smoke audio is absent even though its tracked metadata is
  present.
- The existing Parakeet Unified model directory is absent, so the Stage 1
  cross-engine verifier comparison cannot run.
- The full Whisper large-v3 artifact has no local conversion/checksum.
- The Parakeet TDT and TDT-CTC 1.1B artifacts and parakeet.cpp runtime are
  absent.
- The optional Qwen3-ASR artifact and Apple-compatible runtime are absent.
- No consented frozen application dictation corpus or public recovery corpus
  was supplied, so WER improvement and promotion safety cannot be established.

## Pinned fallback and follow-up

No verifier is selected and no model is kept resident. The production-safe
fallback remains primary-only recognition; verifier timeout/failure must return
the guarded primary result. Before reconsidering promotion, supply local,
licensed/consented artifacts and corpus manifests, record exact checksums and
runtime revisions, run bounded spans on the frozen tracks, and require repair
precision ≥ 98%, high-confidence corruption ≤ 0.05%, protected number/unit/
negation regressions = 0, measured p95/RSS, and paired accuracy evidence.
