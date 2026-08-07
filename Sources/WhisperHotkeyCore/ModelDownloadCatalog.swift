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
/// Turbo returned here in 3.7.0. Parakeet Unified took its place in the bundle
/// on the strength of a measured win in both accuracy and median latency, and
/// shipping both would have pushed the download past 1.8 GB against GitHub's
/// 2 GB asset ceiling. Turbo stays fully selectable; choosing it fetches the
/// checkpoint through the progress panel and verifies the pinned checksum
/// before installing.
public enum ModelDownloadCatalog {
    static let baseURL =
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

    public static let downloadable: [DownloadableModel] = [
        DownloadableModel(
            model: .largeV3TurboQ5,
            url: URL(
                string: "\(baseURL)/ggml-large-v3-turbo-q5_0.bin"
            )!,
            sha256:
                "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2",
            byteCount: 574_041_195
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
