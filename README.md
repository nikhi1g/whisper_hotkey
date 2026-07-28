# whisper_hotkey

`whisper_hotkey` is a private, headless macOS push-to-talk utility. Hold the
dedicated Right Command key, speak, and release to insert local Base English
Whisper transcription at the current text selection.

The MVP targets this Apple Silicon Mac and uses:

- `/opt/homebrew/bin/whisper-cli`
- `/opt/homebrew/opt/whisper-cpp/`
- `~/.cache/whisper/ggml-base.en.bin`

It makes no network requests and keeps no audio or transcript history.

## Development

```sh
swift build
swift test
```

The desktop sandbox may require `CLANG_MODULE_CACHE_PATH` and
`SWIFTPM_MODULECACHE_OVERRIDE` to point inside `.build/module-cache`.

## Bundle and install

The production-style bundle requires the same stable signing identity policy as
BookCLI:

```sh
python3 build_app.py
python3 install.py
```

The installer places the bundle at `/Applications/whisper_hotkey.app` and the
controller at `~/bin/whisper_hotkey`.

Run `whisper_hotkey setup` for permissions, or use `whisper_hotkey status`,
`start`, `stop`, `restart`, `cancel`, `enable-login`, `disable-login`, and
`logs`.
