# Quick Start

`whisper_hotkey` is private, local, English dictation for Apple Silicon Macs.
Hold the selected key, speak, and release to insert text into the field that is
focused at release time. Audio and transcripts are not sent to a server.

## Install

These are the only Terminal commands required:

```sh
git clone https://github.com/nikhi1g/whisper_hotkey.git
cd whisper_hotkey
./run.sh
```

Do **not** run `run.sh` with `sudo`. The bootstrap installs user-owned models,
signing state, and the terminal controller for the account that runs it.

The first run may take several minutes. It checks the Mac, installs missing
build dependencies, downloads a verified model, builds and signs the app,
installs it, launches it, and opens the permission window. It is safe to run
again after an interrupted or completed installation.

## Requirements

- An Apple Silicon Mac (`arm64`) running macOS 14 or newer. Intel Macs and
  earlier macOS releases are not supported.
- An internet connection for the initial clone, Homebrew/Swift dependencies,
  and model download. The installed app does not make network requests.
- A normal macOS account that can install Homebrew and write to `/Applications`.
- Several gigabytes of free disk space for build products and dependencies.
  The default model itself is 141 MB.

`run.sh` handles the remaining prerequisites:

- If Xcode Command Line Tools are missing, it opens Apple's installer and waits
  for you to finish it.
- If arm64 Homebrew is missing, it starts Homebrew's official interactive
  installer. Homebrew then provides `whisper-cpp` and its local libraries.
- If the login keychain has no valid signing identity, it creates a ten-year,
  self-signed **whisper_hotkey Local Development** code-signing identity there.
  This is a stable local identity—not a Developer ID certificate—and keeps
  macOS privacy grants attached across rebuilds. An existing valid identity is
  preferred. To choose one explicitly, set
  `WHISPER_HOTKEY_CODESIGN_IDENTITY` before running the script.
- It downloads Base English to `~/.cache/whisper/` and verifies the pinned
  SHA-256 before installation. It always verifies or installs at least one
  selected model before launching the app; a mismatched model is refused.
- It resolves the pinned Swift dependency, creates a release app bundle,
  bundles the required local libraries, and signs every executable.
- It installs the app at `/Applications/whisper_hotkey.app`, installs the
  controller at `~/bin/whisper_hotkey`, launches the app, and verifies that the
  installed executable and signature match the build.

The app bundle is built locally and is not notarized for distribution. The
bootstrap-created signing certificate is only for this Mac and its login
keychain; it is not committed to the repository or copied into the app.

## Finish macOS setup

The setup window opens automatically. Complete every row:

1. Click **Request** for Microphone and allow access.
2. Open **System Settings → Privacy & Security → Accessibility** and enable
   `whisper_hotkey`.
3. Open **System Settings → Privacy & Security → Input Monitoring** and enable
   `whisper_hotkey`.
4. Approve its Login Item if macOS asks. You can turn **Open at login** off
   later in the app's Settings.

If macOS asks to quit and reopen the app after a permission change, allow it.
Reopen the setup window at any time with:

```sh
~/bin/whisper_hotkey setup
```

Check that everything is ready:

```sh
~/bin/whisper_hotkey status
```

The status should report Microphone, Accessibility, and Input Monitoring as
`granted`, and Model file and Helper as `available`.

## Dictate

Click into any editable text field, hold **Right Command**, speak, then release
it. The default **After Recording** policy loads and transcribes only after
release, so the first result can take a moment while the model starts. Very
quick taps are ignored, and ordinary Command shortcuts continue to work.

If `~/bin` is already on your `PATH`, the controller can be called simply as
`whisper_hotkey`. Its commands are:

```text
start  stop  restart  status  cancel  setup
enable-login  disable-login  logs
```

## Models and recognition engines

The default Base English model is the best first install. Other local models
trade disk space and speed for accuracy:

| Option | Model | Download | Typical reason to choose it |
| --- | --- | ---: | --- |
| `base` | Base English | 141 MB | Fastest and lightest; default |
| `small` | Small English | 465 MB | Better accuracy at moderate cost |
| `medium` | Medium English | 1.5 GB | Highest English-only accuracy; heaviest |
| `turbo` | Large-v3 Turbo Q5 | 547 MB | Strong accuracy/speed balance |

Install and select one model by rerunning the bootstrap:

```sh
./run.sh --model small
./run.sh --model medium
./run.sh --model turbo
./run.sh --all-models
```

Metal is the default engine. Optional Core ML artifacts are installed and
selected explicitly:

```sh
./run.sh --model turbo --engine coreml
./run.sh --model turbo --engine whisperkit
```

`--all-models` selects Base after installing all four. Any explicit `--model`
or `--engine` choice is persisted before the newly built app launches. Missing
models and engines remain disabled in Settings; rerun the bootstrap to add one.
The app never silently switches engines. See
[docs/MODELS.md](docs/MODELS.md) for engine and decoding details.

## Validate or troubleshoot

Validate the requested prerequisites and downloaded artifacts without changing
anything:

```sh
./run.sh --check
./run.sh --check --model small --engine coreml
```

Common recovery commands:

```sh
~/bin/whisper_hotkey restart
~/bin/whisper_hotkey setup
~/bin/whisper_hotkey logs
```

- **No permission prompt:** use the Setup buttons to open the exact System
  Settings panes, enable the installed `/Applications/whisper_hotkey.app`, then
  restart the app.
- **A permission became invalid after rebuilding:** keep using the same signing
  identity. If the identity was intentionally changed, remove the old
  `whisper_hotkey` entry from the affected Privacy & Security pane, add the
  installed app again, and regrant access.
- **A model exists but fails verification:** `run.sh` refuses to overwrite or
  use it. Move the named file out of `~/.cache/whisper/` and rerun the same
  command to download a verified copy.
- **Installation cannot write to `/Applications`:** run from the normal admin
  account that owns the Homebrew installation. Do not run the whole bootstrap
  with `sudo`, because that would install models and controller files for root.
- **The app seems absent:** it has no Dock icon. Use the controller's `status`,
  `setup`, and `restart` commands to inspect or control it.

For development, read [purpose.md](purpose.md),
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), and
[CONTRIBUTING.md](CONTRIBUTING.md).
