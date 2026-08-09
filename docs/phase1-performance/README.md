# Phase 1 performance, memory, and reliability

This directory describes the content-free performance harness owned by W13.
The harness measures a locally installed Whisper helper only when the helper,
model, and a private WAV fixture are all present. It records aggregate
latency/RTF, resident memory, profiler-owned temporary storage, process
reaping, and thermal-tool availability. It never writes audio, transcripts,
helper stdout/stderr, or per-utterance identifiers.

The machine-readable contract is [`result-schema.json`](result-schema.json).
The safe measurement taken on the current host is recorded in
[`m5-pro-24gb-preflight.md`](m5-pro-24gb-preflight.md). It is a preflight, not
an ASR benchmark: no engine result is filled in when the required executable
or corpus is absent.

## Commands

Run a host/tool preflight without touching audio or models:

```sh
python3 Benchmarks/Performance/profile_performance.py \
  --preflight --compare --output "$(mktemp -t whisper-hotkey-performance).json"
```

With an already-built helper, a verified model, and owner-only 16 kHz mono
PCM16 WAVs, run a bounded warm-helper profile. The output path should be a
private temporary file; the harness changes it to mode `0600`.

```sh
python3 Benchmarks/Performance/profile_performance.py \
  --helper .build/arm64-apple-macosx/debug/WhisperModelHelper \
  --model "$HOME/.cache/whisper/ggml-large-v3-turbo-q5_0.bin" \
  --wav-root Benchmarks/Data/WAV \
  --max-cases 10 --repeats 2 --threads 4 \
  --output "$(mktemp -t whisper-hotkey-performance).json"
```

Run the bounded restart/cancel soak with one cancellation every third
iteration:

```sh
python3 Benchmarks/Performance/soak_cancel.py \
  --helper .build/arm64-apple-macosx/debug/WhisperModelHelper \
  --model "$HOME/.cache/whisper/ggml-large-v3-turbo-q5_0.bin" \
  --wav-root Benchmarks/Data/WAV \
  --iterations 10 --cancel-every 3 --cancel-after-ms 100 \
  --output "$(mktemp -t whisper-hotkey-soak).json"
```

`--compare` always fails closed unless two installed engines have usable
per-request adapters. The existing Parakeet benchmark executable is a batch
JSONL runner, so it is not treated as an overlap-capable adapter. A report with
`status: unavailable` and precise `blockers` is the expected result until that
preflight is satisfied.

## Metrics and bounds

For each measured profile, latency and RTF are reported as nearest-rank p50,
p95, and p99 values. RTF is wall time divided by the validated WAV duration;
an aggregate RTF is also reported. Cold helper start, warm-helper RSS, peak
RSS, and the maximum bytes/files in a profiler-owned empty temporary directory
are separate fields. Input WAVs are never copied, so the temporary-storage
number does not claim to include opaque runtime caches outside the harness.

Hard bounds are part of the report: at most 100 cases, 500 measurements, 60
seconds per input, 1,000 discovered fixture paths, 256 KiB per helper JSONL
event, 256 temporary files, 15
minutes of profile/soak wall time, one call per helper, and at most two engine
processes for a future heterogeneous experiment. Helper stdout/stderr is
discarded in memory and never persisted.

The soak harness verifies only owned helper-process termination. Paste
suppression and stale-result generation gating remain application-level tests;
the report states those limits explicitly rather than claiming to verify them.

## Lower-memory matrix

Run the same fixture and model profile on Apple Silicon hosts with 8 GB, 16
GB, and 24 GB or more. Record the host facts, cold/warm latency, p50/p95/p99,
RTF, peak RSS, temporary storage, cancellation/reaping counts, and thermal
state in the schema. A row stays `unmeasured` until its local helper/model and
private fixture are installed. Do not substitute a different engine or infer
results from core count or model file size.

## Deterministic placement and fallback policy

The default policy is one resident primary helper and serialized calls per
runtime. Heterogeneous ANE+Metal overlap is enabled only after a paired run
has both sequential and concurrent measurements on the same host, with the
same fixture, model versions, and warm/cold protocol. Two Metal-heavy model
processes are otherwise measured as sequential only.

If thermal state becomes elevated or memory pressure prevents a new lease:

1. keep the selected primary model and its accuracy settings;
2. stop starting additional verifier work and finish/cancel only owned work;
3. use sequential primary/verification and the bounded highest-risk coverage;
4. defer optional formatting refinement;
5. never silently swap or downgrade the primary model.

`xctrace`/Instruments traces are optional, aggregate-only investigation
artifacts. Keep `.trace` files in a private temporary directory, export only
aggregate tables needed for the report, and remove the trace after review. The
current host has `xctrace` installed; privileged `powermetrics` sampling is
not automated by this harness.

For a trace around a bounded profile, keep the trace outside the repository:

```sh
trace_dir="$(mktemp -d -t whisper-hotkey-trace)"; chmod 700 "$trace_dir"
xctrace record --template 'Time Profiler' \
  --output "$trace_dir/profile.trace" --launch -- \
  python3 Benchmarks/Performance/profile_performance.py \
    --helper .build/arm64-apple-macosx/debug/WhisperModelHelper \
    --model "$HOME/.cache/whisper/ggml-large-v3-turbo-q5_0.bin" \
    --wav-root Benchmarks/Data/WAV --max-cases 1 --repeats 1 \
    --output "$trace_dir/profile.json"
```

Export only aggregate Instruments tables for review, then remove the private
trace directory. A trace is not a result until the report also records the
fixture/model revision and the content-free aggregate metrics.
