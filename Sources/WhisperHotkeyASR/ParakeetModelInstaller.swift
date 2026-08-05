import Foundation
import FluidAudio
import WhisperHotkeyCore

/// Installs a Parakeet checkpoint as an explicit, observable step.
///
/// The whisper models that do not ship in the download are fetched from
/// Settings with a progress panel and a Cancel button. Parakeet used to fetch
/// itself lazily inside the first dictation instead, which meant a few hundred
/// megabytes downloaded behind a Transcribing badge with no progress, no
/// cancel, and no timeout. This gives Parakeet the same explicit treatment.
public enum ParakeetModelInstaller {
    /// A step of an install, in the order the panel reports them.
    public enum Phase: Equatable, Sendable {
        case downloading(fractionCompleted: Double)
        /// Core ML compiles the model for this Mac after the transfer. It has
        /// no byte count, so the panel shows an indeterminate message.
        case compiling
    }

    public static func cacheDirectory(for variant: ParakeetVariant) -> URL {
        AsrModels.defaultCacheDirectory(for: version(for: variant))
    }

    public static func isInstalled(_ variant: ParakeetVariant) -> Bool {
        AsrModels.modelsExist(
            at: cacheDirectory(for: variant),
            version: version(for: variant)
        )
    }

    /// Downloads and compiles the checkpoint, reporting progress. Cancelling
    /// the surrounding task cancels the install.
    public static func install(
        _ variant: ParakeetVariant,
        progress: @escaping @Sendable (Phase) -> Void
    ) async throws {
        do {
            _ = try await AsrModels.download(
                version: version(for: variant),
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
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WhisperASRError.helperFailed(
                "Parakeet download failed: \(error.localizedDescription)"
            )
        }
    }

    static func version(for variant: ParakeetVariant) -> AsrModelVersion {
        switch variant {
        case .fast:
            .tdtCtc110m
        case .accurate:
            .v2
        }
    }
}
