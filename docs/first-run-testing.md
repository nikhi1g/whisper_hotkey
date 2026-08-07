# Testing the first-run experience

`fresh_restart_application_test.sh` at the repository root returns this Mac to
the state a brand-new user's Mac is in, so the download-and-first-launch path
can be exercised for real rather than reasoned about.

It exists because a development Mac can never see the first run by accident.
Preferences record `setupCompleted = 1`, the model caches are already warm, and
the TCC database already holds Microphone, Accessibility, and Input Monitoring
grants. Reinstalling the app on top of that tests the *upgrade* path and
silently skips everything a new user actually encounters.

## Usage

```
./fresh_restart_application_test.sh              # reset, then print next steps
./fresh_restart_application_test.sh --list       # inventory only, changes nothing
./fresh_restart_application_test.sh --download   # also fetch, quarantine, mount the DMG
./fresh_restart_application_test.sh --keep-models # leave the caches in place
./fresh_restart_application_test.sh --restore    # put the newest backup back
```

Start with `--list`. It prints the exact sizes and paths it would touch and
exits without doing anything.

## What it resets, and why each one matters

| Removed | Why a new user's Mac lacks it |
| --- | --- |
| `/Applications/whisper_hotkey.app` | Nothing is installed yet |
| `~/bin/whisper_hotkey` | The CLI shim is a development convenience |
| `local.whisperhotkey.app` defaults | Backed up first. `setupCompleted` and `hasPresentedFirstRunSettings` are what suppress first run |
| `~/Library/Caches/local.whisperhotkey.app` | Whisper models, ~3.6 GB |
| `~/Library/Application Support/FluidAudio` | Parakeet checkpoints, ~2.2 GB |
| `~/Library/Caches/whisperkit-cli` | Left over from the removed WhisperKit engine, ~129 MB |
| TCC grants for Microphone, Accessibility, ListenEvent | The permission prompts are part of the first run |
| Launch Services registration | Otherwise it keeps resolving the bundle ID to the deleted bundle |

It also deletes the `local.whisperhotkey.login-item-tests.*` domains that the
Swift suite leaves behind — there were 195 of them as of 3.6.0. That is
cleanup, not part of the simulation.

The script never touches the repository, `dist/`, or the source tree.

## Your settings are recoverable

Before clearing preferences it exports them to

```
~/Library/Application Support/whisper_hotkey/fresh-test-backups/YYYYMMDD-HHMMSS.plist
```

`--restore` imports the newest one. Models are not restored — the app
re-downloads them, which is usually the point of having run the test.

## What a correct first run looks like

1. The site's download button resolves to `whisper_hotkey.zip` from the latest
   release.
2. Unzipping and dragging the app into `/Applications` works normally.
3. First launch is blocked. One approval through **System Settings > Privacy &
   Security > Open Anyway** is expected — the app is signed with a stable Apple
   Development identity and is deliberately not notarized.
4. First-run setup presents itself.
5. Microphone, Accessibility, and Input Monitoring are each requested.
6. Any model that is not bundled downloads behind the progress row inside
   Settings, not in a separate window.

Step 3 is expected, not a bug, and will remain so without a paid Apple
Developer membership.

## Always test through Finder, never through the terminal

This is the lesson of 3.6.0, and it is worth stating plainly because getting it
wrong shipped a download nobody could open.

3.6.0 switched the site to the DMG on the strength of a terminal test: a DMG
stamped with a real `com.apple.quarantine` value mounted fine under `hdiutil`,
and the app copied out of it carried only `com.apple.provenance`. Every
observation was true and the conclusion was still wrong. **`hdiutil` does not
go through Gatekeeper's verification path at all.** A Finder double-click on
the exact same file is refused with *"Apple could not verify
'whisper_hotkey.dmg' is free of malware"* and only two buttons, **Move to
Trash** and **Done** — no Open Anyway, because an unnotarized disk image cannot
be overridden the way an unnotarized app can. 3.6.2 reverted to the ZIP.

So: `curl`, `hdiutil`, `unzip`, and `open` from a shell all prove nothing about
what a user experiences. Download through a browser, open through Finder,
drag through Finder. `--download` exists only to stage the file quickly; the
opening is still yours to do by hand.
