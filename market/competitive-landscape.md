# Competitive landscape

Snapshot date: 2026-08-09. Prices and features change frequently. Official
product pages are used for factual claims; community posts and GitHub issues
are treated only as directional evidence of user problems.

## The market in one view

| Product | Current offer | Local/privacy posture | Market strength | Opening for `whisper_hotkey` |
| --- | --- | --- | --- | --- |
| Apple Dictation | Included with macOS | On-device availability varies by language/settings; Keyboard settings disclose whether audio/text stays on-device | Zero install, live text, multilingual, native trust | More transparent local-only boundary, model choice, faithful technical workflow |
| Superwhisper | Free dictation; local models and advanced modes in Pro at $8.49/mo, $84.99/yr, or $249.99 lifetime | Advertises offline processing for local models; cloud options also exist | Polished, cross-platform, modes, vocabulary, established brand | Simpler/no-cost offer, smaller scope, measurable key-edge capture |
| Wispr Flow | Free limited tier; Pro $15/user/mo monthly (annual discount shown) | Cloud transcription; Privacy Mode and Cloud Sync controls govern training/retention | Cross-device UX, live polished text, team/admin features | Truly local path with no account, internet, or privacy toggle to configure |
| Aqua Voice | 1,000 words free; Pro $8/mo; Max $24/mo | Cloud-only; Privacy Mode changes transcript retention; SOC 2 Type II | Self-reported <50 ms startup and ~450 ms completion, app-aware polish, dictionaries | Verifiable offline behavior and literal output; must match perceived speed |
| MacWhisper | Free; Pro €64 one-time | Local transcription/model options, with optional external/local AI services | Mature file, meeting, export, and dictation suite; multilingual | Focused dictation without suite complexity or history |
| Spokenly | Unlimited local Whisper/Parakeet free; Pro $99.99/year for managed cloud | Offline local tier, no account required; BYO cloud keys available | Free local use, cross-platform, many languages, streaming/cloud flexibility | Hard to beat on price; compete on measured reliability, faithful minimalism, and privacy audit |
| VoiceInk | Free trial; $29/$49/$69 lifetime by Mac count; GPL source repo | Local transcription/enhancement; optional connected cloud provider | Open-source awareness, vocabulary/replacements, modes, polished distribution | Compete on narrower scope, measured capture reliability, and free core rather than model availability |

Official details and URLs are in [source-register.md](source-register.md).

## Open-source repository field

Local dictation is a highly active open-source category:

| Repository | Public signal on 2026-08-09 | Scope | Strategic lesson |
| --- | ---: | --- | --- |
| [Handy](https://github.com/cjpais/Handy) | 29.1k stars | Free, MIT, macOS/Windows/Linux, Whisper and Parakeet | “Free, private, simple” already has enormous reach; evidence and Mac-specific reliability must differentiate |
| [VoiceInk](https://github.com/Beingpax/VoiceInk) | 5.8k stars | GPL native macOS app, local models, modes, context, vocabulary | Open source plus polished UX and paid convenience is established |
| [OpenWhispr](https://github.com/OpenWhispr/openwhispr) | 5.3k stars | MIT, cross-platform dictation, meetings, notes, agents, local/cloud | Feature breadth is not an open lane; focus can be the counter-position |
| [MacParakeet](https://github.com/moona3k/macparakeet) | 547 stars | GPL, notarized, Parakeet/Whisper, dictation plus media/meeting tools | A free notarized Parakeet competitor raises the installation bar |
| [Pindrop](https://github.com/watzon/pindrop) | Active repository | MIT native macOS, several local engines, streaming, library, notes, optional cloud | Notarized packaging, language breadth, and local streaming are becoming normal |
| [VocaMac](https://github.com/VocaHQ/vocamac) | 75 stars | AGPL, notarized, WhisperKit, push-to-talk and toggle | Even small projects can provide a normal signed/notarized download |
| [WhisperDictation](https://github.com/sam-pop/WhisperDictation) | Active repository | MIT, local Whisper, developer vocabulary, push/toggle | Privacy, no telemetry, technical vocabulary, and “works in any app” are common claims |

By comparison, the public `whisper_hotkey` repository showed one star and zero
forks in GitHub’s page snapshot. The immediate constraint is distribution and
trust, not a shortage of internal architecture.

## What is now table stakes

- a configurable global trigger;
- push-to-talk and toggle behavior;
- direct insertion in common apps;
- local Whisper and/or Parakeet;
- Apple Silicon acceleration;
- an offline/no-audio-upload option;
- a visible recording indicator;
- a custom dictionary or correction story;
- a free trial or free local tier;
- signed, and increasingly notarized, Mac distribution.

These belong in product completeness, not the headline.

## Recurring user pain signals

| Signal | Evidence | Product opportunity |
| --- | --- | --- |
| Opening words are lost because capture is not ready | A Handy user reported “a few to several 100 ms” before the widget starts and missing first words; a FluidVoice user reported the first few words being dropped | Publish a first-word benchmark across device generations and immediate-speech offsets |
| Shortcut semantics conflict with normal Mac chords | Handy issue #898 describes a modifier-only toggle firing inside larger shortcuts | Prove bare-gesture discrimination and exactly-once behavior |
| Long dictations can disappear without a useful failure | Handy issue #1332 reports roughly five-minute recordings silently lost | Make limits explicit, fail visibly, retain nothing after failure, and test the configured maximum |
| Users want live reassurance, but local streaming is difficult | Repeated Reddit and HN requests ask for text as speech arrives | Measure whether an immediate trustworthy badge plus fast final text is enough before adding streaming complexity |
| Jargon corrections can erase the ergonomic benefit | RSI discussion highlights names, technical terms, and repeated correction keystrokes | Optimize correction cost and vocabulary success, not generic WER alone |
| Generative cleanup can change voice or meaning | Users describe preferring faithful transcription and worrying that cleanup changes tone | Make literal output a deliberate product benefit; any cleanup must be optional and visibly separate |
| Accessibility/Input Monitoring permission creates distrust | A commenter on a local-first dictation launch called Accessibility a “no-go” without understanding why it was needed | Explain each permission at the moment of use and offer a clipboard-only fallback if validated |
| Subscription fatigue is real | Superwhisper community discussion questions a $249.99 lifetime price and ongoing subscriptions | Keep the core free/open, then test one-time convenience/support value |

These are qualitative signals, not prevalence estimates. Validate them with
the screener and task test before ranking work.

## Price and three-year cost snapshot

This is not an apples-to-apples quality comparison; it shows the cost shapes a
buyer encounters.

| Product/plan | Listed price | Approximate three-year spend |
| --- | ---: | ---: |
| Apple Dictation | Included | $0 |
| Handy / Spokenly local / other free OSS local tools | Free | $0 |
| MacWhisper Pro | €64 once | €64 |
| VoiceInk Solo | $29 once | $29 |
| Superwhisper annual | $84.99/year | $254.97 |
| Aqua Pro | $8/month | $288 |
| Spokenly Pro | $99.99/year | $299.97 |
| Wispr Flow Pro annual rate shown as $12/month | $144/year | $432 |
| Superwhisper lifetime | $249.99 once | $249.99 |

Taxes, regional prices, discounts, and plan changes are excluded. Local and
cloud features differ, so cost alone cannot determine the winner.

## Where the product can credibly win

1. **First-word reliability as a published result.** Competitors discuss
   “fast,” “instant,” or live output; very few expose physical key-down to first
   audio and first-token retention.
2. **Verifiable privacy instead of privacy settings.** A build with no normal
   network path, ephemeral audio, no account, no history, and a reproducible
   audit is legible to security-minded users.
3. **Faithful output.** Cloud products increasingly rewrite and format. Some
   users need the words they said, with deterministic formatting only.
4. **Minimal idle behavior.** No active microphone, no polling, and a model
   policy that can keep no helper resident is a concrete counterpoint to broad
   productivity suites.
5. **Release-time targeting and cleanup.** Correct destination capture,
   exactly-once insertion, clipboard restoration, cancellation, and private
   file deletion can become a reliability story if tested publicly.

## Where it currently loses

- The unnotarized ZIP and Open Anyway sequence are materially worse than
  Pindrop, MacParakeet, and VocaMac’s notarized downloads.
- English-only support loses to most established products.
- Default Parakeet cannot use the current prompt-based internal dictionary.
- There is no live transcript, cross-device app, team administration, formal
  compliance package, or established support organization.
- The public project has almost no social proof.
- Public documentation has accumulated changing model/default/install language
  and needs one release-specific truth source before outreach.

The answer is not to copy every missing feature. Fix the trust, proof, and
correction-cost gaps first; validate which expansion users will actually retain.
