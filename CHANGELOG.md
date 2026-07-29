# Changelog

## Unreleased

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
