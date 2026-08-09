#!/usr/bin/env python3
"""Deterministic, privacy-safe confidence calibration benchmark.

The input is a synthetic or consented stream of numeric word-level evidence.
It is intentionally rejected if it contains audio, transcript, or token text.
Only rows in the explicit ``calibration`` partition fit a model.  Validation
and test rows are evaluation-only and never select parameters or thresholds.
"""

from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence


SCHEMA = "whisper_hotkey_confidence_calibration_v1"
FORBIDDEN_KEYS = frozenset(
    {
        "audio",
        "audio_data",
        "audio_file",
        "audio_path",
        "hypothesis",
        "prompt",
        "reference",
        "samples",
        "segment",
        "segments",
        "text",
        "token",
        "tokens",
        "transcript",
        "transcript_text",
        "transcription",
        "utterance",
        "wav",
        "waveform",
        "word",
        "words",
    }
)
REQUIRED_FIELDS = frozenset(
    {
        "id",
        "partition",
        "engine",
        "model",
        "profile",
        "raw_error_probability",
        "is_error",
    }
)
MAX_ROWS = 4096
MAX_KEYS = 32


class CalibrationError(ValueError):
    pass


def _normal_key(value: object) -> str:
    rendered = re.sub(r"(?<!^)(?=[A-Z])", "_", str(value))
    rendered = re.sub(r"[^A-Za-z0-9]+", "_", rendered)
    return rendered.casefold().strip("_")


def reject_content(value: object) -> None:
    if isinstance(value, Mapping):
        for key, child in value.items():
            if _normal_key(key) in FORBIDDEN_KEYS:
                raise CalibrationError("content-bearing calibration field")
            reject_content(child)
    elif isinstance(value, list):
        for child in value:
            reject_content(child)


def _finite_probability(value: object, field: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise CalibrationError(f"{field} must be numeric")
    value = float(value)
    if not math.isfinite(value) or not 0 <= value <= 1:
        raise CalibrationError(f"{field} is outside [0, 1]")
    return value


def load_rows(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as error:
        raise CalibrationError("unable to read calibration input") from error
    for line_number, line in enumerate(lines, start=1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as error:
            raise CalibrationError(f"invalid JSON on line {line_number}") from error
        if not isinstance(row, dict):
            raise CalibrationError("each calibration row must be an object")
        reject_content(row)
        missing = REQUIRED_FIELDS.difference(row)
        if missing:
            raise CalibrationError(f"missing fields: {sorted(missing)}")
        if row["partition"] not in {"calibration", "validation", "test"}:
            raise CalibrationError("unknown calibration partition")
        if not isinstance(row["id"], str) or not row["id"]:
            raise CalibrationError("row id must be non-empty")
        if not all(isinstance(row[field], str) and row[field] for field in ("engine", "model", "profile")):
            raise CalibrationError("calibration key fields must be non-empty strings")
        row = dict(row)
        row["raw_error_probability"] = _finite_probability(
            row["raw_error_probability"], "raw_error_probability"
        )
        if not isinstance(row["is_error"], bool):
            raise CalibrationError("is_error must be boolean")
        rows.append(row)
        if len(rows) > MAX_ROWS:
            raise CalibrationError("calibration input exceeds bounded row limit")
    if not rows:
        raise CalibrationError("calibration input is empty")
    return rows


def _key(row: Mapping[str, Any]) -> tuple[str, str, str]:
    return str(row["engine"]), str(row["model"]), str(row["profile"])


def _logit(probability: float) -> float:
    probability = min(max(probability, 1e-7), 1 - 1e-7)
    return math.log(probability / (1 - probability))


def _sigmoid(value: float) -> float:
    if value >= 0:
        z = math.exp(-value)
        return 1 / (1 + z)
    z = math.exp(value)
    return z / (1 + z)


def fit_temperature(rows: Sequence[Mapping[str, Any]]) -> dict[str, float]:
    scores = [float(row["raw_error_probability"]) for row in rows]
    labels = [1.0 if row["is_error"] else 0.0 for row in rows]

    def loss(temperature: float) -> float:
        total = 0.0
        for score, label in zip(scores, labels):
            value = _logit(score) / temperature
            total += max(value, 0) - value * label + math.log1p(math.exp(-abs(value)))
        return total / max(len(scores), 1)

    low = math.log(0.05)
    high = math.log(20.0)
    for _ in range(80):
        first = low + (high - low) / 3
        second = high - (high - low) / 3
        if loss(math.exp(first)) <= loss(math.exp(second)):
            high = second
        else:
            low = first
    return {"temperature": math.exp((low + high) / 2)}


def fit_platt(rows: Sequence[Mapping[str, Any]]) -> dict[str, float]:
    scores = [_logit(float(row["raw_error_probability"])) for row in rows]
    labels = [1.0 if row["is_error"] else 0.0 for row in rows]
    regularization = 0.001
    slope = 1.0
    intercept = 0.0
    for _ in range(100):
        gradient_slope = regularization * slope
        gradient_intercept = regularization * intercept
        hessian_ss = regularization
        hessian_si = 0.0
        hessian_ii = regularization
        for score, label in zip(scores, labels):
            probability = _sigmoid(slope * score + intercept)
            residual = probability - label
            curvature = max(probability * (1 - probability), 1e-9)
            gradient_slope += residual * score
            gradient_intercept += residual
            hessian_ss += curvature * score * score
            hessian_si += curvature * score
            hessian_ii += curvature
        determinant = hessian_ss * hessian_ii - hessian_si * hessian_si
        if not math.isfinite(determinant) or abs(determinant) <= 1e-12:
            break
        delta_slope = (hessian_ii * gradient_slope - hessian_si * gradient_intercept) / determinant
        delta_intercept = (-hessian_si * gradient_slope + hessian_ss * gradient_intercept) / determinant
        slope -= delta_slope
        intercept -= delta_intercept
        if max(abs(delta_slope), abs(delta_intercept)) < 1e-10:
            break
    return {"slope": slope, "intercept": intercept}


def fit_isotonic(rows: Sequence[Mapping[str, Any]]) -> list[dict[str, float]]:
    blocks: list[dict[str, float]] = []
    for row in sorted(enumerate(rows), key=lambda item: (float(item[1]["raw_error_probability"]), item[0])):
        score = float(row[1]["raw_error_probability"])
        blocks.append(
            {
                "minimum": score,
                "maximum": score,
                "positive": 1.0 if row[1]["is_error"] else 0.0,
                "count": 1.0,
            }
        )
        while len(blocks) > 1:
            left = blocks[-2]
            right = blocks[-1]
            left_mean = left["positive"] / left["count"]
            right_mean = right["positive"] / right["count"]
            if left_mean <= right_mean:
                break
            blocks[-2:] = [
                {
                    "minimum": min(left["minimum"], right["minimum"]),
                    "maximum": max(left["maximum"], right["maximum"]),
                    "positive": left["positive"] + right["positive"],
                    "count": left["count"] + right["count"],
                }
            ]
    return [
        {
            "maximum_raw_error_probability": block["maximum"],
            "calibrated_error_probability": block["positive"] / block["count"],
        }
        for block in blocks
    ]


def predict(raw: float, method: str, parameters: Mapping[str, Any]) -> float:
    if method == "temperature":
        return _sigmoid(_logit(raw) / float(parameters["temperature"]))
    if method == "platt":
        return _sigmoid(float(parameters["slope"]) * _logit(raw) + float(parameters["intercept"]))
    points = parameters["points"]
    for point in points:
        if raw <= float(point["maximum_raw_error_probability"]):
            return float(point["calibrated_error_probability"])
    return float(points[-1]["calibrated_error_probability"])


def _average_precision(scores: Sequence[tuple[float, bool]]) -> float | None:
    positive_count = sum(label for _, label in scores)
    if not positive_count:
        return None
    ordered = sorted(enumerate(scores), key=lambda item: (-item[1][0], item[0]))
    true_positive = false_positive = 0
    previous_recall = 0.0
    area = 0.0
    index = 0
    while index < len(ordered):
        score = ordered[index][1][0]
        end = index
        while end < len(ordered) and ordered[end][1][0] == score:
            end += 1
        for _, (_, label) in ordered[index:end]:
            true_positive += int(label)
            false_positive += int(not label)
        recall = true_positive / positive_count
        precision = true_positive / (true_positive + false_positive)
        area += (recall - previous_recall) * precision
        previous_recall = recall
        index = end
    return area


def metric_summary(
    rows: Sequence[Mapping[str, Any]],
    probabilities: Sequence[float],
    *,
    false_unlock_threshold: float | None = None,
) -> dict[str, Any]:
    labels = [bool(row["is_error"]) for row in rows]
    count = len(rows)
    errors = sum(labels)
    brier = sum((probability - int(label)) ** 2 for probability, label in zip(probabilities, labels)) / count
    buckets: list[list[float | int]] = [[0, 0.0, 0.0] for _ in range(10)]
    for probability, label in zip(probabilities, labels):
        index = min(int(probability * 10), 9)
        buckets[index][0] += 1
        buckets[index][1] += probability
        buckets[index][2] += int(label)
    ece = 0.0
    mce = 0.0
    for bucket_count, bucket_probability, bucket_label in buckets:
        if not bucket_count:
            continue
        gap = abs(bucket_probability / bucket_count - bucket_label / bucket_count)
        ece += bucket_count / count * gap
        mce = max(mce, gap)
    prevalence = errors / count
    nll = sum(
        -(int(label) * math.log(min(max(probability, 1e-7), 1 - 1e-7))
          + int(not label) * math.log(1 - min(max(probability, 1e-7), 1 - 1e-7)))
        for probability, label in zip(probabilities, labels)
    ) / count
    baseline_entropy = 0.0 if prevalence in (0, 1) else -prevalence * math.log(prevalence) - (1 - prevalence) * math.log(1 - prevalence)
    ordered = sorted(zip(probabilities, labels), key=lambda item: -item[0])
    selected = max(1, math.ceil(count * 0.25))
    recall_at_25 = sum(label for _, label in ordered[:selected]) / errors if errors else None
    unlocked = [label for probability, label in zip(probabilities, labels) if false_unlock_threshold is not None and probability <= false_unlock_threshold]
    return {
        "sampleCount": count,
        "errorCount": errors,
        "brier": brier,
        "auprc": _average_precision(list(zip(probabilities, labels))),
        "ece": ece,
        "mce": mce,
        "nce": nll / baseline_entropy if baseline_entropy else None,
        "errorRecallAtVerifierBudget25Pct": recall_at_25,
        "falseUnlockRate": (sum(unlocked) / len(unlocked)) if unlocked else None,
    }


def build_artifact(rows: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    groups: list[dict[str, Any]] = []
    keys = sorted({_key(row) for row in rows})
    if len(keys) > MAX_KEYS:
        raise CalibrationError("calibration input exceeds bounded key limit")
    for engine, model, profile in keys:
        calibration = [row for row in rows if _key(row) == (engine, model, profile) and row["partition"] == "calibration"]
        held_out = [row for row in rows if _key(row) == (engine, model, profile) and row["partition"] in {"validation", "test"}]
        if not calibration:
            raise CalibrationError(f"no calibration rows for {engine}/{model}/{profile}")
        if not any(row["is_error"] for row in calibration) or all(row["is_error"] for row in calibration):
            raise CalibrationError(f"calibration rows need both labels for {engine}/{model}/{profile}")
        fitted: dict[str, dict[str, Any]] = {
            "temperature": {**fit_temperature(calibration)},
            "platt": {**fit_platt(calibration)},
            "isotonic": {"points": fit_isotonic(calibration)},
        }
        methods: dict[str, Any] = {}
        for method, parameters in fitted.items():
            if held_out:
                probabilities = [predict(float(row["raw_error_probability"]), method, parameters) for row in held_out]
                metrics = metric_summary(held_out, probabilities)
            else:
                metrics = None
            methods[method] = {"parameters": parameters, "heldOutMetrics": metrics}
        groups.append(
            {
                "engine": engine,
                "model": model,
                "profile": profile,
                "calibrationExampleCount": len(calibration),
                "heldOutExampleCount": len(held_out),
                "methods": methods,
                "operatingPoint": {
                    "status": "uncalibrated",
                    "errorThreshold": None,
                    "reason": "No verifier-budget fixture justifies a shipping threshold.",
                },
            }
        )
    return {
        "schema": SCHEMA,
        "artifactVersion": "w05-synthetic-v1",
        "groups": groups,
        "privacy": {
            "containsAudio": False,
            "containsTranscript": False,
            "containsPersistentCorpus": False,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    artifact = build_artifact(load_rows(args.input))
    args.output.write_text(json.dumps(artifact, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
