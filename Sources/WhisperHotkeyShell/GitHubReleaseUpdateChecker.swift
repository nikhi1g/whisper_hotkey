import Foundation
import WhisperHotkeyCore

public struct SoftwareUpdateRelease: Equatable, Sendable {
    public let version: String
    public let releaseURL: URL
    public let diskImageURL: URL?
    public let checksumURL: URL?

    public init(
        version: String,
        releaseURL: URL,
        diskImageURL: URL?,
        checksumURL: URL?
    ) {
        self.version = version
        self.releaseURL = releaseURL
        self.diskImageURL = diskImageURL
        self.checksumURL = checksumURL
    }

    public var isInstallable: Bool {
        diskImageURL != nil && checksumURL != nil
    }
}

public enum SoftwareUpdateCheckResult: Equatable, Sendable {
    case current(latestVersion: String)
    case available(SoftwareUpdateRelease)
}

public enum SoftwareUpdateStatus: Equatable, Sendable {
    case idle
    case checking
    case current
    case available(version: String, installable: Bool)
    case downloading
    case verifying
    case installing
    case failed

    public var displayText: String {
        switch self {
        case .idle:
            ""
        case .checking:
            "Checking..."
        case .current:
            "Up to date"
        case .available(let version, _):
            "v\(version) available"
        case .downloading:
            "Downloading..."
        case .verifying:
            "Verifying..."
        case .installing:
            "Restarting..."
        case .failed:
            "Unable to check"
        }
    }

    public var isBusy: Bool {
        switch self {
        case .checking, .downloading, .verifying, .installing:
            true
        case .idle, .current, .available, .failed:
            false
        }
    }
}

public protocol SoftwareUpdateChecking: Sendable {
    func check(currentVersion: String) async throws
        -> SoftwareUpdateCheckResult
}

public actor GitHubReleaseUpdateChecker: SoftwareUpdateChecking {
    private static let latestReleaseURL = URL(
        string:
            "https://api.github.com/repos/nikhi1g/whisper_hotkey/releases/latest"
    )!

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func check(currentVersion: String) async throws
        -> SoftwareUpdateCheckResult
    {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.timeoutInterval = 10
        request.setValue(
            "application/vnd.github+json",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(
            "whisper_hotkey/\(currentVersion)",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode)
        else {
            throw URLError(.badServerResponse)
        }
        return try Self.evaluate(data: data, currentVersion: currentVersion)
    }

    static func evaluate(
        data: Data,
        currentVersion: String
    ) throws -> SoftwareUpdateCheckResult {
        struct Release: Decodable {
            struct Asset: Decodable {
                let name: String
                let browserDownloadURL: URL

                enum CodingKeys: String, CodingKey {
                    case name
                    case browserDownloadURL = "browser_download_url"
                }
            }

            let tagName: String
            let htmlURL: URL
            let assets: [Asset]

            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
                case htmlURL = "html_url"
                case assets
            }
        }

        let release = try JSONDecoder().decode(Release.self, from: data)
        guard let installed = SemanticVersion(currentVersion),
              let latest = SemanticVersion(release.tagName)
        else {
            throw URLError(.cannotParseResponse)
        }
        let normalizedLatest = release.tagName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .drop(while: { $0.lowercased() == "v" })
        if installed < latest {
            let diskImageURL = release.assets.first {
                $0.name == "whisper_hotkey.dmg"
            }?.browserDownloadURL
            let checksumURL = release.assets.first {
                $0.name == "whisper_hotkey.dmg.sha256"
            }?.browserDownloadURL
            return .available(
                SoftwareUpdateRelease(
                    version: String(normalizedLatest),
                    releaseURL: release.htmlURL,
                    diskImageURL: diskImageURL,
                    checksumURL: checksumURL
                )
            )
        }
        return .current(latestVersion: String(normalizedLatest))
    }
}
