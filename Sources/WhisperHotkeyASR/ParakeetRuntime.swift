import Foundation
import FluidAudio
import WhisperHotkeyCore

/// Wraps FluidAudio's Parakeet models behind the same load/transcribe/release
/// shape the other engines use.
///
/// Parakeet is a FastConformer transducer, not an autoregressive decoder, so
/// three things differ from the whisper engines and are handled here rather
/// than leaking into `WhisperRecognition`:
///
/// - There is no beam search, so `DecodingProfile` has nothing to select.
/// - There is no prompt, so the internal dictionary and the Pause Mode context
///   tail cannot bias the decode; both are dropped before the call.
/// - Models are fetched and cached by FluidAudio under Application Support
///   rather than `~/.cache/whisper`, so there is no bundled file to discover.
actor ParakeetRuntime {
    private let variant: ParakeetVariant
    private var models: AsrModels?
    private var manager: AsrManager?
    /// Unified is a different FluidAudio manager with its own decoder, so it
    /// is held separately rather than bent into the TDT one.
    private var unifiedManager: UnifiedAsrManager?
    private let audioConverter = AudioConverter()
    private var decoderLayers = 2

    init(variant: ParakeetVariant) {
        self.variant = variant
    }

    private var modelVersion: AsrModelVersion {
        ParakeetModelInstaller.version(for: variant)
    }

    var isLoaded: Bool {
        manager != nil || unifiedManager != nil
    }

    /// Loads an already-installed checkpoint.
    ///
    /// This never downloads. A dictation that had to fetch several hundred
    /// megabytes first showed a Transcribing badge for the whole transfer, with
    /// no progress and no timeout, which is indistinguishable from a hang. The
    /// fetch is an explicit, cancellable step at selection time instead; see
    /// `ParakeetModelInstaller`.
    func load() async throws {
        if variant == .unified {
            try await loadUnified()
            return
        }
        guard manager == nil else { return }
        let directory = ParakeetModelInstaller.cacheDirectory(for: variant)
        guard ParakeetModelInstaller.isInstalled(variant) else {
            throw WhisperASRError.modelMissing(directory.path)
        }
        do {
            let loaded = try await AsrModels.load(
                from: directory,
                version: modelVersion
            )
            try Task.checkCancellation()
            let runtime = AsrManager(config: .default)
            try await runtime.loadModels(loaded)
            models = loaded
            manager = runtime
            decoderLayers = await runtime.decoderLayerCount
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WhisperASRError.helperFailed(
                "Parakeet model load failed"
            )
        }
    }

    func transcribe(audioURL: URL) async throws -> String {
        try await load()
        if variant == .unified {
            guard let unifiedManager else {
                throw WhisperASRError.helperFailed("Parakeet is not loaded")
            }
            do {
                let samples = try audioConverter.resampleAudioFile(audioURL)
                // A fresh decoder state per utterance keeps one dictation from
                // carrying transducer state into the next.
                try await unifiedManager.reset()
                let text = try await unifiedManager.transcribe(samples)
                try Task.checkCancellation()
                return text
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw WhisperASRError.helperFailed(
                    "Parakeet transcription failed"
                )
            }
        }
        guard let manager else {
            throw WhisperASRError.helperFailed("Parakeet is not loaded")
        }
        do {
            // A fresh decoder state per utterance keeps one dictation from
            // carrying transducer state into the next.
            var state = try TdtDecoderState(decoderLayers: decoderLayers)
            let result = try await manager.transcribe(
                audioURL,
                decoderState: &state
            )
            try Task.checkCancellation()
            return result.text
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WhisperASRError.helperFailed(
                "Parakeet transcription failed"
            )
        }
    }

    func release() async {
        if let manager {
            await manager.cleanup()
        }
        if let unifiedManager {
            await unifiedManager.cleanup()
        }
        manager = nil
        unifiedManager = nil
        models = nil
    }

    /// Loads the already-installed Unified checkpoint. Like the TDT path this
    /// never downloads; the install is an explicit step at selection time.
    private func loadUnified() async throws {
        guard unifiedManager == nil else { return }
        let directory = ParakeetModelInstaller.cacheDirectory(for: variant)
        guard ParakeetModelInstaller.isInstalled(variant) else {
            throw WhisperASRError.modelMissing(directory.path)
        }
        do {
            let runtime = UnifiedAsrManager()
            try await runtime.loadModels(from: directory)
            try Task.checkCancellation()
            unifiedManager = runtime
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WhisperASRError.helperFailed("Parakeet model load failed")
        }
    }
}
