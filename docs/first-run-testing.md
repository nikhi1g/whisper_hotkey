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

1. The site's download button resolves to `whisper_hotkey.dmg` from the latest
   stable release.
2. Safari downloads the disk image with quarantine metadata.
3. Finder opens the disk image without **Move to Trash** or **Open Anyway**;
   dragging the app into `/Applications` works normally.
4. The app launches from Applications after Gatekeeper validates its Developer
   ID signature and stapled notarization ticket.
5. First-run setup presents itself.
6. Microphone, Accessibility, and Input Monitoring are each requested.
7. Any model that is not bundled downloads behind the progress row inside
   Settings, not in a separate window.

## Always test through Finder, never only through the terminal

This is the lesson of 3.6.0, and it remains a release gate. That release
switched the site to an unnotarized DMG after a quarantined image mounted
successfully with `hdiutil`. Finder rejected the same image before mounting,
with only **Move to Trash** and **Done**. `hdiutil` does not exercise
Gatekeeper's Finder path.

The stable DMG is now Developer ID-signed, notarized, and stapled specifically
to make that browser-to-Finder path work. `curl`, `hdiutil`, and `open` remain
useful integrity checks but are not user-path evidence. Download through a
browser, open through Finder, drag through Finder, and launch from Applications.
`--download` exists only to stage the file quickly; the opening is still yours
to do by hand.
