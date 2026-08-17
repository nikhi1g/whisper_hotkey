# Post-processing preservation bench

Offline preservation bench for the voice-to-prompt post-processing pipeline
(`POST_PROCESSING_PLAN.md` §6). It records the DeepSeek processor's behavior on
a synthetic gate corpus and replays the recordings against deterministic
machine checks — no model access needed to run the gates.

```
Benchmarks/Performance/post-processing/
  corpus.json        synthetic gate cases (§6) + project-specific cases
  record_cassette.py live recorder (needs DEEPSEEK_API_KEY)
  run_bench.py       offline replay + §6 gate table
  fixtures/          synthetic cassettes so the bench runs with no recordings
```

The corpus is synthetic only — no real user transcripts. Cassettes recorded
against the live API live in `Benchmarks/Data/postprocessing-cassettes/`
(gitignored by design: they contain raw transcripts). Never commit them.

## Recording live cassettes

```sh
DEEPSEEK_API_KEY=sk-... python3 Benchmarks/Performance/post-processing/record_cassette.py
```

- `DEEPSEEK_API_KEY` is required. Without it the script prints a skip message
  and exits 0 so the offline bench remains the default path.
- Model: `DEEPSEEK_PROCESSOR_MODEL` env var, default `deepseek-v4-flash`
  (matches the app client's `DeepSeekConfiguration`).
- Each case is POSTed to `{baseURL}/chat/completions` with the same payload
  shape the app client sends: `response_format {"type":"json_object"}`,
  `thinking {"type":"disabled"}`, `max_tokens 800`. The system prompt is
  assembled from the profile catalog fields (transducer constraints + profile
  objective/allowed/forbidden), mirroring `SemanticProfileCatalog`.
- One cassette per case: `{case_id, request, response_json, latency_ms,
  recorded_at}`. `latency_ms` is the measured round trip and feeds the p50/p95
  gates.
- Useful overrides: `--model`, `--base-url`, `--cassettes-dir`, `--corpus`.

## Running the bench (offline)

```sh
python3 Benchmarks/Performance/post-processing/run_bench.py
```

Loads every cassette in `Benchmarks/Data/postprocessing-cassettes/`; when none
exist it falls back to `fixtures/` (marked `synthetic: true`) so the gates can
always run. Prints per-case PASS/FAIL, flagged manual-review rows, aggregate
pass rate, latency p50/p95, the gate table, and exits 0 only when every gate
passes.

## Gates (`POST_PROCESSING_PLAN.md` §6)

| Gate | Threshold |
| --- | --- |
| Preservation pass rate (all replayed cases) | ≥ 95% |
| Hard failures (gate cases g01–g07, p01) | 0 |
| Negation / uncertainty / identifier preservation (g02–g04, p01) | 100% |
| Explain-instead-of-rewrite marker hits | 0 |
| Processor round-trip p50 / p95 (from cassette `latency_ms`) | ≤ 1.0 s / ≤ 3.0 s |
| Local validation determinism | 100% |

Determinism is verified by re-evaluating every case in the same run and
requiring an identical verdict set. Auto-send stays disabled until the owner
explicitly enables it; these gates only decide eligibility.

## Machine checks per case

Checks are declared in `corpus.json` under `checks`:

- `required_substrings` / `forbidden_substrings`: case-insensitive substring
  containment in `finalText`. Forbidden markers are how "explain instead of
  rewrite" and unresolved self-corrections are detected mechanically (e.g.
  `"caching works by"`).
- `required_tokens`: exact token containment — whitespace tokens with
  surrounding punctuation stripped, casefolded. `useEffect` never matches
  `useEffectHook`; `C++` and `/api/v1` survive because `+` and `/` are not
  stripped.
- `max_meaning_change_risk`: result `meaningChangeRisk` (low < medium < high)
  must not exceed the allowed level.
- Preservation check (always on): every token of every `protected_terms` entry
  must appear in `finalText`.
- `manual_review: true`: machine checks still run, and the case is additionally
  flagged for human review — the model may be right and the machine simply
  cannot verify it (low-confidence names, explanation requests, coding
  dictation without a stated language).

## Corpus cases

| id | raw text | gate |
| --- | --- | --- |
| g01-self-correction | "Tuesday, no, Thursday" | explicit self-correction resolved |
| g02-uncertainty | "I might need to delete it" | uncertainty preserved |
| g03-negation | "Do not delete it" | negation preserved (literal `not`) |
| g04-identifiers | useEffect / C++ / /api/v1 dictation | identifiers preserved exactly |
| g05-low-confidence-name | synthetic proper name | manual review |
| g06-explain-request | "Explain how caching works" | no answer, no explanation marker |
| g07-unspecified-language | coding dictation, no language | manual review |
| p01-fastapi-self-correction | "Use fast API no I mean FastAPI … post slash process" | project self-correction + dictation phrasing |
| p02-dictation-phrasing | "twenty four hours … five percent" | numbers/percent preserved |

The synthetic fixtures cover three machine-check paths end to end: the
verbatim self-correction case (`g01`), the coding/FastAPI case (`p01`), and
the negation case (`g03`). All fixtures must pass the gates.
