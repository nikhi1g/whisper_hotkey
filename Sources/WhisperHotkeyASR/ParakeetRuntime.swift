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
    private var decoderLayers = 2

    init(variant: ParakeetVariant) {
        self.variant = variant
    }

    private var modelVersion: AsrModelVersion {
        switch variant {
        case .fast:
            .tdtCtc110m
        case .accurate:
            .v2
        }
    }

    var isLoaded: Bool {
        manager != nil
    }

    /// Loads the checkpoint, downloading it on first use. The download is a
    /// one-time cost paid on the first preload for a given variant.
    func load() async throws {
        guard manager == nil else { return }
        do {
            let loaded = try await AsrModels.downloadAndLoad(
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
        manager = nil
        models = nil
    }
}
