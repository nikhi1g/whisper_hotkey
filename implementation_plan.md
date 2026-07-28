Yes—this already exists locally, and your Mac has the core pieces installed.

- `whisper.cpp`’s `whisper-cli` and `whisper-stream`
- Local English Whisper Small (465 MB) and Base (141 MB) models
- Metal-capable Apple Silicon execution

BookCLI already uses that exact stack for local dictation with a live partial-transcript preview. It is currently scoped to BookCLI, not system-wide.

For a seamless “hold hotkey → see live text → release → insert at cursor in any app” experience, use an existing macOS dictation app rather than extending BookCLI. My recommendation is:

1. **Try OpenDictator first** — free, open source (MIT), Apple Silicon, global customizable hotkey, floating live preview, and local insertion at the current cursor. It supports WhisperKit or very-fast Parakeet. [OpenDictator](https://www.opendictator.app/)

2. **If you specifically want to reuse whisper.cpp**, try [local-whisper](https://github.com/luisalima/local-whisper). It is MIT-licensed, uses whisper.cpp, gives a streaming overlay, a global hold-to-talk shortcut, local-only processing, and uses Hammerspoon for the system-wide hotkey/paste integration.

3. **For the most polished open-source feature set**, [TypeWhisper](https://github.com/TypeWhisper/typewhisper-mac) has global push-to-talk, live streaming preview, per-app workflows—including terminal handling—and cursor insertion. It can use local WhisperKit, Parakeet, and other local engines.

VoiceInk is another mature open-source option with configurable global shortcuts and local transcription, though its convenience distribution is commercial. [VoiceInk](https://github.com/Beingpax/VoiceInk)

What needs to exist technically:

- A menu-bar app that launches at login.
- Microphone permission.
- Accessibility permission, required to listen for a global hotkey and insert/paste into the focused app.
- A floating non-activating overlay for the live preview.
- Local streaming ASR (WhisperKit is generally best for live partials; your installed `whisper-stream` is viable too).
- Robust insertion: accessibility text insertion when available, then clipboard paste as a fallback.
- Care around password/secure-entry fields: macOS deliberately blocks automation/hotkeys in some contexts.

So: no cloud subscription or new model download is strictly needed to prove the workflow. Your installed `whisper-stream` plus `ggml-small.en.bin` can power a small native/Hammerspoon implementation now. But I’d personally trial OpenDictator and TypeWhisper first; if either feels right, there’s little reason to build and maintain another dictation app. MacWhisper also has a global overlay, but that feature requires its paid tier. [MacWhisper Global](https://docs.macwhisper.com/article/16-global)
