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
/// Empty since 3.4.0: every model the app can select now ships inside it, so
/// nothing is fetched at runtime. The mechanism is kept because it is the only
/// verified install path, and a future model too large to bundle would use it
/// again unchanged.
public enum ModelDownloadCatalog {
    static let baseURL =
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

    public static let downloadable: [DownloadableModel] = []

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
