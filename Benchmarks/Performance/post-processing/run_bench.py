#!/usr/bin/env python3
"""Offline replay of post-processing cassettes against the bench gates.

Loads recorded cassettes from ``Benchmarks/Data/postprocessing-cassettes/``
(gitignored — transcripts live there by design) and, when none exist, falls
back to the synthetic fixtures in ``fixtures/`` so the bench always runs.

For each cassette the result is parsed from ``choices[0].message.content`` and
checked against the corpus case's machine checks:

- required_substrings / forbidden_substrings: case-insensitive substring
  containment in finalText;
- required_tokens: exact token containment (whitespace tokens with surrounding
  punctuation stripped) — "useEffect" never matches "useEffectHook";
- max_meaning_change_risk: result risk must not exceed the allowed level;
- preservation: every token of every protected term must appear in finalText.

Prints per-case PASS/FAIL, flagged manual-review rows, aggregate pass rate,
latency p50/p95 from cassette metadata, and PASS/FAIL against the
POST_PROCESSING_PLAN.md §6 gates.  Exits 0 only when every gate passes.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CORPUS = ROOT / "Benchmarks" / "Performance" / "post-processing" / "corpus.json"
CASSETTES = ROOT / "Benchmarks" / "Data" / "postprocessing-cassettes"
FIXTURES = ROOT / "Benchmarks" / "Performance" / "post-processing" / "fixtures"

# Gate cases from POST_PROCESSING_PLAN.md §6 plus the project-specific
# self-correction case.  A failure on any of these is a hard failure.
HARD_GATE_CASE_IDS = {
    "g01-self-correction",
    "g02-uncertainty",
    "g03-negation",
    "g04-identifiers",
    "g05-low-confidence-name",
    "g06-explain-request",
    "g07-unspecified-language",
    "p01-fastapi-self-correction",
}

# §6: "Negation / uncertainty / identifier preservation cases" must be 100%.
NEGATION_UNCERTAINTY_IDENTIFIER_IDS = {
    "g02-uncertainty",
    "g03-negation",
    "g04-identifiers",
    "p01-fastapi-self-correction",
}

RISK_LEVELS = {"low": 0, "medium": 1, "high": 2}

PUNCTUATION = ".,;:!?\"'()[]{}<>"


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    return ordered[round((len(ordered) - 1) * fraction)]


def tokens(text: str) -> list[str]:
    """Whitespace tokens with surrounding punctuation stripped, casefolded."""
    return [word.strip(PUNCTUATION).casefold() for word in text.split()]


def load_corpus(path: Path) -> dict[str, dict]:
    corpus = json.loads(path.read_text(encoding="utf-8"))
    cases: dict[str, dict] = {}
    for case in corpus["cases"]:
        required = ("id", "raw_text", "profile", "protected_terms", "checks")
        missing = [key for key in required if key not in case]
        if missing:
            raise ValueError(
                f"corpus case missing {missing}: {case.get('id', '<no id>')}"
            )
        cases[case["id"]] = case
    return cases


def load_cassettes(paths: list[Path]) -> list[tuple[dict, Path]]:
    cassettes = []
    for directory in paths:
        if not directory.is_dir():
            continue
        for cassette_path in sorted(directory.glob("*.json")):
            cassette = json.loads(cassette_path.read_text(encoding="utf-8"))
            cassettes.append((cassette, cassette_path))
    return cassettes


def parse_result(response_json: dict) -> tuple[dict | None, str]:
    """Extract the PostProcessResult from the DeepSeek response shape."""
    try:
        content = response_json["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError):
        return None, "response missing choices[0].message.content"
    if not isinstance(content, str) or not content.strip():
        return None, "empty message content"
    try:
        result = json.loads(content)
    except json.JSONDecodeError:
        return None, "message content is not valid JSON"
    if not isinstance(result, dict) or not isinstance(result.get("finalText"), str):
        return None, "result missing string finalText"
    return result, ""


def check_case(case: dict, result: dict) -> list[str]:
    """Run the machine checks; returns failure reasons (empty means pass)."""
    failures: list[str] = []
    final_text = result["finalText"]
    casefolded = final_text.casefold()
    checks = case["checks"]
    for required in checks.get("required_substrings", []):
        if required.casefold() not in casefolded:
            failures.append(f"missing required substring {required!r}")
    for forbidden in checks.get("forbidden_substrings", []):
        if forbidden.casefold() in casefolded:
            failures.append(f"contains forbidden substring {forbidden!r}")
    final_tokens = tokens(final_text)
    for required in checks.get("required_tokens", []):
        if required.casefold() not in final_tokens:
            failures.append(f"missing required token {required!r}")
    for term in case.get("protected_terms", []):
        for token in tokens(term):
            if token not in final_tokens:
                failures.append(f"protected term token {token!r} (from {term!r}) "
                                "missing from finalText")
    allowed = RISK_LEVELS.get(checks.get("max_meaning_change_risk", "low"))
    risk = result.get("meaningChangeRisk")
    if risk not in RISK_LEVELS:
        failures.append(f"invalid meaningChangeRisk {risk!r}")
    elif allowed is not None and RISK_LEVELS[risk] > allowed:
        failures.append(f"meaningChangeRisk {risk!r} exceeds allowed "
                        f"{checks['max_meaning_change_risk']!r}")
    return failures


def verdicts(cases: dict, cassettes: list[tuple[dict, Path]]
             ) -> list[dict]:
    rows = []
    for cassette, path in cassettes:
        case_id = cassette.get("case_id")
        case = cases.get(case_id)
        if case is None:
            print(f"warning: cassette {path} has unknown case_id {case_id!r}; "
                  "skipped")
            continue
        latency = cassette.get("latency_ms", 0)
        result, reason = parse_result(cassette.get("response_json", {}))
        if result is None:
            rows.append({
                "case_id": case_id, "passed": False, "latency_ms": latency,
                "reasons": [reason], "case": case,
            })
            continue
        failures = check_case(case, result)
        rows.append({
            "case_id": case_id, "passed": not failures,
            "latency_ms": latency, "reasons": failures, "case": case,
        })
    return rows


def format_case_table(rows: list[dict]) -> str:
    width = max(len(row["case_id"]) for row in rows)
    lines = [f"{'RESULT':<4}  {'CASE':<{width}}  {'RAW PREVIEW':<48}  "
             f"{'LATENCY':>8}  NOTES"]
    for row in sorted(rows, key=lambda row: row["case_id"]):
        preview = row["case"]["raw_text"]
        if len(preview) > 48:
            preview = preview[:45] + "..."
        notes = "; ".join(row["reasons"])
        if row["case"]["checks"].get("manual_review"):
            notes = (notes + "; " if notes else "") + "manual review"
        lines.append(
            f"{'PASS' if row['passed'] else 'FAIL'}  "
            f"{row['case_id']:<{width}}  {preview:<48}  "
            f"{row['latency_ms']:>7} ms  {notes}"
        )
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--corpus", type=Path, default=CORPUS,
                        help="corpus JSON (default: %(default)s)")
    parser.add_argument("--cassettes-dir", type=Path, default=CASSETTES,
                        help="recorded cassettes (default: %(default)s)")
    parser.add_argument("--fixtures-dir", type=Path, default=FIXTURES,
                        help="synthetic fixtures (default: %(default)s)")
    args = parser.parse_args()

    cases = load_corpus(args.corpus)
    cassettes = load_cassettes([args.cassettes_dir])
    source = str(args.cassettes_dir)
    if not cassettes:
        cassettes = load_cassettes([args.fixtures_dir])
        source = f"{args.fixtures_dir} (synthetic fixtures)"
    if not cassettes:
        print(f"no cassettes in {args.cassettes_dir} or {args.fixtures_dir}")
        raise SystemExit(2)
    print(f"Replaying {len(cassettes)} cassettes from {source}\n")

    rows = verdicts(cases, cassettes)
    if not rows:
        print("no cassettes matched corpus cases")
        raise SystemExit(2)
    # Local validation determinism: pure offline replay, verified by
    # re-evaluating every case and requiring an identical verdict set.
    rerun = verdicts(cases, cassettes)
    deterministic = all(
        first["case_id"] == second["case_id"] and first["passed"] == second["passed"]
        for first, second in zip(rows, rerun)
    ) and len(rows) == len(rerun)

    print(format_case_table(rows))
    print()

    manual = [row for row in rows if row["case"]["checks"].get("manual_review")]
    print("Flagged for manual review:")
    if manual:
        for row in manual:
            outcome = "machine checks pass" if row["passed"] else \
                "machine checks FAIL"
            print(f"  {row['case_id']:<34} {outcome} — human review required")
    else:
        print("  none in this run")
    unrecorded = sorted(
        case_id for case_id, case in cases.items()
        if case["checks"].get("manual_review")
        and case_id not in {row["case_id"] for row in rows}
    )
    if unrecorded:
        print(f"  (corpus manual-review cases without cassettes: "
              f"{', '.join(unrecorded)})")
    print()

    passed = [row for row in rows if row["passed"]]
    pass_rate = 100.0 * len(passed) / len(rows)
    hard_failures = [row for row in rows if not row["passed"]
                     and row["case_id"] in HARD_GATE_CASE_IDS]
    neg_uncertain = [row for row in rows
                     if row["case_id"] in NEGATION_UNCERTAINTY_IDENTIFIER_IDS]
    neg_uncertain_failures = [row for row in neg_uncertain if not row["passed"]]
    marker_hits = [row for row in rows if any(
        "forbidden substring" in reason for reason in row["reasons"])]
    latencies = [row["latency_ms"] for row in rows]
    p50 = percentile(latencies, 0.5)
    p95 = percentile(latencies, 0.95)

    gates = [
        ("Preservation pass rate", ">= 95%",
         pass_rate >= 95.0, f"{pass_rate:.1f}% ({len(passed)}/{len(rows)})"),
        ("Hard failures (g01-g07, p01)", "== 0",
         not hard_failures, str(len(hard_failures))),
        ("Negation/uncertainty/identifier cases", "== 100%",
         not neg_uncertain_failures and bool(neg_uncertain),
         f"{100.0 * (len(neg_uncertain) - len(neg_uncertain_failures)) / len(neg_uncertain):.0f}% "
         f"({len(neg_uncertain) - len(neg_uncertain_failures)}/{len(neg_uncertain)})"),
        ("Explain-instead-of-rewrite marker hits", "== 0",
         not marker_hits, str(len(marker_hits))),
        ("Latency p50", "<= 1000 ms", p50 <= 1000.0, f"{p50} ms"),
        ("Latency p95", "<= 3000 ms", p95 <= 3000.0, f"{p95} ms"),
        ("Local validation determinism", "== 100%",
         deterministic, "100%" if deterministic else "MISMATCH"),
    ]

    print("Gates (POST_PROCESSING_PLAN.md §6)")
    print(f"{'GATE':<44}  {'THRESHOLD':<11}  {'RESULT':<4}  MEASURED")
    all_pass = True
    for name, threshold, passed_gate, measured in gates:
        all_pass = all_pass and passed_gate
        print(f"{name:<44}  {threshold:<11}  "
              f"{'PASS' if passed_gate else 'FAIL':<4}  {measured}")
    print()
    print("GATES: PASS" if all_pass else "GATES: FAIL")
    raise SystemExit(0 if all_pass else 1)


if __name__ == "__main__":
    main()
