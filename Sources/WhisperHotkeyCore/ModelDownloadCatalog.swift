import Foundation

/// A model that is not bundled and can be fetched on demand.
public struct DownloadableModel: Equatable, Sendable {
    public let model: DictationModel
    public let url: URL
    public let sha256: String
    /// Used only to show determinate progress before the server responds.
    public let byteCount: Int64

    public var displayName: String {
        model.fileName
    }
}

public enum ModelDownloadError: Error, Equatable {
    case notDownloadable
    case transportFailed(String)
    case checksumMismatch
    case installFailed(String)
    case cancelled
}

/// Models the app can fetch after installation.
///
/// Base, Small, and Large-v3 Turbo Q5 ship inside the app, so only Medium is
/// listed: all four together exceed GitHub's 2 GB release-asset limit. The
/// source and pinned digests are the same ones `run.sh` and the release
/// workflow already trust, so a download is verified to the same standard as a
/// bundled model before anything is installed.
public enum ModelDownloadCatalog {
    static let baseURL =
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

    public static let downloadable: [DownloadableModel] = [
        DownloadableModel(
            model: .mediumEnglish,
            url: URL(string: "\(baseURL)/ggml-medium.en.bin")!,
            sha256:
                "cc37e93478338ec7700281a7ac30a10128929eb8f427dda2e865faa8f6da4356",
            byteCount: 1_533_774_781
        ),
    ]

    public static func entry(for model: DictationModel) -> DownloadableModel? {
        downloadable.first { $0.model == model }
    }

    public static func isDownloadable(_ model: DictationModel) -> Bool {
        entry(for: model) != nil
    }

    /// Where a fetched model is installed. This is already searched by
    /// `WhisperRuntimeDiscovery`, so an install needs no further wiring.
    public static func destinationURL(
        for model: DictationModel,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        WhisperHotkeyPaths.modelURL(
            for: model,
            homeDirectory: homeDirectory
        )
    }

    public static func humanReadableSize(_ byteCount: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: byteCount)
    }
}
