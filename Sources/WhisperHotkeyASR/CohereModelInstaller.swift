import Foundation
import FluidAudio
import WhisperHotkeyCore

/// Installs the Cohere Transcribe checkpoint.
///
/// Unlike Parakeet, this one is not bundled. The q8 Core ML build is roughly
/// 2.2 GB — a 1.9 GB encoder plus its decoders — which is larger than the
/// entire application including both Parakeet checkpoints and both Whisper
/// models, and past GitHub's release-asset limit. It is fetched on demand
/// through the same explicit, cancellable flow every other on-demand model
/// uses.
public enum CohereModelInstaller {
    public enum Phase: Equatable, Sendable {
        case downloading(fractionCompleted: Double)
        case compiling
    }

    /// FluidAudio publishes the q8 build under a subdirectory of its repo.
    static let repo: Repo = .cohereTranscribeCoreml

    public static func cacheDirectory() -> URL {
        MLModelConfigurationUtils.defaultModelsDirectory(for: repo)
    }

    public static func isInstalled() -> Bool {
        let directory = cacheDirectory()
        let required = [
            ModelNames.CohereTranscribe.encoderCompiledFile,
            ModelNames.CohereTranscribe.decoderCacheExternalV2CompiledFile,
            ModelNames.CohereTranscribe.vocab,
        ]
        return required.allSatisfy {
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent($0).path
            )
        }
    }

    public static func install(
        progress: @escaping @Sendable (Phase) -> Void
    ) async throws {
        do {
            try await ModelHub.download(
                repo,
                to: cacheDirectory(),
                progressHandler: { update in
                    switch update.phase {
                    case .compiling:
                        progress(.compiling)
                    default:
                        progress(
                            .downloading(
                                fractionCompleted: update.fractionCompleted
                            )
                        )
                    }
                }
            )
            try Task.checkCancellation()
        } catch {
            if isCancellation(error) {
                throw CancellationError()
            }
            throw WhisperASRError.modelInstallFailed(
                "Cohere download failed: \(error.localizedDescription)"
            )
        }
    }

    /// FluidAudio cancels the underlying URLSession task, which surfaces as
    /// NSURLErrorCancelled rather than Swift's CancellationError.
    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        var current: NSError? = error as NSError
        var visited: Set<ObjectIdentifier> = []
        while let nsError = current,
              visited.insert(ObjectIdentifier(nsError)).inserted {
            if nsError.domain == NSURLErrorDomain,
               nsError.code == NSURLErrorCancelled {
                return true
            }
            if nsError.domain == NSCocoaErrorDomain,
               nsError.code == NSUserCancelledError {
                return true
            }
            current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }
}
