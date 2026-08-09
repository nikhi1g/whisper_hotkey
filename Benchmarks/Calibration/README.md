# Confidence calibration benchmark

This directory contains a bounded, synthetic calibration fixture and a
stdlib-only artifact generator. It exercises the W05 temperature, Platt, and
isotonic baselines independently for each engine/model/decoding profile key.

Only rows marked `partition: calibration` fit parameters. Rows marked `test`
are evaluated after fitting and cannot tune a model. The generated artifact
reports PR-AUC, Brier score, ECE, MCE, NCE, error recall at a verifier budget,
and false-unlock rate when an explicit operating point is supplied.

The fixture contains numeric evidence and labels only. It has no audio,
transcript, token text, persistent corpus, or network dependency. The operating
point is deliberately `uncalibrated` because this fixture does not justify a
shipping verifier threshold.

```sh
python3 Benchmarks/Calibration/calibrate.py \
  --input Benchmarks/Calibration/synthetic_labeled.jsonl \
  --output /tmp/whisper-hotkey-confidence.json
python3 Benchmarks/Calibration/check_artifact.py
python3 -m unittest Benchmarks/Calibration/test_calibration.py
```
