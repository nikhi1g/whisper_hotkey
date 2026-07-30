Version 3.0.1 keeps every Settings summary chip visible and makes empty
recording feedback disappear promptly.

## Highlights

- Split the Settings summary into two stable rows.
- Keep long combinations such as Turbo, Metal, Smart Decode, and Decode While
  Speaking fully inside the window.
- Preserve each complete summary chip instead of compressing it into an empty
  capsule or allowing it to cross the window edge.
- Increase the Settings content height slightly so both rows retain normal
  spacing.
- Reduce the red No Speech Detected feedback from one second to 200
  milliseconds.
- Leave cancellation and other error durations unchanged.
- Retain all v3.0 Parallel Recognition functionality.

Quick Start:

```sh
git clone https://github.com/nikhi1g/whisper_hotkey.git
cd whisper_hotkey
./run.sh
```

The release includes source and a signed arm64 app bundle. The app is not
notarized and model weights are not included. The verified source bootstrap is
the recommended installation path for a new Mac.
