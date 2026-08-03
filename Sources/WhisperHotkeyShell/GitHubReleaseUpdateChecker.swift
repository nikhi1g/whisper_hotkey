import Foundation
import WhisperHotkeyCore

public enum SoftwareUpdateCheckResult: Equatable, Sendable {
    case current(latestVersion: String)
    case available(latestVersion: String, releaseURL: URL)
}

public enum SoftwareUpdateStatus: Equatable, Sendable {
    case idle
    case checking
    case current
    case available(version: String)
    case failed

    public var displayText: String {
        switch self {
        case .idle:
            ""
        case .checking:
            "Checking..."
        case .current:
            "Up to date"
        case .available(let version):
            "v\(version) available"
        case .failed:
            "Unable to check"
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
            let tagName: String
            let htmlURL: URL

            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
                case htmlURL = "html_url"
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
            return .available(
                latestVersion: String(normalizedLatest),
                releaseURL: release.htmlURL
            )
        }
        return .current(latestVersion: String(normalizedLatest))
    }
}
