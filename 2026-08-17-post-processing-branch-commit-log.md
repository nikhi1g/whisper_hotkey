# Session Log — 2026-08-17 — voice-to-prompt post-processing (`post_processing` branch)

> Auto-generated session summary. For future agents and the owner: this file
> records everything built on the `post_processing` branch in this session and
> the live state of the machine. See also [`POST_PROCESSING_PLAN.md`](POST_PROCESSING_PLAN.md)
> for the full orchestration plan and contracts.

## Branch status

- `main` is untouched except the archive commit below.
- All work lives on `post_processing`; never merge to `main` until the owner says so.
- The installed app at `/Applications/whisper_hotkey.app` **is the branch build**
  (rebuilt and reinstalled several times this session; Parakeet checkpoints
  bundled via `WHISPER_HOTKEY_BUNDLE_MODEL=1`).

## Commit timeline (canonical branch history)

| Hash | Time | Message |
|---|---|---|
| `988c7ef` | 22:42 | chore: add phase1 ultra-low-wer orchestration packet archive (main) |
| `0bdc526` | 22:44 | docs: add voice-to-prompt post-processing orchestration plan |
| `45e03cb` | 22:48 | docs: fix keychain contract, add setup script and preference ownership to plan |
| `ffc0670` | 22:48 | docs: use flat worktree branch names (git forbids post_processing/ prefix) |
| `49f8b0a` | 22:49 | feat: add one-time DeepSeek keychain setup script |
| `98389ca` | 22:57 | feat: add voice-to-prompt post-processing contracts (Core) |
| `3e86cc7` | 23:11 | feat: add DeepSeek transcript processor and keychain helper |
| `1f0a807` | 23:05 | feat: add post-processing preservation bench (corpus, recorder, runner, fixtures) |
| `82db2c9` | 23:16 | docs: assign Contracts.swift DictationPhase case to w17 |
| `d942bbb` | 23:22 | feat: configurable thinking mode and reasoning effort for DeepSeek processor |
| `f769258` | 23:22 | feat: setup script verifies both flash and pro processor models |
| `8ce1435` | 23:23 | docs: document thinking toggle, effort, model picker and setup verification |
| `137dc7c` | 23:42 | feat: add post-processing review UI and settings controls |
| `00e1c78` | 23:43 | feat: wire post-processing review flow into dictation (app integration) |
| `0fcaa41` | 23:49 | feat: drive processor model/thinking/effort from Settings preferences |
| `4eb1ae1` | 23:50 | docs: branch-scoped post-processing product contract section |
| `d6f9d76` | 00:07 | feat: full reasoning-effort range, key paste, and test-before-save with check feedback |
| `f1f5d5c` | 01:24 | fix: trusted-app keychain ACL, async status read, guard flattening |

(Worktree feature branches `w14-contracts`, `w15-client`, `w16-ui`,
`w17-integration`, `w18-bench` exist under `.claude/worktrees/` with their own
commits; the integrated equivalents are the cherry-picks above.)

## What was built

**Feature:** a voice-to-prompt middleware layer on top of the existing local
dictation. Dictated text is optionally sent to the DeepSeek API
(`deepseek-v4-flash` or `deepseek-v4-pro`) and rewritten through a semantic
profile (verbatim / clarity / coding) before the existing paste path inserts it.

- **Control plane** — local deterministic voice-command parser
  (`mode clarity|coding|verbatim`, `scratch that`, `send`, `cancel`,
  `show original`); commands never reach the API.
- **Contracts** (`WhisperHotkeyCore`) — bounded `PostProcessRequest` /
  `PostProcessResult`, `SemanticProfileCatalog` (profiles are data),
  `PreservationChecker`, `AutoSendGate`, `VoiceCommandParser`,
  `PostProcessPreview`. New state-machine phase `reviewing`.
- **DeepSeek client** (`WhisperHotkeyShell`) — `DeepSeekTranscriptProcessor`
  actor, URLSession, JSON mode, 5 s timeout, retry-once-then-raw-fallback,
  `validateCredentials()` ping. Configurable thinking toggle (off default;
  DeepSeek server default is ON, so the wire always sends an explicit toggle)
  and reasoning effort `low|medium|high|xhigh|max`.
- **Settings UI** — Post-processing section: enable toggle, profile chips,
  model picker (flash/pro), Thinking toggle, Reasoning-effort picker, API-key
  field with **Paste**, **Test** (live check, temporary ✓/✗), and **Save**
  (validates before storing; never overwrites a working key with a bad one).
- **Review flow** — after transcription: reviewing state on the existing
  non-activating badge; raw vs processed, preserved tokens, corrections, risk;
  Enter accepts (existing clipboard transaction + Command-V), Cmd+Z raw,
  Esc cancels; processor failure → "unavailable — raw shown". Generation
  tokens keep stale results from pasting.
- **Setup script** — `setup_deepseek_wh_hotkey.sh`: builds the branch, stores
  the key in the login keychain with a trusted-app ACL, verifies read-back,
  `--verify` checks **both** models, prints next steps.
- **Bench** — `Benchmarks/Performance/post-processing/`: §6 preservation
  corpus, cassette recorder (gitignored output), offline gate runner.
  Gates: hard preservation ≥95%, 0 explain-instead-of-rewrite, 100% negation/
  identifier cases, p50 ≤1 s / p95 ≤3 s, determinism 100%.

## Keychain contract (fixed; both sides share it)

```
service: com.whisperhotkey.deepseek
account: api-key
kind:    generic password
```

- Read precedence: `DEEPSEEK_API_KEY` env first, then keychain.
- The item must carry a **trusted-app ACL** for `/Applications/whisper_hotkey.app`
  (`security add-generic-password -T`), or the app cannot read it:
  the `security` CLI ties items to itself otherwise, and `-A` proved
  ineffective on this macOS. The setup script writes `-A -T` both.
- `ProcessorKeychain.store` deletes then adds, with an `errSecDuplicateItem`
  → `SecItemUpdate` fallback.
- Settings' status read is **detached/non-blocking** — a restricted ACL must
  never freeze the main thread (it once hung the full test suite, see below).

## Bugs found and fixed this session (live user reports)

1. **"Post-processing does nothing / not restructuring"** — root cause: the
   keychain item was unreadable by the app (CLI-created, no trusted-app ACL),
   plus a double-optional bug at the delegate guard
   (`(try? read()) != nil` nests `String??`; a nil item compared non-nil).
   Net effect: silent fallback to direct raw insert, zero processor log lines.
   Fixed: ACL, guard flattening. Verified live via a harness: coding profile
   restructures `"use fast api no i mean fastapi..."` into a structured brief.
2. **"API key not saving"** — same root cause: `store()` hit an invisible
   duplicate (`errSecDuplicateItem`). Fixed via trusted-app ACL + update
   fallback.
3. **Full test suite hang** — `SecItemCopyMatching` blocked on the restricted
   item inside `AdvancedSettingsWindowController.refresh()` (xctest is not the
   trusted app). Fixed by the detached status read. Full suite: **471 tests,
   0 failures, 3 skipped (pre-existing)** in ~16 s.

## Current live state

- Installed app: branch build, signed with the stable Apple Development
  identity (permissions carry over), Parakeet checkpoints bundled, login item
  enabled, running/idle.
- User's real DeepSeek key: stored in the keychain with the trusted-app ACL
  (length 35); `--verify` earlier confirmed both flash and pro reachable.
- Auto-send stays **off** until the owner reviews bench gates and enables it.
- `DEEPSEEK_API_KEY` is exported in the shell env — remember env wins over
  keychain in the app's read precedence.

## Handoff pointers

- Plan and contracts: `POST_PROCESSING_PLAN.md`
- Product contract (branch-scoped section at the end): `purpose.md`
- Setup: `./setup_deepseek_wh_hotkey.sh ["key"] [--verify]`
- Bench: `python3 Benchmarks/Performance/post-processing/run_bench.py`
- Owner's test flow: Settings → Post-processing → enable → model/thinking/
  effort → profile → dictate → review → Enter.
