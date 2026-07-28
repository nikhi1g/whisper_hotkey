# Contributing

Contributions are welcome for the Apple Silicon macOS 14+ scope.

1. Read [purpose.md](purpose.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
2. Create a focused branch.
3. Run `swift test`.
4. For app changes, run `python3 build_app.py` with a local signing identity and
   exercise the affected interaction before opening a pull request.

Keep speech recognition local, preserve normal modifier shortcuts, avoid idle
polling or resident model weights, and never commit models, recordings,
transcripts, credentials, app bundles, or build output.
