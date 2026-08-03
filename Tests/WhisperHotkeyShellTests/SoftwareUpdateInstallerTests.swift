import Foundation
import XCTest
@testable import WhisperHotkeyShell

final class SoftwareUpdateInstallerTests: XCTestCase {
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
}
