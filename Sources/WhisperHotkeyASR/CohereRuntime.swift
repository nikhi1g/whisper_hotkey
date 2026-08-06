import Foundation
import FluidAudio
import WhisperHotkeyCore

/// Wraps FluidAudio's Cohere Transcribe pipeline behind the same
/// load/transcribe/release shape the other engines use.
///
/// Cohere is a 2B encoder-decoder with an autoregressive, cache-external
/// decoder. That is a different cost profile from Parakeet's transducer: it
/// emits tokens one at a time, so per-utterance latency scales with how much
/// was said rather than being effectively flat. It is offered for accuracy,
/// not for speed.
actor CohereRuntime {
    private let pipeline = CoherePipeline()
    private let audioConverter = AudioConverter()
    private var models: CoherePipeline.LoadedModels?

    var isLoaded: Bool { models != nil }

    /// Loads an already-installed checkpoint. Never downloads: a dictation
    /// must not turn into a multi-gigabyte transfer.
    func load() async throws {
        guard models == nil else { return }
        let directory = CohereModelInstaller.cacheDirectory()
        guard CohereModelInstaller.isInstalled() else {
            throw WhisperASRError.modelMissing(directory.path)
        }
        do {
            models = try await CoherePipeline.loadModels(
                encoderDir: directory,
                decoderDir: directory,
                vocabDir: directory
            )
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WhisperASRError.helperFailed("Cohere model load failed")
        }
    }

    func transcribe(audioURL: URL) async throws -> String {
        try await load()
        guard let models else {
            throw WhisperASRError.helperFailed("Cohere is not loaded")
        }
        do {
            let samples = try audioConverter.resampleAudioFile(audioURL)
            // The pipeline caps a single pass at 30 s; transcribeLong windows
            // anything longer, so it is correct for both and the recording
            // limit can stay where the user set it.
            let result = try await pipeline.transcribeLong(
                audio: samples,
                models: models
            )
            try Task.checkCancellation()
            return result.text
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WhisperASRError.helperFailed("Cohere transcription failed")
        }
    }

    func release() {
        models = nil
    }
}
