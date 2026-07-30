Version 3.0.2 adds a complete native theme editor and corrects the alignment
and direction of the HUD action icons.

Recommended for all users of version 3.0.

## Highlights

- Expand the built-in HUD collection from 11 to 24 restrained themes.
- Group built-in themes into clear Dark and Light sections.
- Create named custom presets from three synchronized native color wells and
  six-digit hex fields.
- Preview custom colors live using the same capsule palette and icon geometry
  as the runtime HUD.
- Persist up to 32 custom themes locally and edit them later.
- Keep Stop and Send glyphs centered inside equal circular controls.
- Ensure the Send arrow points upward in both Settings and the runtime HUD.
- Apply the selected theme to Transcribing, Busy, and No Speech Detected while
  keeping actionable failures red.
- Put the user's complete active workflow and its meaning first in the User
  Guide, followed by a table containing only unselected alternatives.
- Retain the complete v3.0 local recognition and privacy behavior.

Quick Start:

```sh
git clone https://github.com/nikhi1g/whisper_hotkey.git
cd whisper_hotkey
./run.sh
```

The release includes source and a signed arm64 app bundle. The app is not
notarized and model weights are not included. Existing users should replace the
installed app with this patch. The verified source bootstrap remains the
recommended installation path for a new Mac.
