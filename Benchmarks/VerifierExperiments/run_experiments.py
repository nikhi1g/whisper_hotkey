#!/usr/bin/env python3
"""Run bounded, offline verifier experiments without retaining speech content.

The local recognition runners remain responsible for invoking an engine.  This
module consumes only an aggregate-safe measurement exchange: opaque case
digests, aligned word positions, error-position sets, guard decisions, and
numeric resource observations.  It never opens an audio file and it rejects
transcript-bearing input before any summary is written.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import platform
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence


SCHEMA_VERSION = 1
MEASUREMENT_SCHEMA = "whisper_hotkey_verifier_measurements_v1"
RESULT_SCHEMA = "whisper_hotkey_verifier_result_v1"
CONFIG_PATH = Path(__file__).with_name("experiment_config.json")
RESULT_SCHEMA_PATH = Path(__file__).with_name("verifier-result-v1.schema.json")

SAFE_CASE_ID = re.compile(r"^sha256:[0-9a-f]{64}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
THERMAL_STATES = frozenset({"nominal", "fair", "serious", "critical", "unknown"})

# The deny-list is deliberately broader than the currently accepted schema.
# A future schema extension must explicitly opt in to a content-free field.
FORBIDDEN_CONTENT_KEYS = frozenset(
    {
        "audio",
        "audio_data",
        "audio_file",
        "audio_path",
        "audio_url",
        "audiofile",
        "hypothesis",
        "hypothesis_text",
        "prompt",
        "prompt_text",
        "reference",
        "reference_text",
        "references",
        "segment",
        "segments",
        "text",
        "transcript",
        "transcript_text",
        "transcription",
        "token",
        "tokens",
        "utterance",
        "utterance_text",
        "wav",
        "wav_data",
        "wav_path",
        "waveform",
        "word",
        "words",
    }
)

MEASUREMENT_KEYS = frozenset(
    {
        "schema",
        "schemaVersion",
        "candidateId",
        "provenance",
        "accuracy",
        "items",
    }
)
ACCURACY_KEYS = frozenset(
    {
        "applicationPrimaryWer",
        "applicationCandidateWer",
        "pairedImprovementSupported",
        "publicRegressionPassed",
        "protectedRegressionCount",
    }
)
ITEM_KEYS = frozenset(
    {
        "caseIdHash",
        "referenceWordCount",
        "primaryErrorPositions",
        "verifierErrorPositions",
        "edits",
        "audioDurationMs",
        "verifierSpanDurationsMs",
        "latencyMs",
        "coldLoadMs",
        "warmLoadMs",
        "peakRssMiB",
        "cpuPercent",
        "metalPercent",
        "anePercent",
        "thermalState",
    }
)
EDIT_KEYS = frozenset(
    {
        "position",
        "accepted",
        "locked",
        "anchorsPreserved",
        "numbersPreserved",
        "alignmentValid",
        "generationCurrent",
    }
)


class VerifierExperimentError(ValueError):
    """Raised when an experiment cannot be made reproducible or content-safe."""


def _normal_key(key: object) -> str:
    rendered = re.sub(r"(?<!^)(?=[A-Z])", "_", str(key))
    rendered = re.sub(r"[^A-Za-z0-9]+", "_", rendered)
    return rendered.casefold().strip("_")


def reject_content_keys(value: object) -> None:
    """Fail closed on content-bearing keys, including nested future fields."""

    if isinstance(value, Mapping):
        for key, child in value.items():
            if _normal_key(key) in FORBIDDEN_CONTENT_KEYS:
                raise VerifierExperimentError(
                    "measurement contains transcript or audio content"
                )
            reject_content_keys(child)
    elif isinstance(value, list):
        for child in value:
            reject_content_keys(child)


def _require_mapping(value: object, field: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise VerifierExperimentError(f"{field} must be an object")
    return value


def _finite_number(
    value: object,
    field: str,
    *,
    minimum: float = 0.0,
    maximum: float | None = None,
) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise VerifierExperimentError(f"{field} must be numeric")
    number = float(value)
    if not math.isfinite(number) or number < minimum:
        raise VerifierExperimentError(f"{field} is outside its finite bound")
    if maximum is not None and number > maximum:
        raise VerifierExperimentError(f"{field} is outside its finite bound")
    return number


def _integer(value: object, field: str, *, minimum: int = 0) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
        raise VerifierExperimentError(f"{field} must be an integer in range")
    return value


def _boolean(value: object, field: str) -> bool:
    if not isinstance(value, bool):
        raise VerifierExperimentError(f"{field} must be boolean")
    return value


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        raise VerifierExperimentError("unable to hash local provenance file") from error
    return digest.hexdigest()


def load_config() -> dict[str, Any]:
    try:
        payload = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise VerifierExperimentError("experiment configuration is not valid JSON") from error
    if not isinstance(payload, dict) or payload.get("schema_version") != 1:
        raise VerifierExperimentError("unsupported experiment configuration")
    return payload


def _config_candidate(config: Mapping[str, Any], candidate_id: str) -> Mapping[str, Any]:
    candidates = config.get("candidates")
    if not isinstance(candidates, list):
        raise VerifierExperimentError("experiment configuration has no candidates")
    for candidate in candidates:
        if isinstance(candidate, Mapping) and candidate.get("id") == candidate_id:
            return candidate
    raise VerifierExperimentError("candidate is not pinned in experiment configuration")


def _check_record(
    check_id: str,
    *,
    required: bool,
    path: Path | None,
    expected_sha256: str | None = None,
    require_pin: bool = True,
    directory: bool = False,
    presence_only: bool = False,
) -> dict[str, Any]:
    """Return a content-free local artifact check."""

    record: dict[str, Any] = {
        "id": check_id,
        "required": required,
        "status": "missing",
        "sha256": None,
        "expectedSha256": expected_sha256,
    }
    if path is None:
        return record
    if presence_only:
        if path.exists():
            record["status"] = "present"
        return record
    if directory:
        if not path.is_dir():
            return record
        try:
            files = [entry for entry in path.rglob("*.wav") if entry.is_file()]
        except OSError:
            record["status"] = "unreadable"
            return record
        if not files:
            return record
        if any((entry.stat().st_mode & 0o077) != 0 for entry in files):
            record["status"] = "not_private"
            record["fileCount"] = len(files)
            return record
        record["status"] = "present"
        record["fileCount"] = len(files)
        return record
    if not path.is_file():
        return record
    observed = _sha256_file(path)
    record["sha256"] = observed
    if expected_sha256:
        record["status"] = (
            "present_verified" if observed == expected_sha256 else "checksum_mismatch"
        )
    elif require_pin:
        record["status"] = "present_unpinned"
    else:
        record["status"] = "present"
    return record


def _ready(record: Mapping[str, Any]) -> bool:
    status = record.get("status")
    return status in {"present_verified", "present"}


def _blockers(checks: Iterable[Mapping[str, Any]]) -> list[str]:
    return [
        f"{check['id']}:{check['status']}"
        for check in checks
        if bool(check.get("required")) and not _ready(check)
    ]


def _default_path(repo_root: Path, relative: str | None) -> Path | None:
    return repo_root / relative if relative else None


def preflight(
    repo_root: Path,
    *,
    primary_model: Path | None = None,
    helper: Path | None = None,
    candidate_artifacts: Mapping[str, Path] | None = None,
    smoke_manifest: Path | None = None,
    smoke_audio_root: Path | None = None,
    application_manifest: Path | None = None,
    application_audio_root: Path | None = None,
    public_manifest: Path | None = None,
    public_audio_root: Path | None = None,
) -> dict[str, Any]:
    """Check local prerequisites without downloading or opening audio."""

    config = load_config()
    primary = _require_mapping(config["primary"], "primary")
    corpora = {
        str(entry["id"]): entry
        for entry in config.get("corpora", [])
        if isinstance(entry, Mapping) and entry.get("id")
    }
    checks: list[dict[str, Any]] = []
    checks.append(
        _check_record(
            "primary:model",
            required=True,
            path=primary_model,
            expected_sha256=str(primary["model_sha256"]),
        )
    )
    checks.append(
        _check_record(
            "primary:helper",
            required=True,
            path=helper,
            require_pin=False,
        )
    )

    smoke = corpora.get("librispeech_test100_local", {})
    default_smoke_manifest = _default_path(repo_root, smoke.get("manifest_path"))
    checks.append(
        _check_record(
            "corpus:librispeech_test100:manifest",
            required=True,
            path=smoke_manifest or default_smoke_manifest,
            expected_sha256=smoke.get("manifest_sha256"),
        )
    )
    checks.append(
        _check_record(
            "corpus:librispeech_test100:audio",
            required=True,
            path=smoke_audio_root,
            directory=True,
        )
    )

    checks.append(
        _check_record(
            "corpus:application_consent_frozen:manifest",
            required=True,
            path=application_manifest,
            require_pin=True,
        )
    )
    checks.append(
        _check_record(
            "corpus:application_consent_frozen:audio",
            required=True,
            path=application_audio_root,
            directory=True,
        )
    )

    public = corpora.get("public_recovery_tracks", {})
    checks.append(
        _check_record(
            "corpus:public_recovery_tracks:manifest",
            required=True,
            path=public_manifest,
            require_pin=True,
        )
    )
    checks.append(
        _check_record(
            "corpus:public_recovery_tracks:audio",
            required=True,
            path=public_audio_root,
            directory=True,
        )
    )

    overrides = candidate_artifacts or {}
    for raw_candidate in config.get("candidates", []):
        if not isinstance(raw_candidate, Mapping):
            continue
        candidate_id = str(raw_candidate["id"])
        required = bool(raw_candidate.get("required_for_promotion"))
        artifact = overrides.get(candidate_id)
        checks.append(
            _check_record(
                f"candidate:{candidate_id}:artifact",
                required=required,
                path=artifact,
                expected_sha256=raw_candidate.get("artifact_sha256"),
                require_pin=True,
            )
        )
        runtime = str(raw_candidate.get("runtime"))
        if runtime == "parakeet_cpp":
            checks.append(
                _check_record(
                    f"candidate:{candidate_id}:runtime",
                    required=required,
                    path=repo_root / "Benchmarks" / "ParakeetCpp",
                    require_pin=True,
                    presence_only=True,
                )
            )
        elif runtime == "qwen_asr":
            checks.append(
                _check_record(
                    f"candidate:{candidate_id}:runtime",
                    required=False,
                    path=repo_root / "Benchmarks" / "QwenASR",
                    require_pin=True,
                    presence_only=True,
                )
            )

    blockers = _blockers(checks)
    return {
        "schemaVersion": SCHEMA_VERSION,
        "recordType": "preflight",
        "status": "ready" if not blockers else "blocked",
        "checks": checks,
        "blockers": blockers,
    }


def _positions(value: object, field: str, *, reference_words: int, maximum: int) -> set[int]:
    if not isinstance(value, list) or len(value) > maximum:
        raise VerifierExperimentError(f"{field} must be a bounded integer array")
    result: set[int] = set()
    for raw in value:
        position = _integer(raw, field)
        if position >= reference_words:
            raise VerifierExperimentError(f"{field} contains an out-of-range position")
        if position in result:
            raise VerifierExperimentError(f"{field} contains a duplicate position")
        result.add(position)
    return result


def _validate_measurement_item(
    raw_item: object,
    *,
    bounds: Mapping[str, Any],
) -> dict[str, Any]:
    item = _require_mapping(raw_item, "measurement item")
    unknown = set(item) - ITEM_KEYS
    if unknown:
        raise VerifierExperimentError("measurement item contains an unsupported field")
    case_id = item.get("caseIdHash")
    if not isinstance(case_id, str) or not SAFE_CASE_ID.fullmatch(case_id):
        raise VerifierExperimentError("caseIdHash must be a SHA-256 digest")
    reference_words = _integer(item.get("referenceWordCount"), "referenceWordCount", minimum=1)
    if reference_words > int(bounds["max_reference_words_per_item"]):
        raise VerifierExperimentError("referenceWordCount exceeds the experiment bound")
    primary_errors = _positions(
        item.get("primaryErrorPositions"),
        "primaryErrorPositions",
        reference_words=reference_words,
        maximum=int(bounds["max_positions_per_set"]),
    )
    verifier_errors = _positions(
        item.get("verifierErrorPositions"),
        "verifierErrorPositions",
        reference_words=reference_words,
        maximum=int(bounds["max_positions_per_set"]),
    )
    raw_edits = item.get("edits", [])
    if not isinstance(raw_edits, list) or len(raw_edits) > int(bounds["max_edits_per_item"]):
        raise VerifierExperimentError("edits exceeds the experiment bound")
    edits: list[dict[str, Any]] = []
    edit_positions: set[int] = set()
    for raw_edit in raw_edits:
        edit = _require_mapping(raw_edit, "edit")
        if set(edit) != EDIT_KEYS:
            raise VerifierExperimentError("edit has an unsupported or missing field")
        position = _integer(edit["position"], "edit.position")
        if position >= reference_words or position in edit_positions:
            raise VerifierExperimentError("edit position is out of range or duplicated")
        edit_positions.add(position)
        edits.append(
            {
                "position": position,
                "accepted": _boolean(edit["accepted"], "edit.accepted"),
                "locked": _boolean(edit["locked"], "edit.locked"),
                "anchorsPreserved": _boolean(
                    edit["anchorsPreserved"], "edit.anchorsPreserved"
                ),
                "numbersPreserved": _boolean(
                    edit["numbersPreserved"], "edit.numbersPreserved"
                ),
                "alignmentValid": _boolean(
                    edit["alignmentValid"], "edit.alignmentValid"
                ),
                "generationCurrent": _boolean(
                    edit["generationCurrent"], "edit.generationCurrent"
                ),
            }
        )

    audio_ms = _finite_number(
        item.get("audioDurationMs"),
        "audioDurationMs",
        minimum=0.001,
        maximum=float(bounds["max_case_audio_duration_ms"]),
    )
    raw_spans = item.get("verifierSpanDurationsMs", [])
    if not isinstance(raw_spans, list) or len(raw_spans) > int(bounds["max_spans_per_item"]):
        raise VerifierExperimentError("verifierSpanDurationsMs exceeds its bound")
    spans = [
        _finite_number(
            raw_span,
            "verifierSpanDurationsMs",
            minimum=0.0,
            maximum=float(bounds["max_span_duration_ms"]),
        )
        for raw_span in raw_spans
    ]
    if sum(spans) > audio_ms * float(bounds["max_verifier_audio_ratio"]):
        raise VerifierExperimentError("verifier audio ratio exceeds its bound")
    latency_ms = _finite_number(item.get("latencyMs"), "latencyMs")

    normalized: dict[str, Any] = {
        "caseIdHash": case_id,
        "referenceWordCount": reference_words,
        "primaryErrorPositions": primary_errors,
        "verifierErrorPositions": verifier_errors,
        "edits": edits,
        "audioDurationMs": audio_ms,
        "verifierSpanDurationsMs": spans,
        "latencyMs": latency_ms,
    }
    for key in ("coldLoadMs", "warmLoadMs", "peakRssMiB"):
        if key in item:
            normalized[key] = _finite_number(item[key], key)
        else:
            normalized[key] = None
    for key in ("cpuPercent", "metalPercent", "anePercent"):
        if key in item:
            normalized[key] = _finite_number(item[key], key, maximum=100.0)
        else:
            normalized[key] = None
    if "thermalState" in item:
        thermal_state = item["thermalState"]
        if thermal_state not in THERMAL_STATES:
            raise VerifierExperimentError("thermalState is not a known content-free state")
        normalized["thermalState"] = thermal_state
    else:
        normalized["thermalState"] = None
    return normalized


def validate_measurements(payload: object, config: Mapping[str, Any] | None = None) -> dict[str, Any]:
    """Validate an aggregate-safe measurement exchange and normalize it."""

    reject_content_keys(payload)
    measurement = _require_mapping(payload, "measurements")
    unknown = set(measurement) - MEASUREMENT_KEYS
    if unknown:
        raise VerifierExperimentError("measurements contain an unsupported field")
    if measurement.get("schema") != MEASUREMENT_SCHEMA:
        raise VerifierExperimentError("unsupported measurement schema")
    if measurement.get("schemaVersion") != SCHEMA_VERSION:
        raise VerifierExperimentError("unsupported measurement schema version")
    candidate_id = measurement.get("candidateId")
    if not isinstance(candidate_id, str):
        raise VerifierExperimentError("candidateId must be a string")
    selected_config = config or load_config()
    _config_candidate(selected_config, candidate_id)
    provenance = _require_mapping(measurement.get("provenance", {}), "provenance")
    for field in ("runtimeVersion", "runtimeCommit", "modelSha256", "corpusManifestSha256"):
        if field not in provenance:
            raise VerifierExperimentError(f"provenance is missing {field}")
    for field in ("modelSha256", "corpusManifestSha256"):
        value = provenance[field]
        if not isinstance(value, str) or not SHA256.fullmatch(value):
            raise VerifierExperimentError(f"provenance {field} is not a SHA-256 digest")
    accuracy = measurement.get("accuracy")
    normalized_accuracy: dict[str, Any] | None = None
    if accuracy is not None:
        accuracy_record = _require_mapping(accuracy, "accuracy")
        if set(accuracy_record) != ACCURACY_KEYS:
            raise VerifierExperimentError("accuracy has an unsupported or missing field")
        normalized_accuracy = {
            "applicationPrimaryWer": _finite_number(
                accuracy_record["applicationPrimaryWer"],
                "accuracy.applicationPrimaryWer",
                maximum=1.0,
            ),
            "applicationCandidateWer": _finite_number(
                accuracy_record["applicationCandidateWer"],
                "accuracy.applicationCandidateWer",
                maximum=1.0,
            ),
            "pairedImprovementSupported": _boolean(
                accuracy_record["pairedImprovementSupported"],
                "accuracy.pairedImprovementSupported",
            ),
            "publicRegressionPassed": _boolean(
                accuracy_record["publicRegressionPassed"],
                "accuracy.publicRegressionPassed",
            ),
            "protectedRegressionCount": _integer(
                accuracy_record["protectedRegressionCount"],
                "accuracy.protectedRegressionCount",
            ),
        }
    items = measurement.get("items")
    bounds = _require_mapping(selected_config.get("bounds"), "bounds")
    if not isinstance(items, list) or not items or len(items) > int(bounds["max_items"]):
        raise VerifierExperimentError("items exceeds the experiment bound")
    normalized_items = [
        _validate_measurement_item(item, bounds=bounds) for item in items
    ]
    case_ids = [str(item["caseIdHash"]) for item in normalized_items]
    if len(set(case_ids)) != len(case_ids):
        raise VerifierExperimentError("caseIdHash values must be unique")
    if sum(len(item["verifierSpanDurationsMs"]) for item in normalized_items) > int(
        bounds["max_total_spans"]
    ):
        raise VerifierExperimentError("total verifier spans exceed the experiment bound")
    return {
        "schema": MEASUREMENT_SCHEMA,
        "schemaVersion": SCHEMA_VERSION,
        "candidateId": candidate_id,
        "provenance": dict(provenance),
        "accuracy": normalized_accuracy,
        "items": normalized_items,
    }


def _rate(numerator: int | float, denominator: int | float) -> float | None:
    return None if denominator == 0 else numerator / denominator


def _percentile(values: Sequence[float], fraction: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    index = round((len(ordered) - 1) * fraction)
    return ordered[index]


def aggregate_metrics(measurements: Mapping[str, Any]) -> dict[str, Any]:
    """Compute deterministic, content-free verifier metrics."""

    items = measurements.get("items")
    if not isinstance(items, list):
        raise VerifierExperimentError("validated measurements have no items")
    primary_errors = 0
    verifier_errors = 0
    intersection = 0
    union = 0
    corrected_oracle = 0
    accepted = 0
    corrected_guarded = 0
    introduced = 0
    unsafe_accepts = 0
    high_confidence_corruptions = 0
    reference_words = 0
    completion: list[float] = []
    cold_load: list[float] = []
    warm_load: list[float] = []
    rss: list[float] = []
    audio_ms = 0.0
    span_ms = 0.0
    span_count = 0
    max_span: float | None = None
    cpu: list[float] = []
    metal: list[float] = []
    ane: list[float] = []
    thermal_states: set[str] = set()

    for item in items:
        primary = set(item["primaryErrorPositions"])
        verifier = set(item["verifierErrorPositions"])
        primary_errors += len(primary)
        verifier_errors += len(verifier)
        intersection += len(primary & verifier)
        union += len(primary | verifier)
        corrected_oracle += len(primary - verifier)
        reference_words += int(item["referenceWordCount"])
        completion.append(float(item["latencyMs"]))
        if item["coldLoadMs"] is not None:
            cold_load.append(float(item["coldLoadMs"]))
        if item["warmLoadMs"] is not None:
            warm_load.append(float(item["warmLoadMs"]))
        if item["peakRssMiB"] is not None:
            rss.append(float(item["peakRssMiB"]))
        audio_ms += float(item["audioDurationMs"])
        spans = [float(value) for value in item["verifierSpanDurationsMs"]]
        span_ms += sum(spans)
        span_count += len(spans)
        if spans:
            item_max = max(spans)
            max_span = item_max if max_span is None else max(max_span, item_max)
        for key, values in (("cpuPercent", cpu), ("metalPercent", metal), ("anePercent", ane)):
            if item[key] is not None:
                values.append(float(item[key]))
        if item["thermalState"] is not None:
            thermal_states.add(str(item["thermalState"]))

        for edit in item["edits"]:
            if not edit["accepted"]:
                continue
            accepted += 1
            position = int(edit["position"])
            is_corrected = position in primary and position not in verifier
            if is_corrected:
                corrected_guarded += 1
            else:
                introduced += 1
            safe = (
                not edit["locked"]
                and edit["anchorsPreserved"]
                and edit["numbersPreserved"]
                and edit["alignmentValid"]
                and edit["generationCurrent"]
            )
            if not safe:
                unsafe_accepts += 1
            if edit["locked"]:
                high_confidence_corruptions += 1

    contention_samples = max(len(cpu), len(metal), len(ane))
    contention = {
        "status": "measured" if contention_samples else "unmeasured",
        "samples": contention_samples,
        "cpuP95Percent": _percentile(cpu, 0.95),
        "metalP95Percent": _percentile(metal, 0.95),
        "aneP95Percent": _percentile(ane, 0.95),
        "thermalState": (
            next(iter(thermal_states))
            if len(thermal_states) == 1
            else ("mixed" if thermal_states else None)
        ),
    }
    accuracy = measurements.get("accuracy")
    if isinstance(accuracy, Mapping):
        accuracy_result: dict[str, Any] = {
            "status": "measured",
            **dict(accuracy),
        }
    else:
        accuracy_result = {
            "status": "unmeasured",
            "applicationPrimaryWer": None,
            "applicationCandidateWer": None,
            "pairedImprovementSupported": None,
            "publicRegressionPassed": None,
            "protectedRegressionCount": None,
        }
    return {
        "accuracy": accuracy_result,
        "errorOverlap": {
            "items": len(items),
            "primaryErrors": primary_errors,
            "verifierErrors": verifier_errors,
            "intersection": intersection,
            "union": union,
            "jaccard": _rate(intersection, union),
            "primaryOverlapRate": _rate(intersection, primary_errors),
        },
        "oracleRepair": {
            "opportunities": primary_errors,
            "corrected": corrected_oracle,
            "rate": _rate(corrected_oracle, primary_errors),
        },
        "guardedRepair": {
            "accepted": accepted,
            "corrected": corrected_guarded,
            "introduced": introduced,
            "precision": _rate(corrected_guarded, accepted),
            "recall": _rate(corrected_guarded, primary_errors),
            "falseRewriteRate": _rate(introduced, accepted),
            "unsafeAccepts": unsafe_accepts,
            "highConfidenceCorruptions": high_confidence_corruptions,
            "highConfidenceCorruptionRate": _rate(
                high_confidence_corruptions, reference_words
            ),
        },
        "latency": {
            "samples": len(completion),
            "completionP50Ms": _percentile(completion, 0.50),
            "completionP95Ms": _percentile(completion, 0.95),
            "completionP99Ms": _percentile(completion, 0.99),
            "coldLoadP50Ms": _percentile(cold_load, 0.50),
            "warmP50Ms": _percentile(warm_load, 0.50),
            "warmP95Ms": _percentile(warm_load, 0.95),
        },
        "rss": {
            "samples": len(rss),
            "peakRSSMiB": max(rss) if rss else None,
            "meanPeakRSSMiB": sum(rss) / len(rss) if rss else None,
        },
        "spanBudget": {
            "items": len(items),
            "spans": span_count,
            "audioMs": audio_ms,
            "verifierAudioMs": span_ms,
            "coverageRatio": _rate(span_ms, audio_ms) or 0.0,
            "maxSpanMs": max_span,
            "withinBounds": True,
        },
        "contention": contention,
    }


def _git_commit(repo_root: Path) -> str | None:
    try:
        completed = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=str(repo_root),
            capture_output=True,
            check=False,
            text=True,
        )
    except (OSError, ValueError):
        return None
    if completed.returncode != 0:
        return None
    value = completed.stdout.strip()
    return value if re.fullmatch(r"[0-9a-f]{7,64}", value) else None


def _runtime_metadata() -> dict[str, Any]:
    return {
        "python": platform.python_version(),
        "os": platform.system(),
        "architecture": platform.machine(),
    }


def _candidate_provenance(config: Mapping[str, Any], candidate_id: str) -> dict[str, Any]:
    candidate = dict(_config_candidate(config, candidate_id))
    runtime_id = str(candidate.get("runtime"))
    runtimes = config.get("runtimes", {})
    runtime = runtimes.get(runtime_id, {}) if isinstance(runtimes, Mapping) else {}
    candidate["runtime_provenance"] = dict(runtime) if isinstance(runtime, Mapping) else {}
    return candidate


def _promotion_reasons(
    config: Mapping[str, Any],
    preflight_record: Mapping[str, Any],
    candidate_records: Sequence[Mapping[str, Any]],
) -> list[str]:
    reasons = list(preflight_record.get("blockers", []))
    required_ids = {
        str(candidate["id"])
        for candidate in config.get("candidates", [])
        if isinstance(candidate, Mapping) and candidate.get("required_for_promotion")
    }
    for record in candidate_records:
        if str(record.get("candidateId")) in required_ids and record.get("status") != "measured":
            reasons.append(f"candidate:{record['candidateId']}:no_valid_measurement")
        metrics = record.get("metrics")
        if not isinstance(metrics, Mapping):
            continue
        accuracy = metrics.get("accuracy", {})
        primary_wer = accuracy.get("applicationPrimaryWer") if isinstance(accuracy, Mapping) else None
        candidate_wer = accuracy.get("applicationCandidateWer") if isinstance(accuracy, Mapping) else None
        if (
            not isinstance(accuracy, Mapping)
            or accuracy.get("status") != "measured"
            or not accuracy.get("pairedImprovementSupported")
            or not accuracy.get("publicRegressionPassed")
            or not isinstance(primary_wer, (int, float))
            or not isinstance(candidate_wer, (int, float))
            or candidate_wer >= primary_wer
            or accuracy.get("protectedRegressionCount") != 0
        ):
            reasons.append(f"candidate:{record['candidateId']}:accuracy_gate")
        guarded = metrics.get("guardedRepair", {})
        precision = guarded.get("precision") if isinstance(guarded, Mapping) else None
        if precision is None or precision < float(config["promotion_gates"]["repair_precision_floor"]):
            reasons.append(f"candidate:{record['candidateId']}:repair_precision_gate")
        corruption_rate = (
            guarded.get("highConfidenceCorruptionRate")
            if isinstance(guarded, Mapping)
            else None
        )
        if (
            corruption_rate is None
            or corruption_rate
            > float(config["promotion_gates"]["high_confidence_corruption_ceiling"])
        ):
            reasons.append(f"candidate:{record['candidateId']}:high_confidence_corruption_gate")
        latency = metrics.get("latency", {})
        if (
            not isinstance(latency, Mapping)
            or latency.get("completionP95Ms") is None
        ):
            reasons.append(f"candidate:{record['candidateId']}:latency_unmeasured")
        rss = metrics.get("rss", {})
        if not isinstance(rss, Mapping) or rss.get("peakRSSMiB") is None:
            reasons.append(f"candidate:{record['candidateId']}:rss_unmeasured")
    # Keep reasons deterministic while retaining the first occurrence.
    return list(dict.fromkeys(reasons))


def build_report(
    repo_root: Path,
    *,
    primary_model: Path | None = None,
    helper: Path | None = None,
    candidate_artifacts: Mapping[str, Path] | None = None,
    smoke_manifest: Path | None = None,
    smoke_audio_root: Path | None = None,
    application_manifest: Path | None = None,
    application_audio_root: Path | None = None,
    public_manifest: Path | None = None,
    public_audio_root: Path | None = None,
    measurements: Mapping[str, Any] | None = None,
    run_id: str | None = None,
) -> list[dict[str, Any]]:
    config = load_config()
    revision = _git_commit(repo_root)
    preflight_record = preflight(
        repo_root,
        primary_model=primary_model,
        helper=helper,
        candidate_artifacts=candidate_artifacts,
        smoke_manifest=smoke_manifest,
        smoke_audio_root=smoke_audio_root,
        application_manifest=application_manifest,
        application_audio_root=application_audio_root,
        public_manifest=public_manifest,
        public_audio_root=public_audio_root,
    )
    report_id = run_id or f"w06-{revision[:12] if revision else 'offline'}"
    metadata = {
        "schemaVersion": SCHEMA_VERSION,
        "recordType": "metadata",
        "runId": report_id,
        "harness": {
            "schema": RESULT_SCHEMA,
            "version": "1.0.0",
            "configSha256": _sha256_file(CONFIG_PATH),
            "resultSchemaSha256": _sha256_file(RESULT_SCHEMA_PATH),
        },
        "provenance": {
            "sourceRevision": revision,
            "runtime": _runtime_metadata(),
            "runtimes": config.get("runtimes", {}),
            "normalization": config.get("normalization", {}),
            "bounds": config.get("bounds", {}),
        },
        "privacy": {
            "audioPersisted": False,
            "transcriptsPersisted": False,
            "ordinaryUserContent": False,
            "aggregateOnly": True,
        },
    }
    candidate_records: list[dict[str, Any]] = []
    supplied: dict[str, Mapping[str, Any]] = {}
    if measurements is not None:
        validated = validate_measurements(measurements, config)
        supplied[str(validated["candidateId"])] = validated
    for raw_candidate in config.get("candidates", []):
        if not isinstance(raw_candidate, Mapping):
            continue
        candidate_id = str(raw_candidate["id"])
        candidate_checks = [
            check
            for check in preflight_record["checks"]
            if str(check["id"]).startswith(f"candidate:{candidate_id}:")
        ]
        candidate_blockers = _blockers(candidate_checks)
        candidate_measurement = supplied.get(candidate_id)
        if candidate_measurement is not None:
            candidate_status = "measured"
            candidate_metrics = aggregate_metrics(candidate_measurement)
        else:
            candidate_metrics = None
            candidate_status = "blocked" if candidate_blockers else "not_run"
        candidate_records.append(
            {
                "schemaVersion": SCHEMA_VERSION,
                "recordType": "candidate",
                "candidateId": candidate_id,
                "status": candidate_status,
                "provenance": _candidate_provenance(config, candidate_id),
                "metrics": candidate_metrics,
                "blockers": candidate_blockers,
            }
        )
    reasons = _promotion_reasons(config, preflight_record, candidate_records)
    decision = {
        "schemaVersion": SCHEMA_VERSION,
        "recordType": "decision",
        "decision": "no-promotion" if reasons else "eligible-for-review",
        "reasons": reasons,
        "measuredCandidates": [
            record["candidateId"]
            for record in candidate_records
            if record["status"] == "measured"
        ],
    }
    return [metadata, preflight_record, *candidate_records, decision]


def jsonl(records: Sequence[Mapping[str, Any]]) -> str:
    return "".join(
        json.dumps(record, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
        + "\n"
        for record in records
    )


def _write_private_output(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    try:
        path.chmod(0o600)
    except OSError as error:
        raise VerifierExperimentError("unable to protect experiment output") from error


def _load_measurements(path: Path) -> Mapping[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise VerifierExperimentError("measurement input is not valid JSON") from error
    return validate_measurements(payload)


def _candidate_overrides(values: Sequence[str]) -> dict[str, Path]:
    overrides: dict[str, Path] = {}
    for value in values:
        candidate_id, separator, raw_path = value.partition("=")
        if not separator or not candidate_id or not raw_path:
            raise VerifierExperimentError("--candidate-artifact must be candidate=path")
        if candidate_id in overrides:
            raise VerifierExperimentError("candidate artifact was supplied twice")
        overrides[candidate_id] = Path(raw_path).expanduser().resolve()
    return overrides


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Collect bounded verifier evidence without transcript/audio persistence."
    )
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--measurements", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--run-id")
    parser.add_argument("--primary-model", type=Path)
    parser.add_argument("--helper", type=Path)
    parser.add_argument("--candidate-artifact", action="append", default=[])
    parser.add_argument("--smoke-manifest", type=Path)
    parser.add_argument("--smoke-audio-root", type=Path)
    parser.add_argument("--application-manifest", type=Path)
    parser.add_argument("--application-audio-root", type=Path)
    parser.add_argument("--public-manifest", type=Path)
    parser.add_argument("--public-audio-root", type=Path)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    repo_root = args.repo_root.expanduser().resolve()
    overrides = _candidate_overrides(args.candidate_artifact)
    measurements = _load_measurements(args.measurements) if args.measurements else None
    records = build_report(
        repo_root,
        primary_model=args.primary_model.expanduser().resolve() if args.primary_model else None,
        helper=args.helper.expanduser().resolve() if args.helper else None,
        candidate_artifacts=overrides,
        smoke_manifest=args.smoke_manifest.expanduser().resolve() if args.smoke_manifest else None,
        smoke_audio_root=args.smoke_audio_root.expanduser().resolve() if args.smoke_audio_root else None,
        application_manifest=(
            args.application_manifest.expanduser().resolve()
            if args.application_manifest
            else None
        ),
        application_audio_root=(
            args.application_audio_root.expanduser().resolve()
            if args.application_audio_root
            else None
        ),
        public_manifest=args.public_manifest.expanduser().resolve() if args.public_manifest else None,
        public_audio_root=(
            args.public_audio_root.expanduser().resolve() if args.public_audio_root else None
        ),
        measurements=measurements,
        run_id=args.run_id,
    )
    rendered = jsonl(records)
    if args.output:
        _write_private_output(args.output.expanduser().resolve(), rendered)
    else:
        sys.stdout.write(rendered)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except VerifierExperimentError as error:
        print(f"verifier experiment error: {error}", file=sys.stderr)
        raise SystemExit(2)
