# Current repository audit diff

Compared with the packet's `MD/02_CURRENT_REPOSITORY_AUDIT.md`, against
current-main baseline commit `210009e607e70e2b7c506144a230a82e1447b37f`.
The machine-readable form is [`audit-diff.json`](audit-diff.json).

| Audit fact | Status | Current checkout |
| --- | --- | --- |
| Recognition contract is string-only | Changed | Whisper now has `resultRich`/`RecognitionHypothesis`; compatibility string APIs remain. |
| Whisper fallback timestamps are disabled | Confirmed with scope | CLI fallback still uses `-nt`; helper protocol v2 can emit timing metadata. |
| Recognizer owns and deletes source audio | Partially changed | `preserveAudio` exists, but default deletion remains and no session lease exists. |
| Parakeet rich output is discarded | Confirmed | `ParakeetRuntime.transcribe` and its wrapper retain text only. |
| Smart Decode is selective repair | Confirmed with rich metadata | Adaptive mode retries the complete requested sample range; no uncertain-span planner exists. |
| Swift discards helper evidence | Partially changed | Protocol v2 maps rich Whisper evidence, but propagation is not complete across providers/call sites. |
| Decode While Speaking stores independent strings | Confirmed | `PredecodedTranscriptAccumulator` still joins `[String]` chunks. |
| Recognition chain is serial | Confirmed | One actor/helper path preserves ordered recognition and delivery. |
| Current benchmark supports a product accuracy claim | Confirmed insufficient | Only the 100-utterance LibriSpeech smoke track is wired; no app corpus/lifecycle harness. |

The changed facts do not alter recognition behavior in W00. They identify the
contract, provider, audio-lifetime, and benchmark hooks that later Phase 1
workers must close. The `confirmed with scope` result for the command-line
fallback is deliberate: rich helper timing is available for experiments, but
fallback output is still timestamp-free.
