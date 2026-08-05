Version 3.3.0 adds Parakeet, a recognition engine that is both more accurate
and several times faster than every whisper option the app already shipped, and
reorganizes the Recognition settings so they describe what is actually running.

## Highlights

- Add Parakeet, running NVIDIA Parakeet on the Neural Engine through FluidAudio
  instead of whisper. Measured on this repository's own LibriSpeech benchmark
  (100 utterances across test-clean and test-other, Apple M5 Pro, warm model),
  it wins on both axes at once rather than trading one for the other.
- Reorganize the Recognition section. Engine now comes first, because it
  decides which models exist and whether Decoding applies. The Model row swaps
  to whichever family the engine belongs to, and the Decoding row is hidden on
  engines that have no beam search rather than greyed out while still painting
  a selected profile.
- Keep Parakeet's model choice separate from whisper's, so switching engines
  never overwrites the other engine's selection.

## Measured

| Engine | Word error rate | Mean latency | Speed |
| --- | ---: | ---: | ---: |
| Large-v3 Turbo Q5 + Metal, Precision | 4.32% | 321 ms | 21.5x realtime |
| Large-v3 Turbo Q5 + Metal, Smart Decode | 4.04% | 305 ms | 22.7x realtime |
| Parakeet Fast | 3.88% | 34 ms | 206x realtime |
| Parakeet Accurate | 2.62% | 56 ms | 123x realtime |

Parakeet Fast is a 110M model and still more accurate than every whisper model
in the app. Reproduce these numbers with the harness in `Benchmarks/Parakeet/`,
which scores with the same word error math as the whisper benchmark.

## Two things Parakeet does not do

- **No decoding profiles.** It is a transducer, so there is no beam search for
  Precision or Smart Decode to select. The row is hidden on that engine.
- **No prompt.** The internal dictionary and the Pause Mode context tail cannot
  bias a Parakeet decode. Both still apply on every whisper engine, which is
  one reason all of them remain available and unchanged.

Parakeet checkpoints download on first use into Application Support, so the
first dictation after selecting the engine waits on a 219 MB or 443 MB fetch.

The app is signed with a stable Apple Development identity and is not
notarized, so the first launch still needs one approval through System
Settings > Privacy & Security > Open Anyway. Audio and transcripts remain
local, and every bundled and downloaded whisper model is verified against a
pinned SHA-256.
