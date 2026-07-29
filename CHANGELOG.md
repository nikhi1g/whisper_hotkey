# Changelog

## Unreleased

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
- Made Escape unambiguously abort active dictation, discard its private audio,
  cancel recognition, and insert nothing
- Reserved Escape for cancellation and migrated legacy Escape triggers to Right
  Command
- Made Return and keypad Enter stop, insert, and submit active dictation
- Preserved ordinary Escape and Return behavior outside active dictation

## 2.0.0 — 2026-07-28

Major interaction and reliability release.

- Added explicit Press and Hold and Toggle dictation modes
- Added a focused Advanced Settings window while keeping the menu compact
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

## 1.0.0 — 2026-07-28

First public release.

- Global configurable hold-to-talk and toggle dictation gestures
- Local English whisper.cpp recognition with four selectable models
- Menu-bar status and persistent preferences
- Caret-preferred, mouse-fallback recording controller with waveform and timer
- Stop-and-insert and insert-and-send controls
- Context-aware boundary spacing and selection replacement through Command-V
- Login-item support and terminal start, stop, status, setup, and logs commands
- Private temporary audio, bounded helper cleanup, and no cloud processing
