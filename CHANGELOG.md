# Changelog

## 3.5.0: 2026-08-06

Two New Engines release. Both are additions; nothing existing changed.

- Added **Parakeet Unified** as a third Parakeet model. On the repository's
  100-utterance benchmark it beats the shipping engine on every accuracy figure
  and on mean and median latency: 2.46% word error rate against 2.62%, and
  41 ms median against 53 ms. Its one regression is tail latency on audio past
  15 seconds, which it transcribes with overlapping windows. Downloaded on
  demand at 594 MB
- Added **Cohere Transcribe** as a fifth engine, Apache-2.0 and the
  highest-ranked permissively licensed model with an Apple Silicon path.
  Measured on the same set it ties Parakeet overall (2.57% against 2.62%),
  wins on clean speech, loses on noisy speech, and costs eleven times the
  latency at 629 ms. Offered in Advanced only, downloaded on demand at 2.4 GB,
  with the tradeoff stated before the download rather than after
- Left every existing engine, model, preset, and decoding profile untouched.
  Fast and Accurate resolve exactly as they did, and no saved selection changes
- Extended the benchmark harness to measure all three, so leaderboard claims
  can be checked against this corpus rather than taken on trust

## 3.4.2: 2026-08-06

Release plumbing. No change to how the app behaves.

- Populated the Parakeet cache before the release build. Bundling the
  checkpoints in 3.4.1 broke the release workflow in a way hidden behind the
  missing signing secrets: `build_app.py` copies them out of FluidAudio's cache,
  and a clean runner has none, so the build would have failed even once the
  secrets were added. The benchmark harness grew a `download` subcommand rather
  than this needing a new package or a hand-rolled fetch
- Dropped the retired `ggml-small.en.bin` from the workflow's download list. The
  workflow's downloads now match `build_app.py` exactly
- Separated the Parakeet copy from the verified whisper copy in `build_app.py`,
  so a test stubbing the whisper model list no longer reaches for the real
  FluidAudio cache

## 3.4.1: 2026-08-05

Two Choices release. Recognition is one decision now, not four.

Released as 3.4.1 because the 3.4.0 tag was cut one commit early, before the
vocabulary-row and packaging fixes below. It was never published.

- Led the Recognition settings with **Fast** and **Accurate**, folding engine,
  model, decoding profile, and processing mode behind an Advanced disclosure.
  Those four controls existed to serve one decision — lowest latency or best
  accuracy — and made the user assemble it from parts in vocabulary they had no
  reason to know
- Resolved both presets to Parakeet, which is ahead of every Whisper
  configuration on accuracy and latency at once
- Shipped both Parakeet checkpoints inside the app, so the best configuration
  is available on a fresh install with no download at all
- Reported **Custom** for a configuration matching neither preset, highlighting
  no segment and keeping the advanced controls open, since they are the only
  explanation for the state
- Retired Small and Medium English. Parakeet Fast beats Small on size, speed,
  and accuracy at once (217 MB, 3.88%, 34 ms against 466 MB and 8.59%), and
  Medium was the largest and slowest model in the app without being more
  accurate than Turbo. A saved selection of either migrates to Turbo
- Kept Base English and Large-v3 Turbo Q5, because Parakeet accepts no prompt
  and the internal dictionary only biases Whisper
- Emptied the runtime download catalog: every model the app can select now
  ships inside it
- Hid the vocabulary row outright on an engine that accepts no prompt, instead
  of showing it disabled beneath a sentence explaining that it does nothing.
  Entries are still never cleared
- Made the advanced escape hatch a labelled "Advanced Options" button with a
  gear, right-aligned. A `.disclosure` bezel draws a bare triangle and discards
  the button's title, so it rendered as a stray glyph
- Stopped release packaging duplicating the bundled-model list, which drifted
  the moment a model was retired and failed only at DMG time

## 3.3.6: 2026-08-05

An Honest Interface release. Every fix here is a surface that reported
something other than what the app was doing.

- Fixed the Settings window wedging when the Engine chip was switched back and
  forth. Returning from Parakeet applied the whisper model selection before the
  Model row was rebuilt, so a two-segment control was asked for segment three
  and AppKit raised NSRangeException from inside the click handler, abandoning
  the rest of the refresh and ignoring every later click
- Made Parakeet checkpoints install as an explicit step at selection time, with
  a size confirmation, a progress panel, and a working Cancel. The first
  dictation on a new checkpoint previously downloaded several hundred megabytes
  behind a Transcribing badge with no progress and no timeout
- Stopped a cancelled install reporting itself as a failure, and stopped a
  Parakeet problem being described as a whisper helper failure
- Made the User Guide describe the engine that is running. It named the whisper
  model and offered whisper decoding profiles even on Parakeet, which has
  neither
- Marked the internal dictionary inapplicable while Parakeet is selected, where
  entries saved but never reached the recognizer. Entries are kept, not cleared
- Named the running engine in the Setup window, which reported a ready whisper
  model and whisper helper for an engine that uses neither
- Stopped an uninstalled whisper model stranding the engine picker, where every
  whisper engine greyed out at once with no way back from Parakeet
- Stopped offering to reinstall an app already running from ~/Applications

## 3.3.0: 2026-08-05

A Faster and More Accurate Engine release.

- Added Parakeet as a fourth recognition engine, running NVIDIA Parakeet on the
  Neural Engine through FluidAudio. On the repository's LibriSpeech benchmark
  (100 utterances, Apple M5 Pro) it beats every whisper option on both axes at
  once: 2.62% word error rate at 56 ms per utterance, against Large-v3 Turbo
  Q5's 4.32% at 321 ms
- Gave Parakeet its own two checkpoints, Fast and Accurate, and its own saved
  selection, so switching engines no longer overwrites the whisper model choice
- Reordered the Recognition settings so Engine comes first, because it decides
  which models exist and whether Decoding applies at all
- Swapped the Model row to whichever family the selected engine belongs to,
  instead of labelling Parakeet checkpoints with whisper's size names
- Hid the Decoding row on engines that have no beam search, for Parakeet and
  WhisperKit alike, where it was previously greyed out but still painted a
  selected profile
- Dropped the internal dictionary and Pause Mode prompt on Parakeet, which is a
  transducer and accepts no prompt
- Added a reproducible Parakeet benchmark under `Benchmarks/Parakeet/`, scored
  with the same word error math as the whisper benchmark
- Left every existing engine, model, and decoding choice in place

## 3.2.4: 2026-08-05

Clean Dictation and a Real Install release.

- Withheld the internal dictionary's recognition hint from clips with no
  audible signal, where whisper could decode it as a confident continuation and
  splice entries such as `Codex.md` into the middle of real dictation
- Offered to move the app into Applications on first launch, and to relaunch
  from the installed copy through its own bundled launcher
- Opened Settings once on a new installation
- Bundled Base English, Small English, and Large-v3 Turbo Q5, every model the
  first-run profile can select, taking the download to about 1 GB
- Downloaded Medium English on demand with progress and pinned SHA-256
  verification, where selecting it previously did nothing
- Reported progress while an update downloads, verifies, and installs

## 3.2.3: 2026-08-04

Installable Download hotfix.

- Published `whisper_hotkey.zip` as the primary download because
  macOS 15 and later block an unnotarized disk image before it mounts
- Documented the one-time System Settings > Privacy & Security > Open Anyway
  approval in the README and on the product page, and removed the inaccurate
  claim that the download is notarized
- Restored the release workflow, which failed on notarization secrets that do
  not exist and left a hand-uploaded, unopenable disk image on the release page
- Required an explicit channel in `tools/package_dmg.py` so an ad-hoc or preview
  build can no longer be published under the public release asset name
- Kept `whisper_hotkey.dmg` and the stable signing identity unchanged so in-app
  updates and existing privacy grants continue to work

## 3.0.7: 2026-07-31

Instant Start patch.

- Ordered and synchronously displayed the listening HUD before potentially
  blocking microphone hardware initialization
- Removed the consistent visible dead period at accepted dictation startup
- Preserved idle microphone shutdown and ordinary modifier-chord behavior

## 3.0.6: 2026-07-31

Completion Tail hotfix.

- Added a bounded 240-millisecond capture post-roll when confirmed speech
  reaches Send or Enter with less than 180 milliseconds of trailing silence
- Kept silent and already-paused completion gestures immediate
- Preserved the original completion-time insertion target throughout post-roll
- Cancelled pending post-roll work on cancellation, replacement, and shutdown

## 3.0.5: 2026-07-31

Settings Continuity hotfix.

- Replaced the separate custom-theme sheet with an inline Settings editor that
  expands and collapses the existing scrollable document
- Added the runtime HUD's top-center waiting marker to the custom-theme preview
- Enabled standard Settings window close, minimize, resize, and full-screen
  controls plus their native keyboard shortcuts
- Removed the redundant explanatory subtitle from the User Guide header

## 3.0.3: 2026-07-31

Transcription Continuity patch.

- Kept the final waveform, elapsed time, and listening controls visible while
  local transcription runs
- Layered the existing perimeter activity trail over the frozen listening HUD
  without changing its geometry or restoring input handling
- Added a small top-center waiting marker at the activity trail's exact origin
- Removed the blank transcribing capsule between recording and insertion

## 3.0.2: 2026-07-30

Theme Studio release.

- Expanded the HUD theme picker from 11 to 24 persistent presets
- Grouped the theme dropdown into disabled Dark and Light section headings
- Applied light appearance behavior consistently across all ten light presets
- Added a native three-color custom-theme editor with synchronized color wells,
  hex fields, Dark or Light classification, preset naming, and live HUD preview
- Persisted up to 32 named custom presets and grouped them under Custom
- Centered the Stop and Send glyphs with shared deterministic vector geometry
- Corrected the Send arrow to point upward in flipped AppKit button coordinates
- Applied the selected theme to Transcribing, Busy, and No Speech Detected while
  retaining red treatment for actionable failures
- Reorganized the User Guide into a dynamic current-path table followed by only
  the configuration alternatives the user has not selected

## 3.0.1: 2026-07-30

Interface Polish release.

- Reduced the red No Speech Detected feedback to 200 milliseconds without
  changing other error or cancellation durations
- Wrapped the Settings summary chips across two stable rows so longer
  recognition choices remain inside the window

## 3.0.0: 2026-07-30

Parallel Recognition release.

- Added Smart Decode, which accepts a confident greedy pass and retries
  uncertain speech with the existing five-beam Precision path
- Added three explicit processing policies: After Recording, Model Ready, and
  Decode While Speaking
- Added serial background pre-decoding of bounded speech chunks while capture
  continues, retaining one model runtime and one final paste
- Preserved the uninterrupted private recording for safe full-context fallback
  when any background chunk fails
- Added deterministic LibriSpeech benchmarking for accuracy and release latency
- Measured a 15 percent mean post-release latency reduction across 100 clips and
  a 32 percent reduction for clips at least eight seconds long
- Fixed the temporary cancelled menu state so it clears without waiting for the
  next dictation

## 2.11.0: 2026-07-29

Perimeter Flow release.

- Tightened the fixed HUD from 218 by 44 points to a true 203 by 42-point
  capsule with smaller margins and waveform cell
- Equalized Stop and Send as 32-point circular controls while preserving the
  longest countdown without clipping
- Removed the borderless panel's system shadow so the opaque theme background
  is the complete HUD silhouette
- Replaced the transcribing label with a deterministic Core Animation activity
  trail that starts at top center and loops around the complete capsule
- Used seven progressively fading segments without a gradient, polling timer,
  geometry change, or idle work
- Added a persistent Internal dictionary token editor for exact names and
  technical phrases
- Applied the bounded local dictionary prompt to every recognition mode over
  private helper stdin
- Reduced the top-level README to the exact clone-and-run Quick Start

## 2.9.0: 2026-07-29

Apple Acceleration release.

- Added an Engine selector beside Model with Metal, whisper.cpp Core ML
  Encoder, and native WhisperKit choices
- Preserved whisper.cpp Metal as the default and persisted explicit engine
  selection across launches
- Added pinned, checksum-verified bootstrap paths for whisper.cpp Core ML
  encoders and WhisperKit model and tokenizer bundles
- Bundled the private Core ML whisper.cpp runtime libraries inside the signed
  application while keeping model weights outside the app
- Required accelerated artifacts to be complete before enabling their Settings
  choices and prohibited silent fallback to another engine
- Added local-only WhisperKit inference with optional model residency and
  bounded unload behavior on cancellation, failure, model changes, and quit
- Added explicit helper validation so the Core ML encoder option cannot run
  against a non-Core ML whisper.cpp build
- Added an optional Keep Model Ready setting for preloading and reusing the
  selected whisper.cpp helper between dictations
- Kept model readiness off by default and retained bounded cleanup on disable,
  model changes, cancellation, failure, restart, and quit
- Updated the User Guide with the warm-model speed and idle-memory tradeoff
- Applied the selected HUD theme to Settings and the User Guide
- Replaced the translucent guide canvas with an opaque themed background and
  higher-contrast text
- Removed the remaining explanatory sentence area from the Settings footer

## 2.6.0: 2026-07-28

Personalization release.

- Simplified the user-facing settings name to Settings throughout the UI
- Replaced the three-choice behavior and four-choice model menus with one-click
  segmented chips
- Reorganized Settings into clear Input, Recognition, and Startup sections
- Added a lower-right User Guide covering every gesture, completion key, HUD
  control, behavior, model, menu action, and privacy guarantee
- Added compact live summary chips for the active key, behavior, model,
  recording limit, and login state
- Fixed the User Guide rendering as a visible, selectable native text document
- Removed redundant privacy copy from the minimal Settings footer
- Halved the No Speech Detected badge duration from two seconds to one
- Added a persistent Theme dropdown with GitHub Dark Dimmed and ten varied HUD
  presets that apply immediately without idle work

## 2.5.0: 2026-07-28

Live Flow release.

- Added Pause Mode for automatic ordered phrase insertion after natural pauses
- Reused one loaded Whisper helper during an active Pause Mode session while
  preserving zero model/audio-worker residency at idle
- Added bounded local prior-phrase context for continuation punctuation and
  casing across Pause Mode chunks
- Kept Pause Mode capture uninterrupted in one private full-session recording
  while rotating lightweight inference segments at adaptive cadence boundaries
- Reduced Pause Mode's adaptive boundary to a live 300–750 ms range with a
  450 ms initial target
- Made the listening badge draggable from its waveform or timer, preserving and
  clamping the chosen position through the rest of the dictation
- Tightened the timer cell to compact the fixed-size listening badge
- Positioned Accessibility-anchored badges above the complete focused field,
  with a below-field screen-edge fallback, so dictated text remains unobscured
- Kept terminal badges near the active caret by rejecting oversized or distant
  focused-container geometry
- Automatically followed focused text controls during active dictation through
  a recording-only event-driven Accessibility observer
- Locked the badge at its chosen position after the first drag, resetting that
  lock for the next dictation
- Made Escape unambiguously abort active dictation, discard its private audio,
  cancel recognition, and insert nothing
- Reserved Escape for cancellation and migrated legacy Escape triggers to Right
  Command
- Made Return and keypad Enter stop, insert, and submit active dictation
- Preserved ordinary Escape and Return behavior outside active dictation

## 2.0.0: 2026-07-28

Major interaction and reliability release.

- Added explicit Press and Hold and Toggle dictation modes
- Added a focused Settings window while keeping the menu compact
- Added an in-menu Restart action
- Added silence detection so empty recordings do not produce hallucinated text
- Reworked the recording controller into a compact, fixed-size, borderless HUD
- Kept the HUD pinned to its initial caret or pointer anchor throughout a session
- Positioned the pointer-fallback Send control directly beneath the pointer
- Added low-cost waveform feedback, Stop and Insert, and unmodified-Return Send
- Simplified duration feedback to elapsed time normally and an orange-to-red
  remaining-time warning during the final minute
- Fixed intermittent HUD disappearance across repeated sessions and macOS Spaces
- Fixed Send accidentally inheriting held modifier flags
- Expanded native AppKit regression coverage for controls, layout, visibility,
  state transitions, and pointer placement

## 1.0.0: 2026-07-28

First public release.

- Global configurable hold-to-talk and toggle dictation gestures
- Local English whisper.cpp recognition with four selectable models
- Menu-bar status and persistent preferences
- Caret-preferred, mouse-fallback recording controller with waveform and timer
- Stop-and-insert and insert-and-send controls
- Context-aware boundary spacing and selection replacement through Command-V
- Login-item support and terminal start, stop, status, setup, and logs commands
- Private temporary audio, bounded helper cleanup, and no cloud processing
