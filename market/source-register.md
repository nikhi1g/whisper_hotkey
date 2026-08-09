# Source register

Accessed 2026-08-09 unless otherwise stated. Product capabilities, prices, and
privacy policies are volatile; re-open every primary source before publishing
a comparison page or advertisement.

## Primary company and platform sources

| Source | Supports | Limitation |
| --- | --- | --- |
| [Apple: Dictate messages and documents on Mac](https://support.apple.com/guide/mac-help/mh40584/mac) | System-wide Dictation behavior, commands, local/server status disclosure, languages | Availability varies by language, region, and device settings |
| [Apple: Siri, Dictation & Privacy](https://www.apple.com/legal/privacy/data/en/ask-siri-dictation/) | When audio can be processed on-device or sent to Apple; retention/training choices | Covers Apple’s complete Siri/Dictation system, not a third-party comparison |
| [Superwhisper Pro](https://superwhisper.com/docs/get-started/sw-pro) | $8.49 monthly, $84.99 annual, $249.99 lifetime; local models and advanced features in Pro | Vendor documentation |
| [Superwhisper offline transcription](https://superwhisper.com/offline-transcription) | On-device/offline positioning and target use cases | Vendor comparison claims should not be treated as independent testing |
| [Wispr Flow pricing](https://wisprflow.ai/pricing) | Free limits, Pro pricing, languages, privacy mode, team features | Dynamic monthly/annual page can expose different price text in different sections |
| [Wispr security and compliance FAQ](https://docs.wisprflow.ai/articles/3467817258-security-and-compliance-faq) | Privacy Mode, Cloud Sync, training and retention behavior | Vendor policy; settings/defaults can change |
| [Aqua pricing](https://aquavoice.com/) | Free allowance and Pro/Max/Team prices | Vendor page |
| [Aqua FAQ](https://aquavoice.com/info/faq) | Cloud-only operation, self-reported <50 ms startup and ~450 ms finish, WER claims, retention controls | Performance and application WER are vendor-reported and not paired with this product |
| [Aqua privacy policy](https://aquavoice.com/info/privacy) | Account, transcript, metadata, service-provider handling | Policy dated 2025-05-22; check for newer version |
| [MacWhisper](https://www.macwhisper.com/) | €64 one-time Pro price, local model support, dictation and transcription features | Vendor page combines many features and repeated testimonials |
| [Spokenly pricing](https://spokenly.app/pricing) | Unlimited local free tier, no account for local, $99.99/year Pro, platforms | Vendor page |
| [VoiceInk site](https://tryvoiceink.com/) and [pricing](https://tryvoiceink.com/pricing) | Local transcription/enhancement, optional connected cloud providers, $29/$49/$69 lifetime plans | Vendor claims; packaged build licensing differs from the build-from-source path |
| [Willow pricing](https://willowvoice.com/pricing) | Free, $15 monthly/$12 annual Pro, cloud/privacy features | Included for category context, not in the core matrix |
| [Willow privacy](https://help.willowvoice.com/en/articles/12854269-how-willow-protects-your-data-and-privacy) | Cloud processing, default Private Mode, local history claims | Vendor policy |
| [Typeless data controls](https://www.typeless.com/data-controls) | Cloud processing, zero-retention claim, context processing | Language/localized page availability may vary |

## Repository sources

| Repository | Evidence used |
| --- | --- |
| [`nikhi1g/whisper_hotkey`](https://github.com/nikhi1g/whisper_hotkey) and [v4.2.5 release](https://github.com/nikhi1g/whisper_hotkey/releases/tag/v4.2.5) | Public positioning, supported platform, install path; live GitHub API check found 1 star, 0 forks/issues, latest tag v4.2.5, and 1 ZIP download |
| [`cjpais/Handy`](https://github.com/cjpais/Handy) | MIT, cross-platform local Whisper/Parakeet, 29.1k-star snapshot |
| [`Beingpax/VoiceInk`](https://github.com/Beingpax/VoiceInk) | GPL, native macOS local dictation, 5.8k-star snapshot |
| [`OpenWhispr/openwhispr`](https://github.com/OpenWhispr/openwhispr) | MIT, local/cloud, meetings/notes/agents, 5.3k-star snapshot |
| [`moona3k/macparakeet`](https://github.com/moona3k/macparakeet) | GPL, notarized Parakeet-first Mac app, 547-star snapshot |
| [`watzon/pindrop`](https://github.com/watzon/pindrop) | MIT, notarized native app, local engines/streaming/history/optional cloud |
| [`VocaHQ/vocamac`](https://github.com/VocaHQ/vocamac) | AGPL, notarized WhisperKit app, 75-star snapshot |
| [`sam-pop/WhisperDictation`](https://github.com/sam-pop/WhisperDictation) | MIT, no-account/no-telemetry claims, developer vocabulary, unnotarized install |

Repository stars are discovery/community signals, not quality scores.
Release download counters can include maintainers and automation; they are not
evidence of activation or retention.

## Directional user evidence

| Source | Signal | Interpretation limit |
| --- | --- | --- |
| [Handy shortcut discussion #211](https://github.com/cjpais/Handy/discussions/211) | User reports several-hundred-millisecond readiness delay and missed opening words; requests alternative activation | One discussion, not incidence data |
| [Handy issue #898](https://github.com/cjpais/Handy/issues/898) | Modifier-only toggle conflicts with larger chords | Product/version-specific |
| [Handy issue #1332](https://github.com/cjpais/Handy/issues/1332) | Long recording reportedly lost silently | Single report and environment |
| [FluidVoice launch discussion](https://www.reddit.com/r/macapps/comments/1ucezv2/os_fluidvoice_is_back_with_a_bang_free_local_ai/) | First words dropped; cleanup aggressiveness and hotkey requests | Community thread; includes creator promotion |
| [Local-first dictation discussion](https://www.reddit.com/r/macapps/comments/1mpd7fz/whispering_opensource_localfirst_dictation_you/) | Trust in open source, push-to-talk desire, Accessibility-permission objection | Qualitative comments only |
| [Superwhisper pricing discussion](https://www.reddit.com/r/superwhisper/comments/1s7k6f3/struggling_with_the_new_superwhisper_pricing/) | Subscription/lifetime price sensitivity | Small self-selected community sample |
| [RSI correction-cost discussion](https://www.reddit.com/r/RSI/comments/1un500e/anyone_who_dictates_because_of_rsi_does_it/) | Jargon and correction keystrokes can negate dictation value | Original poster discloses product affiliation |
| [Faithful vs cleanup discussion](https://www.reddit.com/r/RSI/comments/1u90xl8/voice_dictation_finally_took_most_of_the_typing/) | Some users prefer literal output and alternate triggers | Original poster discloses product affiliation; validate independently |
| [Mac dictation comparison discussion](https://www.reddit.com/r/macapps/comments/1u4zho1/comparison_of_dictation_apps/) | Separates capture, model, cleanup, privacy, and cost; recommends workflow-specific tests | Community synthesis, not controlled research |
| [Show HN: Whispering](https://news.ycombinator.com/item?id=44942731) | Requests for local-first education use, activation modes, iOS, commands, and transcript actions | Self-selected technical audience |

## Internal evidence

- [`../README.md`](../README.md): current install, recognition choices, privacy,
  and benchmark summary.
- [`../docs/MODELS.md`](../docs/MODELS.md): exact corpus/device/decode benchmark
  qualifiers and current model policy.
- [`../docs/releases/4.2.5.md`](../docs/releases/4.2.5.md): key-edge capture,
  FIFO/writer separation, toggle-close fix, test matrix, and explicit statement
  that WER did not change.
- [`../purpose.md`](../purpose.md): intended product and privacy boundaries.

Internal documents are implementation evidence, not independent validation.
