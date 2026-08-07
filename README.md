# Quick Start

`whisper_hotkey` is private, local, English dictation for Apple Silicon Macs.
Hold the selected key, speak, and release to insert text into the field that is
focused at release time. Audio and transcripts are not sent to a server.

## Install the Mac app

The fastest path is the signed, self-contained download:

1. **[Download the latest release](https://github.com/nikhi1g/whisper_hotkey/releases/latest)**
   and pick `whisper_hotkey.zip`.
2. Unzip it and drag **whisper_hotkey** into **Applications**.
3. Open `/Applications/whisper_hotkey.app`. macOS blocks the first launch with
   *"Apple could not verify …"*; click **Done**, then open **System Settings →
   Privacy & Security**, scroll to **Security**, and click **Open Anyway** next
   to `whisper_hotkey`. This is a one-time step, explained below.
4. The app has no Dock icon; look for its waveform icon in the menu bar and
   complete the setup window.

The download includes the pinned, SHA-256-verified Base English model, so no
compiler, Homebrew installation, model download, or Terminal command is
required. macOS still requires you to grant Microphone, Accessibility, and Input
Monitoring access because those permissions cannot be pre-approved by an
installer.

### Why macOS blocks the first launch

The app is signed with a stable Apple Development identity, but it is **not
notarized**. Notarization requires a paid Apple Developer Program membership,
which this project does not have, so Gatekeeper cannot verify the build on its
own and asks you to approve it once. Right-click → Open no longer bypasses this
on macOS 15 and later; the Privacy & Security path above is the supported one.

Every release publishes a checksum, so you can confirm you received the exact
published file before you approve it:

```sh
shasum -a 256 -c whisper_hotkey.zip.sha256
```

The `.dmg` asset in each release contains the same app and exists for the in-app
updater. Downloading it in a browser is blocked at mount time on macOS 15 and
later, which is why the ZIP is the recommended download.

Visit the product page at
[nikhi1g.github.io/whisper_hotkey](https://nikhi1g.github.io/whisper_hotkey/)
or inspect every part of the build in this repository.

## Build from source

These are the only Terminal commands required:

```sh
git clone https://github.com/nikhi1g/whisper_hotkey.git
cd whisper_hotkey
./run.sh
```

Do **not** run `run.sh` with `sudo`. The bootstrap installs user-owned models,
signing state, and the terminal controller for the account that runs it.

The first source build may take several minutes. It checks the Mac, installs missing
build dependencies, downloads a verified model, builds and signs the app,
installs it, launches it, and opens the permission window. The script remains
attached: complete setup, return to Terminal, and press Return when prompted.
It rechecks every requirement and exits only after the model, helper, Login
Item, and all three permissions are verified. It is safe to run again after an
interrupted or completed installation.

## Requirements for a source build

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

The app bundle produced by `run.sh` is built and signed on your own Mac, so
Gatekeeper never questions it and the Open Anyway step above does not apply. The
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

If you installed from source, return to Terminal and press Return after
completing the rows. If anything is still missing, `run.sh` prints the current
status, reopens Setup, and waits for you again. Once every requirement is
ready, it prints `Setup verified` and finishes installation. A download
installation uses the same setup window without the attached Terminal
verification loop.

If macOS asks to quit and reopen the app after a permission change, allow it.
The menu-bar icon can reopen Setup at any time. A source installation also
installs a terminal controller, so you can use:

```sh
~/bin/whisper_hotkey setup
```

Check a source installation from Terminal:

```sh
~/bin/whisper_hotkey status
```

The status should report Microphone, Accessibility, and Input Monitoring as
`granted`, and Model file and Helper as `available`.

## Dictate

Click into any editable text field, hold **Right Option**, speak, then release
it. A fresh install on a Mac with at least 8 GB selects **Decode While
Speaking** for the shortest completion latency. Lower-memory Macs select
**After Recording** to preserve memory. Very quick taps are ignored, and
ordinary Option shortcuts continue to work.

For source installations, if `~/bin` is already on your `PATH`, the controller can be called simply as
`whisper_hotkey`. Its commands are:

```text
start  stop  restart  status  cancel  setup
verify-setup  enable-login  disable-login  logs
```

`verify-setup` prints the same readiness details as `status`, but returns a
nonzero exit status until the complete setup is ready. `run.sh` uses it for the
human-in-the-loop verification gate.

## Recognition

Recognition leads with one choice, not four. Settings offers **Fast** and
**Accurate**, with the individual controls behind them shown alongside.

| Preset | Runs | Word error rate | Latency |
| --- | --- | ---: | ---: |
| Fast | Parakeet 110M | 3.88% | 34 ms |
| Accurate | Parakeet 0.6B | 2.62% | 56 ms |

Both presets run NVIDIA Parakeet on the Neural Engine, and both checkpoints
ship inside the app, so the best configuration on accuracy and latency is
available on a fresh install with no download. Measured on this repository's
own benchmark; reproduce with the harness in `Benchmarks/Parakeet/`.

There are only two presets because a third would have nowhere to sit. Parakeet
0.6B is simultaneously the most accurate option and answers in well under a
tenth of a second, so a "balanced" tier would resolve to the same
configuration as an "most accurate" one.

### Individual controls

Model, decoding profile, and processing mode sit directly below the presets.
They used to fold behind an "Advanced Options" disclosure; the fold hid the
only explanation for what a preset had done, and a setting a user cannot see
is a setting they cannot trust. A configuration matching neither preset
reports **Custom**.

| Option | Model | Size | Reason to choose it |
| --- | --- | ---: | --- |
| Parakeet Accurate | `parakeet-tdt-0.6b-v2` | 443 MB | Default; best on both axes |
| Parakeet Fast | `parakeet-tdt-ctc-110m` | 217 MB | Lowest latency and memory |
| Parakeet Unified | `parakeet-unified-en-0.6b` | 594 MB | Most accurate; on-demand download |
| Whisper Turbo | `ggml-large-v3-turbo-q5_0.bin` | 547 MB | Supports the internal dictionary |
| Cohere Transcribe | `cohere-transcribe-03-2026` | 2.4 GB | Best on clean speech; ~11x slower |

Whisper Turbo remains because Parakeet is a transducer: it accepts no prompt,
so the internal dictionary and Pause Mode context only bias Whisper. Whisper
Base left the list in 3.5.7 — Parakeet Fast is smaller, faster and more
accurate, and it is bundled. Small and Medium English were retired in 3.4.1.

The bundled options ship inside the app; Unified and Cohere are fetched only
when selected.

```sh
./run.sh --model base
./run.sh --model turbo
./run.sh --engine parakeet
```

Any explicit `--model` or `--engine` choice is persisted before the newly built
app launches. The app never silently switches engines. See
[docs/MODELS.md](docs/MODELS.md) for engine and decoding details.

## Validate or troubleshoot

Validate the requested prerequisites and downloaded artifacts without changing
anything:

```sh
./run.sh --check
./run.sh --check --model turbo --engine parakeet
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
[CONTRIBUTING.md](CONTRIBUTING.md). Maintainers can find the Pages, signing, and
release procedure in
[docs/DISTRIBUTION.md](docs/DISTRIBUTION.md).
