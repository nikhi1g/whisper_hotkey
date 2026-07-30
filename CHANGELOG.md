# Changelog

## Unreleased

- Expanded the HUD theme picker from 11 to 24 persistent presets
- Grouped the theme dropdown into disabled Dark and Light section headings
- Applied light appearance behavior consistently across all ten light presets

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
