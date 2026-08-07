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

    /// Where the checkpoint is read from. The copy bundled with the app wins,
    /// so a fresh install has Parakeet ready with no download at all. The
    /// writable cache is the fallback for a variant that is not bundled.
    public static func cacheDirectory(
        for variant: ParakeetVariant,
        bundle: Bundle = .main
    ) -> URL {
        if let bundled = bundledDirectory(for: variant, bundle: bundle) {
            return bundled
        }
        if variant == .unified {
            return MLModelConfigurationUtils.defaultModelsDirectory(
                for: .parakeetUnified
            )
        }
        return AsrModels.defaultCacheDirectory(for: version(for: variant))
    }

    /// The bundled checkpoint, when the app shipped with this variant and the
    /// files actually survived packaging.
    public static func bundledDirectory(
        for variant: ParakeetVariant,
        bundle: Bundle = .main
    ) -> URL? {
        // Unified is never bundled, so there is nothing to look for.
        guard variant != .unified else { return nil }
        guard let resources = bundle.resourceURL else { return nil }
        let candidate = resources
            .appendingPathComponent("ParakeetModels", isDirectory: true)
            .appendingPathComponent(
                variant.cacheFolderName,
                isDirectory: true
            )
        guard AsrModels.modelsExist(
            at: candidate,
            version: version(for: variant)
        ) else {
            return nil
        }
        return candidate
    }

    public static func isInstalled(
        _ variant: ParakeetVariant,
        bundle: Bundle = .main
    ) -> Bool {
        let directory = cacheDirectory(for: variant, bundle: bundle)
        if variant == .unified {
            // The offline path loads four bundles plus the vocabulary; the
            // streaming encoders in the same repo are not fetched.
            let names = ModelNames.ParakeetUnified.self
            return [
                names.offlineEncoderInt8File,
                names.decoderFile,
                names.jointDecisionFile,
                names.vocab,
            ].allSatisfy {
                FileManager.default.fileExists(
                    atPath: directory.appendingPathComponent($0).path
                )
            }
        }
        return AsrModels.modelsExist(
            at: directory,
            version: version(for: variant)
        )
    }

    /// Downloads and compiles the checkpoint, reporting progress. Cancelling
    /// the surrounding task cancels the install.
    public static func install(
        _ variant: ParakeetVariant,
        progress: @escaping @Sendable (Phase) -> Void
    ) async throws {
        if variant == .unified {
            try await installUnified(progress: progress)
            return
        }
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
        } catch {
            if isCancellation(error) {
                throw CancellationError()
            }
            throw WhisperASRError.modelInstallFailed(error.localizedDescription)
        }
    }

    /// Unified lives in its own repo with its own manager, so it is fetched
    /// through the generic hub rather than the TDT model loader.
    private static func installUnified(
        progress: @escaping @Sendable (Phase) -> Void
    ) async throws {
        do {
            try await ModelHub.download(
                .parakeetUnified,
                to: MLModelConfigurationUtils.defaultModelsDirectory(),
                variant: "offline",
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
            if isCancellation(error) { throw CancellationError() }
            throw WhisperASRError.modelInstallFailed(error.localizedDescription)
        }
    }

    static func version(for variant: ParakeetVariant) -> AsrModelVersion {
        switch variant {
        case .fast:
            .tdtCtc110m
        case .accurate, .unified:
            // Unified never reaches the TDT loader; this keeps the switch total.
            .v2
        }
    }

    /// Whether `error` represents a deliberate cancellation rather than a
    /// genuine failure. FluidAudio's download stack cancels the underlying
    /// `URLSessionTask` on Task cancellation (see
    /// `FileDownloader.streamDownload`'s `withTaskCancellationHandler`),
    /// which surfaces as an `NSURLErrorCancelled` error rather than Swift's
    /// `CancellationError` — so a plain `catch is CancellationError` misses
    /// it. Mirrors FluidAudio's own internal `RetryPolicy.isCancellation`,
    /// which is not exposed publicly.
    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        var current: NSError? = error as NSError
        var visited: Set<ObjectIdentifier> = []
        while let nsError = current, visited.insert(ObjectIdentifier(nsError)).inserted {
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
                return true
            }
            if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError {
                return true
            }
            current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }
}
