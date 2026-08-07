# BenchmarkSuite

This folder is the tracked home for benchmark **assets** and reproducible
benchmarks metadata.  

It exists to solve two problems:

- keep dataset manifests, metadata, and run case lists under version control, and  
- keep raw corpus/audio files in the existing `.gitignore`ed locations.

Current benchmark corpora and scripts remain in the local `Benchmarks/` tree, but
the source-of-truth metadata is now:

- `Benchmarks/BenchmarkSuite/datasets/catalog.json` — curated benchmark dataset
  catalog
- `Benchmarks/BenchmarkSuite/datasets/merged/librispeech-100/` — the
  reproducible LibriSpeech 100-utterance selection used by this repo’s existing
  harness
- `Benchmarks/BenchmarkSuite/tests/` — tests for asset integrity

## What changed

The previously used `Benchmarks/Data/` and `Benchmarks/Results/` directories are
still used for large, local files and generated benchmark payloads, but they are
ignored by git. This folder mirrors the stable metadata so another machine can
recreate the same test set and validate it quickly.

## Newly included benchmark datasets to benchmark against

`catalog.json` now includes additional English ASR suites (and one punctuation
benchmark companion resource) that you can use for broader coverage:

- LibriSpeech PC (`SLR145`) — punctuation/capitalization companion manifests
- LibriTTS (`SLR60`) — broader read-speech coverage
- AMI Corpus (`SLR16`) — meeting speech and noise/acoustics
- TEDLIUM (`SLR7`/`SLR19`/`SLR51`) — long-form lecture speech
- Common Voice (`Mozilla`) — conversational/general speech

`catalog.json` stores the download URLs, licensing, and recommended splits.

## Syncing and validating assets

1. Merge current repository results/manifests into the suite:

```sh
python3 Benchmarks/BenchmarkSuite/scripts/sync_assets.py
```

2. Validate the asset set:

```sh
python3 Benchmarks/BenchmarkSuite/tests/run_suite_asset_checks.py
```

## Notes

- This is intentionally not a duplicate of the full corpus; only metadata and
  lightweight manifests are tracked to keep the repo practical.
- Raw `.wav` files are still expected in `Benchmarks/Data/WAV/...` and will not be
  committed.
