import Foundation
import XCTest
@testable import WhisperHotkeyShell

final class SoftwareUpdateInstallerTests: XCTestCase {
    func testLivePublishedUpdateWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment[
            "WHISPER_HOTKEY_LIVE_UPDATE_TEST"
        ] == "1" else {
            throw XCTSkip("Live update verification is opt-in")
        }
        let release = SoftwareUpdateRelease(
            version: "3.1.2",
            releaseURL: URL(
                string: "https://github.com/nikhi1g/whisper_hotkey/releases/tag/v3.1.2"
            )!,
            diskImageURL: URL(
                string: "https://github.com/nikhi1g/whisper_hotkey/releases/download/v3.1.2/whisper_hotkey.dmg"
            )!,
            checksumURL: URL(
                string: "https://github.com/nikhi1g/whisper_hotkey/releases/download/v3.1.2/whisper_hotkey.dmg.sha256"
            )!
        )

        let prepared = try await SoftwareUpdateInstaller().prepare(
            release: release,
            installedApplicationURL: URL(
                fileURLWithPath: "/Applications/whisper_hotkey.app",
                isDirectory: true
            ),
            installedVersion: "3.1.1"
        )
        defer {
            try? FileManager.default.removeItem(
                at: prepared.cleanupDirectoryURL
            )
        }
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: prepared.applicationURL.path
            )
        )
    }

    func testParsesOnlyExactDiskImageChecksumRecords() {
        let digest = String(repeating: "a", count: 64)
        XCTAssertEqual(
            SoftwareUpdateInstaller.expectedDigest(
                from: "\(digest)  whisper_hotkey.dmg\n"
            ),
            digest
        )
        XCTAssertNil(
            SoftwareUpdateInstaller.expectedDigest(
                from: "\(digest)  another.dmg\n"
            )
        )
        XCTAssertNil(
            SoftwareUpdateInstaller.expectedDigest(
                from: "abcd  whisper_hotkey.dmg\n"
            )
        )
    }

    func testStreamsSHA256ForDownloadedFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("download")
        try Data("whisper_hotkey".utf8).write(to: file)

        XCTAssertEqual(
            try SoftwareUpdateInstaller.sha256(of: file),
            "4a58b89dc7fe852944c265568d74f6b07e996b052891e8cf1488db95dda4284b"
        )
    }

    func testParsesDesignatedRequirementFromEitherCodesignStream() {
        let requirement =
            "identifier \"local.whisperhotkey.app\" and anchor apple generic"
        let line = Data("designated => \(requirement)\n".utf8)
        let executable = Data("Executable=/Applications/app\n".utf8)

        XCTAssertEqual(
            SoftwareUpdateInstaller.designatedRequirement(
                standardOutput: line,
                standardError: executable
            ),
            requirement
        )
        XCTAssertEqual(
            SoftwareUpdateInstaller.designatedRequirement(
                standardOutput: executable,
                standardError: line
            ),
            requirement
        )
        XCTAssertNil(
            SoftwareUpdateInstaller.designatedRequirement(
                standardOutput: executable,
                standardError: Data()
            )
        )
    }

}
