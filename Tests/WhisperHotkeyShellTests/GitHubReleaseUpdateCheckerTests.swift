import Foundation
import XCTest
@testable import WhisperHotkeyShell

final class GitHubReleaseUpdateCheckerTests: XCTestCase {
    func testEvaluatesNewerStableReleaseAsAvailable() throws {
        let data = Data(
            #"{"tag_name":"v3.2.0","html_url":"https://github.com/nikhi1g/whisper_hotkey/releases/tag/v3.2.0","assets":[{"name":"whisper_hotkey.dmg","browser_download_url":"https://example.com/whisper_hotkey.dmg"},{"name":"whisper_hotkey.dmg.sha256","browser_download_url":"https://example.com/whisper_hotkey.dmg.sha256"}]}"#.utf8
        )

        XCTAssertEqual(
            try GitHubReleaseUpdateChecker.evaluate(
                data: data,
                currentVersion: "3.1.0"
            ),
            .available(
                SoftwareUpdateRelease(
                    version: "3.2.0",
                    releaseURL: URL(
                        string: "https://github.com/nikhi1g/whisper_hotkey/releases/tag/v3.2.0"
                    )!,
                    diskImageURL: URL(
                        string: "https://example.com/whisper_hotkey.dmg"
                    )!,
                    checksumURL: URL(
                        string: "https://example.com/whisper_hotkey.dmg.sha256"
                    )!
                )
            )
        )
    }

    func testNewerReleaseWithoutBothAssetsIsVisibleButNotInstallable() throws {
        let data = Data(
            #"{"tag_name":"v3.2.0","html_url":"https://example.com/release","assets":[]}"#.utf8
        )

        guard case .available(let release) = try GitHubReleaseUpdateChecker
            .evaluate(data: data, currentVersion: "3.1.0")
        else {
            return XCTFail("Expected an available release")
        }
        XCTAssertEqual(release.version, "3.2.0")
        XCTAssertFalse(release.isInstallable)
    }

    func testEvaluatesSameOrOlderStableReleaseAsCurrent() throws {
        let same = Data(
            #"{"tag_name":"v3.1.0","html_url":"https://example.com/3.1.0","assets":[]}"#.utf8
        )
        let older = Data(
            #"{"tag_name":"v3.0.9","html_url":"https://example.com/3.0.9","assets":[]}"#.utf8
        )

        XCTAssertEqual(
            try GitHubReleaseUpdateChecker.evaluate(
                data: same,
                currentVersion: "3.1.0"
            ),
            .current(latestVersion: "3.1.0")
        )
        XCTAssertEqual(
            try GitHubReleaseUpdateChecker.evaluate(
                data: older,
                currentVersion: "3.1.0"
            ),
            .current(latestVersion: "3.0.9")
        )
    }

    func testRejectsMalformedReleaseMetadata() {
        XCTAssertThrowsError(
            try GitHubReleaseUpdateChecker.evaluate(
                data: Data(#"{"tag_name":"latest"}"#.utf8),
                currentVersion: "3.1.0"
            )
        )
    }
}
