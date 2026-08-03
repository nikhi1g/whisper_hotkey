Version 3.1.1 adds explicit, privacy-preserving GitHub update checks to Settings.

Recommended for all users of version 3.0.

## Highlights

- Add a manual **Check for Updates** action with clear checking, current,
  available, and failure states.
- Add an off-by-default **Check automatically** preference that performs one
  stable-release check per launch when enabled.
- Request only public GitHub release metadata. Never send audio, transcripts,
  dictionary entries, settings, or device identifiers.
- Keep update checks event-driven with no polling, background timer, automatic
  download, or silent installation.

This source-only patch release exists to verify the in-app stable-release check.
The downloadable DMG remains on the previous release path until signing and
notarization credentials are configured for the release workflow.
