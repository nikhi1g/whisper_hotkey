#!/usr/bin/env python3
"""Frozen, privacy-preserving benchmark scoring.

The scoring input is intentionally richer than the output.  ``reference``
and ``hypothesis`` are accepted only while a benchmark is running; the
returned artifact contains utterance IDs and numeric error counts, never the
audio or either text string.
"""

from __future__ import annotations

import math
from collections import Counter
from typing import Any, Iterable, Mapping, Sequence

from .edit_distance import EditCounts, align, edit_counts
from .normalization import (
    PUNCTUATION,
    boundary_positions,
    capitalization_labels,
    display_units,
    display_words,
    NORMALIZATION_VERSION,
    normalize_text,
    normalized_characters,
    normalization_sha256,
    punctuation_by_word,
)


def _number(value: Any, default: float | None = None) -> float | None:
    if value is None:
        return default
    try:
        converted = float(value)
    except (TypeError, ValueError):
        return default
    if not math.isfinite(converted):
        return default
    return converted


def _rate(errors: int, units: int) -> float | None:
    return errors / units if units else None


def _f1(true_positive: int, false_positive: int, false_negative: int) -> float:
    denominator = 2 * true_positive + false_positive + false_negative
    return 2 * true_positive / denominator if denominator else 1.0


def _percentile(values: Sequence[float], fraction: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    position = (len(ordered) - 1) * fraction
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    weight = position - lower
    return ordered[lower] * (1 - weight) + ordered[upper] * weight


def _counts_dict(counts: EditCounts, units: int) -> dict[str, int | float | None]:
    return {
        "referenceUnits": units,
        "substitutions": counts.substitutions,
        "deletions": counts.deletions,
        "insertions": counts.insertions,
        "errors": counts.errors,
        "rate": _rate(counts.errors, units),
    }


def punctuation_metrics(reference: str, hypothesis: str) -> dict[str, Any]:
    """Score punctuation by mark and return macro/micro F1."""

    reference_events = Counter(punctuation_by_word(reference))
    hypothesis_events = Counter(punctuation_by_word(hypothesis))
    by_mark: dict[str, dict[str, int | float]] = {}
    total_tp = total_fp = total_fn = 0
    observed_marks = set(mark for _, mark in reference_events | hypothesis_events)
    for mark in sorted(observed_marks or PUNCTUATION):
        reference_count = sum(count for (index, value), count in reference_events.items() if value == mark)
        hypothesis_count = sum(count for (index, value), count in hypothesis_events.items() if value == mark)
        true_positive = sum(
            min(count, hypothesis_events.get((index, mark), 0))
            for (index, value), count in reference_events.items()
            if value == mark
        )
        false_positive = hypothesis_count - true_positive
        false_negative = reference_count - true_positive
        total_tp += true_positive
        total_fp += false_positive
        total_fn += false_negative
        by_mark[mark] = {
            "reference": reference_count,
            "hypothesis": hypothesis_count,
            "truePositive": true_positive,
            "falsePositive": false_positive,
            "falseNegative": false_negative,
            "f1": _f1(true_positive, false_positive, false_negative),
        }
    macro = (
        sum(float(values["f1"]) for values in by_mark.values()) / len(by_mark)
        if by_mark
        else 1.0
    )
    return {
        "byMark": by_mark,
        "macroF1": macro,
        "microF1": _f1(total_tp, total_fp, total_fn),
        "referenceCount": sum(reference_events.values()),
        "hypothesisCount": sum(hypothesis_events.values()),
    }


def boundary_metrics(reference: str, hypothesis: str) -> dict[str, int | float]:
    reference_positions = Counter(boundary_positions(reference))
    hypothesis_positions = Counter(boundary_positions(hypothesis))
    true_positive = sum(
        min(count, hypothesis_positions.get(position, 0))
        for position, count in reference_positions.items()
    )
    false_positive = sum(hypothesis_positions.values()) - true_positive
    false_negative = sum(reference_positions.values()) - true_positive
    return {
        "referenceCount": sum(reference_positions.values()),
        "hypothesisCount": sum(hypothesis_positions.values()),
        "truePositive": true_positive,
        "falsePositive": false_positive,
        "falseNegative": false_negative,
        "f1": _f1(true_positive, false_positive, false_negative),
    }


def capitalization_metrics(reference: str, hypothesis: str) -> dict[str, int | float]:
    reference_words = normalize_text(reference)
    hypothesis_words = normalize_text(hypothesis)
    reference_display = display_words(reference)
    hypothesis_display = display_words(hypothesis)
    steps = align(reference_words, hypothesis_words)
    reference_index = hypothesis_index = 0
    comparable = errors = 0
    proper_noun_total = proper_noun_correct = 0
    reference_labels = capitalization_labels(reference)
    hypothesis_labels = capitalization_labels(hypothesis)
    for step in steps:
        if step.reference is not None:
            current_reference_index = reference_index
            reference_index += 1
        else:
            current_reference_index = -1
        if step.hypothesis is not None:
            current_hypothesis_index = hypothesis_index
            hypothesis_index += 1
        else:
            current_hypothesis_index = -1
        if step.operation == "equal":
            comparable += 1
            if (
                current_reference_index < len(reference_labels)
                and current_hypothesis_index < len(hypothesis_labels)
                and reference_labels[current_reference_index] != hypothesis_labels[current_hypothesis_index]
            ):
                errors += 1
    # A proper noun is approximated conservatively as a reference word whose
    # first character is uppercase but that is not the first word of a
    # sentence.  Explicit metadata can replace this slice in score_rows.
    for index, token in enumerate(reference_display):
        if index > 0 and token[:1].isupper():
            proper_noun_total += 1
            if index < len(hypothesis_display) and hypothesis_display[index] == token:
                proper_noun_correct += 1
    return {
        "errors": errors,
        "words": comparable,
        "errorRate": _rate(errors, comparable),
        "properNounTotal": proper_noun_total,
        "properNounCorrect": proper_noun_correct,
    }


def score_pair(reference: str, hypothesis: str) -> dict[str, Any]:
    """Return detailed numeric metrics for one ephemeral text pair."""

    normalized_reference = normalize_text(reference)
    normalized_hypothesis = normalize_text(hypothesis)
    display_reference = display_units(reference)
    display_hypothesis = display_units(hypothesis)
    characters_reference = normalized_characters(reference)
    characters_hypothesis = normalized_characters(hypothesis)
    normalized_counts = edit_counts(normalized_reference, normalized_hypothesis)
    display_counts = edit_counts(display_reference, display_hypothesis)
    character_counts = edit_counts(characters_reference, characters_hypothesis)
    return {
        "normalized": _counts_dict(normalized_counts, len(normalized_reference)),
        "display": _counts_dict(display_counts, len(display_reference)),
        "cer": _counts_dict(character_counts, len(characters_reference)),
        "punctuation": punctuation_metrics(reference, hypothesis),
        "boundary": boundary_metrics(reference, hypothesis),
        "capitalization": capitalization_metrics(reference, hypothesis),
        "normalizedReference": normalized_reference,
        "normalizedHypothesis": normalized_hypothesis,
    }


def _metadata(row: Mapping[str, Any]) -> Mapping[str, Any]:
    value = row.get("metadata", {})
    return value if isinstance(value, Mapping) else {}


def _row_value(row: Mapping[str, Any], *names: str) -> Any:
    metadata = _metadata(row)
    for name in names:
        if name in row:
            return row[name]
        if name in metadata:
            return metadata[name]
    return None


def _category_cases(row: Mapping[str, Any], *names: str) -> list[Any]:
    value = _row_value(row, *names)
    if value is None:
        return []
    if isinstance(value, (str, bytes)):
        return [value]
    if isinstance(value, Sequence):
        return list(value)
    return [value]


def _category_accuracy(
    row: Mapping[str, Any],
    reference_words: Sequence[str],
    hypothesis_words: Sequence[str],
    *names: str,
) -> tuple[int, int]:
    """Count exact category cases from optional ephemeral annotations."""

    cases = _category_cases(row, *names)
    if not cases:
        return 0, 0
    correct = 0
    for case in cases:
        if isinstance(case, Mapping):
            expected = case.get("reference", case.get("expected", case.get("value", "")))
            observed = case.get("hypothesis")
            expected_words = normalize_text(str(expected))
            if observed is not None:
                observed_words = normalize_text(str(observed))
                correct += int(expected_words == observed_words)
            else:
                correct += int(bool(expected_words) and _contains_sequence(hypothesis_words, expected_words))
        else:
            expected_words = normalize_text(str(case))
            correct += int(bool(expected_words) and _contains_sequence(hypothesis_words, expected_words))
    return correct, len(cases)


def _contains_sequence(values: Sequence[str], target: Sequence[str]) -> bool:
    if not target or len(target) > len(values):
        return False
    return any(list(values[offset : offset + len(target)]) == list(target) for offset in range(len(values) - len(target) + 1))


def _confidence_examples(rows: Sequence[Mapping[str, Any]]) -> list[tuple[float, bool]]:
    examples: list[tuple[float, bool]] = []
    for row in rows:
        raw_confidence = _row_value(row, "wordConfidence", "confidence", "confidences")
        if not isinstance(raw_confidence, Sequence) or isinstance(raw_confidence, (str, bytes)):
            continue
        reference = normalize_text(str(row.get("reference", "")))
        hypothesis = normalize_text(str(row.get("hypothesis", row.get("text", ""))))
        raw_correct = _row_value(row, "wordCorrect", "correctWords", "wordErrors")
        correctness: list[bool] | None = None
        if isinstance(raw_correct, Sequence) and not isinstance(raw_correct, (str, bytes)):
            values = list(raw_correct)
            if values and all(isinstance(item, bool) for item in values):
                correctness = values
            elif values:
                # ``wordErrors`` is accepted as an explicit error label.
                correctness = [not bool(item) for item in values]
        if correctness is None:
            alignment = align(reference, hypothesis)
            correctness = [step.operation == "equal" for step in alignment if step.hypothesis is not None]
        for confidence, correct in zip(raw_confidence, correctness):
            value = _number(confidence)
            if value is None:
                continue
            examples.append((min(1.0, max(0.0, value)), bool(correct)))
    return examples


def _average_precision(scores: Sequence[tuple[float, bool]]) -> float | None:
    positives = sum(not correct for _, correct in scores)
    if not positives:
        return None
    ordered = sorted(scores, key=lambda item: item[0], reverse=True)
    true_positives = 0
    previous_recall = 0.0
    area = 0.0
    for rank, (_, correct) in enumerate(ordered, 1):
        if not correct:
            true_positives += 1
            recall = true_positives / positives
            area += (recall - previous_recall) * (true_positives / rank)
            previous_recall = recall
    return area


def confidence_metrics(rows: Sequence[Mapping[str, Any]]) -> dict[str, float | int | None]:
    examples = _confidence_examples(rows)
    if not examples:
        return {
            "incorrectWordAuprc": None,
            "ece": None,
            "mce": None,
            "nce": None,
            "errorRecallAtVerifierBudget": None,
            "wordCount": 0,
        }
    bins: list[list[tuple[float, bool]]] = [[] for _ in range(10)]
    for confidence, correct in examples:
        bins[min(9, int(confidence * 10))].append((confidence, correct))
    ece = 0.0
    mce = 0.0
    for bucket in bins:
        if not bucket:
            continue
        mean_confidence = sum(item[0] for item in bucket) / len(bucket)
        mean_accuracy = sum(item[1] for item in bucket) / len(bucket)
        gap = abs(mean_confidence - mean_accuracy)
        ece += gap * len(bucket) / len(examples)
        mce = max(mce, gap)
    entropy = sum(
        -(int(correct) * math.log(max(confidence, 1e-12)) + (1 - int(correct)) * math.log(max(1 - confidence, 1e-12)))
        for confidence, correct in examples
    ) / len(examples)
    baseline = sum(not correct for _, correct in examples) / len(examples)
    baseline_entropy = 0.0
    if 0 < baseline < 1:
        baseline_entropy = -(baseline * math.log(baseline) + (1 - baseline) * math.log(1 - baseline))
    nce = 1.0 - entropy / baseline_entropy if baseline_entropy else None
    ordered = sorted(examples, key=lambda item: 1.0 - item[0], reverse=True)
    total_errors = sum(not correct for _, correct in ordered)
    budget_fraction = 0.1
    budget = max(1, math.ceil(len(ordered) * budget_fraction))
    recalled = sum(not correct for _, correct in ordered[:budget])
    return {
        "incorrectWordAuprc": _average_precision(examples),
        "ece": ece,
        "mce": mce,
        "nce": nce,
        "errorRecallAtVerifierBudget": recalled / total_errors if total_errors else None,
        "wordCount": len(examples),
    }


def _aggregate_repair_metrics(rows: Sequence[Mapping[str, Any]]) -> dict[str, float | int | None]:
    attempts = correct = changed = false_rewrites = high_confidence_corruption = 0
    invoked = 0
    verifier_audio_ms = 0.0
    audio_ms = 0.0
    for row in rows:
        applied = bool(_row_value(row, "repairApplied", "repairAttempted"))
        attempts += int(applied)
        correct += int(bool(_row_value(row, "repairCorrect"))) if applied else 0
        changed_value = _row_value(row, "repairChangedWords", "lexicalMutationCount")
        changed += int(_number(changed_value, 0.0) or 0.0)
        false_rewrites += int(bool(_row_value(row, "falseRewrite", "repairIncorrect")))
        high_confidence_corruption += int(bool(_row_value(row, "highConfidenceCorruption")))
        invoked += int(bool(_row_value(row, "verifierInvoked")))
        verifier_audio_ms += _number(_row_value(row, "verifierAudioMs"), 0.0) or 0.0
        audio_ms += _number(_row_value(row, "audioDurationMs"), 0.0) or 0.0
    reference_words = sum(
        len(normalize_text(str(row.get("reference", ""))))
        for row in rows
    )
    return {
        "repairPrecision": correct / attempts if attempts else None,
        "repairRecall": correct / max(1, sum(int(bool(_row_value(row, "repairNeeded"))) for row in rows))
        if any(bool(_row_value(row, "repairNeeded")) for row in rows)
        else None,
        "falseRewriteRate": false_rewrites / attempts if attempts else None,
        "highConfidenceCorruptionRate": high_confidence_corruption / max(1, reference_words),
        "lexicalMutationCount": changed,
        "verifierAudioRatio": verifier_audio_ms / audio_ms if audio_ms else None,
        "verifierInvocationRate": invoked / len(rows) if rows else None,
    }


def score_rows(
    rows: Iterable[Mapping[str, Any]],
    *,
    run_id: str = "benchmark-run",
    commit: str = "unknown",
    hardware: Mapping[str, Any] | None = None,
    configuration: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    """Score ephemeral input rows and return a schema-ready result artifact."""

    materialized = list(rows)
    if not materialized:
        raise ValueError("at least one benchmark row is required")
    items: list[dict[str, Any]] = []
    normalized_totals = Counter()
    display_totals = Counter()
    character_totals = Counter()
    punctuation_totals: Counter[str] = Counter()
    boundary_totals = Counter()
    category_totals: dict[str, list[int]] = {
        "entity": [0, 0],
        "numberUnit": [0, 0],
        "homophone": [0, 0],
    }
    latency_values: list[float] = []
    audio_values: list[float] = []
    rss_values: list[float] = []
    first_result_values: list[float] = []
    stable_sentence_values: list[float] = []
    cpu_values: list[float] = []
    gpu_values: list[float] = []
    ane_values: list[float] = []
    repetition_count = hallucination_count = false_period_count = 0
    cancellation_count = cancellation_failure_count = 0
    rapid_restart_count = rapid_restart_failure_count = 0
    thermal_states: list[str] = []

    for row in materialized:
        if "id" not in row:
            raise ValueError("each benchmark row requires an id")
        if "reference" not in row:
            raise ValueError(f"benchmark row {row['id']} requires reference text")
        hypothesis = str(row.get("hypothesis", row.get("text", "")))
        reference = str(row["reference"])
        pair = score_pair(reference, hypothesis)
        normalized = pair["normalized"]
        display = pair["display"]
        cer = pair["cer"]
        for target, source in (
            (normalized_totals, normalized),
            (display_totals, display),
            (character_totals, cer),
        ):
            target["referenceUnits"] += int(source["referenceUnits"] or 0)
            target["substitutions"] += int(source["substitutions"])
            target["deletions"] += int(source["deletions"])
            target["insertions"] += int(source["insertions"])
            target["errors"] += int(source["errors"])
        for mark, values in pair["punctuation"]["byMark"].items():
            punctuation_totals[f"{mark}:reference"] += int(values["reference"])
            punctuation_totals[f"{mark}:hypothesis"] += int(values["hypothesis"])
            punctuation_totals[f"{mark}:tp"] += int(values["truePositive"])
            punctuation_totals[f"{mark}:fp"] += int(values["falsePositive"])
            punctuation_totals[f"{mark}:fn"] += int(values["falseNegative"])
        boundary_totals["reference"] += int(pair["boundary"]["referenceCount"])
        boundary_totals["hypothesis"] += int(pair["boundary"]["hypothesisCount"])
        boundary_totals["tp"] += int(pair["boundary"]["truePositive"])
        boundary_totals["fp"] += int(pair["boundary"]["falsePositive"])
        boundary_totals["fn"] += int(pair["boundary"]["falseNegative"])
        reference_words = normalize_text(reference)
        hypothesis_words = normalize_text(hypothesis)
        for category, names in {
            "entity": ("entities", "namedEntities", "properNouns"),
            "numberUnit": ("numberUnits", "numbers", "units"),
            "homophone": ("homophones",),
        }.items():
            correct, total = _category_accuracy(row, reference_words, hypothesis_words, *names)
            category_totals[category][0] += correct
            category_totals[category][1] += total
        latency = _number(_row_value(row, "latencyMs", "latency_ms"), 0.0) or 0.0
        audio_duration = _number(_row_value(row, "audioDurationMs", "audio_duration_ms"), 0.0) or 0.0
        rss = _number(_row_value(row, "peakRSSMiB", "peak_rss_mib"))
        for target, names in (
            (first_result_values, ("timeToFirstResultMs", "firstResultMs")),
            (stable_sentence_values, ("timeToStableSentenceMs", "stableSentenceMs")),
            (cpu_values, ("cpuUtilizationPct", "cpuPercent")),
            (gpu_values, ("gpuUtilizationPct", "gpuPercent")),
            (ane_values, ("aneUtilizationPct", "anePercent")),
        ):
            value = _number(_row_value(row, *names))
            if value is not None:
                target.append(value)
        repetition_count += int(bool(_row_value(row, "repetition", "repetitionDetected")))
        hallucination_count += int(bool(_row_value(row, "hallucination", "hallucinationDetected")))
        false_period_count += int(bool(_row_value(row, "falsePeriod", "falsePeriodAfterThinkingPause")))
        cancelled = bool(_row_value(row, "cancelled", "canceled"))
        cancellation_count += int(cancelled)
        cancellation_failure_count += int(cancelled and bool(_row_value(row, "cancellationFailed")))
        rapid_restart = bool(_row_value(row, "rapidRestart", "rapidRestartAttempted"))
        rapid_restart_count += int(rapid_restart)
        rapid_restart_failure_count += int(rapid_restart and bool(_row_value(row, "rapidRestartFailed")))
        thermal_state = _row_value(row, "energyThermalState", "thermalState")
        if thermal_state is not None:
            thermal_states.append(str(thermal_state))
        latency_values.append(latency)
        if audio_duration:
            audio_values.append(audio_duration)
        if rss is not None:
            rss_values.append(rss)
        items.append(
            {
                "id": str(row["id"]),
                "subset": str(_row_value(row, "subset", "track") or "unspecified"),
                "referenceWordCount": int(normalized["referenceUnits"] or 0),
                "normalizedSubstitutions": int(normalized["substitutions"]),
                "normalizedDeletions": int(normalized["deletions"]),
                "normalizedInsertions": int(normalized["insertions"]),
                "normalizedWordErrors": int(normalized["errors"]),
                "displayUnitCount": int(display["referenceUnits"] or 0),
                "displayErrors": int(display["errors"]),
                "charUnitCount": int(cer["referenceUnits"] or 0),
                "charErrors": int(cer["errors"]),
                "latencyMs": latency,
                "audioDurationMs": audio_duration,
                **({"peakRSSMiB": rss} if rss is not None else {}),
            }
        )

    punctuation_by_mark: dict[str, dict[str, int | float]] = {}
    for mark in sorted({key.split(":", 1)[0] for key in punctuation_totals}):
        tp = punctuation_totals[f"{mark}:tp"]
        fp = punctuation_totals[f"{mark}:fp"]
        fn = punctuation_totals[f"{mark}:fn"]
        punctuation_by_mark[mark] = {
            "reference": punctuation_totals[f"{mark}:reference"],
            "hypothesis": punctuation_totals[f"{mark}:hypothesis"],
            "truePositive": tp,
            "falsePositive": fp,
            "falseNegative": fn,
            "f1": _f1(tp, fp, fn),
        }
    punctuation_f1 = (
        sum(float(values["f1"]) for values in punctuation_by_mark.values()) / len(punctuation_by_mark)
        if punctuation_by_mark
        else 1.0
    )
    boundary_f1 = _f1(boundary_totals["tp"], boundary_totals["fp"], boundary_totals["fn"])
    confidence = confidence_metrics(materialized)
    repair = _aggregate_repair_metrics(materialized)
    normalized_wer = _rate(normalized_totals["errors"], normalized_totals["referenceUnits"])
    display_wer = _rate(display_totals["errors"], display_totals["referenceUnits"])
    cer_rate = _rate(character_totals["errors"], character_totals["referenceUnits"])
    summary: dict[str, Any] = {
        "normalizedWER": normalized_wer,
        "displayWER": display_wer,
        "wer": normalized_wer,
        "cer": cer_rate,
        "entityAccuracy": _rate(category_totals["entity"][0], category_totals["entity"][1]),
        "numberUnitAccuracy": _rate(category_totals["numberUnit"][0], category_totals["numberUnit"][1]),
        "homophoneExactMatch": _rate(category_totals["homophone"][0], category_totals["homophone"][1]),
        "punctuationF1": punctuation_f1,
        "punctuationMacroF1": punctuation_f1,
        "punctuationMicroF1": _f1(
            sum(int(values["truePositive"]) for values in punctuation_by_mark.values()),
            sum(int(values["falsePositive"]) for values in punctuation_by_mark.values()),
            sum(int(values["falseNegative"]) for values in punctuation_by_mark.values()),
        ),
        "boundaryF1": boundary_f1,
        "sentenceBoundaryF1": boundary_f1,
        "falsePeriodRate": (false_period_count or boundary_totals["fp"]) / max(1, boundary_totals["reference"]) if boundary_totals["reference"] or false_period_count or boundary_totals["fp"] else None,
        "capitalizationErrorRate": _rate(
            sum(int(score_pair(str(row["reference"]), str(row.get("hypothesis", row.get("text", ""))))["capitalization"]["errors"]) for row in materialized),
            sum(int(score_pair(str(row["reference"]), str(row.get("hypothesis", row.get("text", ""))))["capitalization"]["words"]) for row in materialized),
        ),
        "properNounAccuracy": _rate(category_totals["entity"][0], category_totals["entity"][1]),
        "numberErrorRate": 1.0 - _rate(category_totals["numberUnit"][0], category_totals["numberUnit"][1]) if category_totals["numberUnit"][1] else None,
        "numberDateUnitAccuracy": _rate(category_totals["numberUnit"][0], category_totals["numberUnit"][1]),
        "incorrectWordAuprc": confidence["incorrectWordAuprc"],
        "confidenceAuprc": confidence["incorrectWordAuprc"],
        "ece": confidence["ece"],
        "mce": confidence["mce"],
        "nce": confidence["nce"],
        "errorRecallAtVerifierBudget": confidence["errorRecallAtVerifierBudget"],
        **repair,
        "latencyP50Ms": _percentile(latency_values, 0.50),
        "latencyP95Ms": _percentile(latency_values, 0.95),
        "latencyP99Ms": _percentile(latency_values, 0.99),
        "realTimeFactor": sum(latency_values) / sum(audio_values) if audio_values else None,
        "peakRSSMiB": max(rss_values) if rss_values else None,
        "timeToFirstResultMs": _percentile(first_result_values, 0.50),
        "timeToStableSentenceMs": _percentile(stable_sentence_values, 0.50),
        "cpuUtilizationPct": sum(cpu_values) / len(cpu_values) if cpu_values else None,
        "gpuUtilizationPct": sum(gpu_values) / len(gpu_values) if gpu_values else None,
        "aneUtilizationPct": sum(ane_values) / len(ane_values) if ane_values else None,
        "energyThermalState": thermal_states[-1] if thermal_states else None,
        "cancellationFailureRate": cancellation_failure_count / cancellation_count if cancellation_count else None,
        "rapidRestartFailureRate": rapid_restart_failure_count / rapid_restart_count if rapid_restart_count else None,
        "hallucinationRate": hallucination_count / len(materialized) if materialized else None,
        "repetitionRate": repetition_count / len(materialized) if materialized else None,
        "hallucinationRepetitionRate": (hallucination_count + repetition_count) / (2 * len(materialized)) if materialized else None,
        "utteranceCount": len(materialized),
    }
    # Keep the output free of input text while retaining category and
    # punctuation aggregates needed for reproducibility.
    return {
        "schemaVersion": 1,
        "runID": str(run_id),
        "commit": str(commit),
        "hardware": dict(hardware or {}),
        "configuration": dict(configuration or {}),
        "normalization": {
            "version": NORMALIZATION_VERSION,
            "sha256": normalization_sha256(),
        },
        "summary": summary,
        "slices": {
            "punctuation": {"byMark": punctuation_by_mark},
            "boundary": {
                "reference": boundary_totals["reference"],
                "hypothesis": boundary_totals["hypothesis"],
                "truePositive": boundary_totals["tp"],
                "falsePositive": boundary_totals["fp"],
                "falseNegative": boundary_totals["fn"],
            },
            "confidenceWordCount": confidence["wordCount"],
        },
        "items": items,
    }
