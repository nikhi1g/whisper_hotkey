# M5 Pro 24 GB preflight

Collected on 2026-08-08 from the W00 baseline checkout (`7990de5`, before
W13 edits) using local host tools only. The report intentionally omits the
machine serial number, hardware UUID, user name, home-directory paths, audio,
and transcript content.

## Host facts

| Fact | Observed value |
| --- | --- |
| Model | MacBook Pro, `Mac17,9` |
| Chip | Apple M5 Pro |
| CPU cores | 15 reported (5 super + 10 performance) |
| GPU cores | 16 reported |
| Memory | 24 GB |
| Architecture | arm64 |
| macOS | 26.5.2, build `25F84` |
| Kernel | Darwin 25.5.0 |
| `xctrace` | available, version 16.0 (17F113) |

`system_profiler` was the authoritative source for the core and memory counts;
the restricted `sysctl` probe did not expose those fields. No core-count
assumption was used to claim a performance result.

## Engine and fixture preflight

No local ASR inference was run in this safe preflight. The checkout did not
contain an executable `WhisperModelHelper`, an executable
`parakeet-benchmark`, or the private `Benchmarks/Data/WAV` fixture root. The
local cache did contain the already-verified Base and Turbo model files from
the W00 setup, but a model file without its matching helper and private fixture
cannot produce a valid engine measurement.

Therefore the following metrics are intentionally **unmeasured**:

- warm/cold p50, p95, and p99 latency;
- real-time factor (RTF);
- model residency and peak RSS during inference;
- temporary span/storage growth attributable to an engine;
- helper leaks under soak/cancel;
- sequential versus ANE+Metal heterogeneous/concurrent placement;
- sustained inference thermal behavior.

The exact fail-closed blockers are:

1. `WhisperModelHelper` executable missing.
2. `parakeet-benchmark` executable missing, and the existing source-level
   benchmark interface is batch JSONL rather than a per-request overlap
   adapter.
3. Private WAV fixture root missing.
4. No second installed per-request engine means concurrent placement cannot be
   compared to sequential execution.

The performance tool records these blockers in `preflight` and
`comparisons[].blockers`; it does not insert zeroes or copy archived latency
numbers into a W13 result.

The machine-readable result also contains explicit `unmeasured` rows for the
8 GB, 16 GB, and 24 GB Apple Silicon tiers. The 24 GB row documents this
host's hardware preflight, but remains unmeasured for ASR until a helper and
private fixture are run.

## Thermal and tracing notes

`xctrace` is available for a future aggregate Time Profiler/Allocations/Metal
System Trace run. `powermetrics` is installed but requires privileged sampling
and is not invoked by the harness. `pmset -g therm` returned no CPU power or
thermal state on this host, so thermal status is recorded as unavailable. No
raw command output is persisted.

## Next safe run

After building the helper and preparing a private, owner-only fixture, run the
commands in [`README.md`](README.md). Keep each output JSON in a private
temporary location, inspect aggregate fields only, and remove any Instruments
trace after extracting the necessary totals. A lower-memory result must be
collected on a separate 8 GB or 16 GB Apple Silicon host; this report makes no
claim for those hosts.
