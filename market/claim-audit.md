# Public claim audit

Audit date: 2026-08-09. This is a messaging asset, not a request to change code
in this research step.

Before recruiting beyond a small technical cohort, one release-specific truth
sheet should feed the website, README summary, release notes, demo captions,
and comparisons. A privacy product loses credibility when small public details
disagree, even if the application behavior is sound.

## Conflicts and ambiguities to resolve

| Topic | Current public/internal wording | Risk | Canonical wording for 4.2.5 marketing |
| --- | --- | --- | --- |
| Human download | README correctly directs people to `whisper_hotkey.zip`; the website Setup section still says “Open the disk image” | A browser-downloaded unnotarized DMG is deliberately not the human path and can reach a Move to Trash dead end | “Download the ZIP, unzip it, and move the app to Applications.” |
| Recognition family | Website data-flow diagram labels recognition “Local Whisper”; current shipping default is Parakeet Unified, with three Parakeet choices and Whisper Turbo | Product name and diagram make the actual default look undisclosed | Use “Local recognition” in general diagrams; name Parakeet/Whisper only in the technical details |
| Model/user choice | Current README leads with Fast and Accurate presets, then four individual choices; older purpose text still describes a four-Whisper-model picker | Campaign copy can accidentally describe an obsolete UI | “Choose Fast or Accurate, or inspect four local recognition choices.” Verify against the exact build before publishing |
| Network behavior | README broadly says the installed app does not make network requests; the product contract allows an explicit manual update check and an off-by-default once-per-launch check | “No network requests” can be falsified by a user who enables updates | “Dictation makes no network request. Only a manual or explicitly enabled once-per-launch update check contacts GitHub release metadata.” |
| Included/downloaded models | Download copy says pinned models are included; Whisper Turbo is an on-demand, verified local download while bundled Parakeet choices work immediately | “No model download” sounds universal when it applies to the fresh default path | “The bundled Parakeet choices work without a model download; optional Whisper Turbo is downloaded only when selected.” |
| Size | README/source-build section mentions a 141 MB default model, while the release default Parakeet Unified is about 594 MB | Source-build and release-install defaults are easy to conflate | Keep source-build and packaged-release requirements in separate labeled sections |
| Performance | WER/decode latency is prominent; 4.2.5 changes capture startup and integrity, not decoder output | Readers may infer the release lowered WER or that 45 ms is press-to-text | “2.46% combined WER and 45 ms p50 decode on 100 LibriSpeech utterances, warm on an M5 Pro; end-to-end results pending.” |
| “Instant” first-word behavior | Architecture and deterministic tests support key-edge capture; representative device/user data has not been published | An absolute claim is vulnerable to microphone/device variance | “Capture is designed to start at the physical key edge.” Promote to a numeric claim only through the scorecard |
| Privacy/history | No transcript library exists, but a latest-result clipboard fallback may remain in memory until quit if enabled | “Nothing retained” can be too broad | “No transcript history is written. The optional latest-result fallback is memory-only until the app quits.” Verify exact setting/release behavior |
| Install trust | Build is stably Apple Development-signed, not notarized | Hiding Open Anyway creates abandonment and suspicion | Put the limitation and three permission purposes next to every download button |
| Product name | `whisper_hotkey` implies Whisper is the product/default even though Parakeet leads recognition | Technical name is acceptable for GitHub but may confuse a broader audience | Test a plain-language display/marketing name only after the beachhead validates; do not rename during this research step |

## Release claim sheet template

Complete this for every public release:

- Version/tag/hash:
- Published date:
- Supported Mac hardware/macOS:
- Human download artifact and SHA-256:
- Signature identity/notarization state:
- Permissions and exact purpose:
- Default preset/recognition choice/processing/input behavior:
- Included choices and optional downloads:
- Dictation-time network behavior:
- Update-check behavior and default:
- Audio lifetime and deletion paths:
- Transcript/history/clipboard behavior:
- Benchmark corpus/device/sample/configuration:
- WER and decode latency:
- End-to-end latency and first-word cohort result:
- Known limitations/regressions:
- Compatibility matrix link:

If a field is unknown, publish “not measured” rather than copying it from a
previous release.

## Search and distribution hygiene

- Search indexes may lag the latest GitHub release; always link the exact tag
  in a campaign and confirm `/releases/latest` resolves correctly first.
- Keep one permanent human-download URL that resolves to the ZIP policy.
- Use release-numbered demo captions so old clips cannot masquerade as current
  results.
- Put benchmark protocol and raw result links beside every number.
- Recheck competitor names, domains, and prices immediately before publishing;
  “VoiceInk,” in particular, is used by more than one site on the web.
