# whisper_hotkey 1.0.0

The first public release of a private, low-resource, system-wide dictation agent
for Apple Silicon Macs.

Clone the repository and run:

```sh
./run.sh
```

The bootstrap installs/checks Homebrew whisper.cpp, downloads the verified Base
English model, builds and signs the app locally, installs it in `/Applications`,
launches it, and opens the macOS permission setup.

See the README for prerequisites, permissions, hotkey configuration, larger
models, terminal control, and local-signing details.

This release is distributed as source because the project does not currently
ship a notarized Developer ID binary. Models are not included in the archive.
