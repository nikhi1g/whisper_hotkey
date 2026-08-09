import Foundation
import XCTest
@testable import WhisperHotkeyASR

final class AudioLeaseTests: XCTestCase {
    func testPrivateLeaseDefersCleanupUntilBorrowedSpanReleases() throws {
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }

        let lease = try WhisperAudioLease.create(
            in: parent,
            maximumSpanDuration: 1
        )
        let directory = lease.directoryURL
        XCTAssertEqual(try permissions(of: directory), 0o700)

        try Data([0]).write(to: lease.canonicalURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: lease.canonicalURL.path
        )
        XCTAssertEqual(try permissions(of: lease.canonicalURL), 0o600)

        var span: WhisperAudioSpan? = try lease.makeSpan(
            startSample: 0,
            endSample: 16_000,
            sampleRate: 16_000
        )
        XCTAssertEqual(span?.url, lease.canonicalURL)
        XCTAssertEqual(span?.sampleCount, 16_000)
        XCTAssertEqual(try XCTUnwrap(span).duration, 1, accuracy: 0.000_001)

        lease.cancel()
        XCTAssertTrue(lease.isFinished)
        XCTAssertFalse(
            lease.isCleaned,
            "A borrowed span must keep canonical audio available."
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertThrowsError(
            try lease.makeSpan(
                startSample: 0,
                endSample: 1,
                sampleRate: 16_000
            )
        ) { error in
            XCTAssertEqual(error as? WhisperAudioLeaseError, .leaseFinished)
        }

        span = nil
        XCTAssertTrue(lease.isCleaned)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testSpanBoundsAreValidatedAndBounded() throws {
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let lease = try WhisperAudioLease.create(
            in: parent,
            maximumSpanDuration: 1
        )
        defer { lease.finish() }

        XCTAssertThrowsError(
            try lease.makeSpan(startSample: 0, endSample: 0, sampleRate: 16_000)
        ) { error in
            XCTAssertEqual(error as? WhisperAudioLeaseError, .invalidSpanBounds)
        }
        XCTAssertThrowsError(
            try lease.makeSpan(startSample: -1, endSample: 1, sampleRate: 16_000)
        ) { error in
            XCTAssertEqual(error as? WhisperAudioLeaseError, .invalidSpanBounds)
        }
        XCTAssertThrowsError(
            try lease.makeSpan(startSample: 0, endSample: 1, sampleRate: 0)
        ) { error in
            XCTAssertEqual(error as? WhisperAudioLeaseError, .invalidSpanBounds)
        }
        XCTAssertThrowsError(
            try lease.makeSpan(
                startSample: 0,
                endSample: 16_001,
                sampleRate: 16_000
            )
        ) { error in
            XCTAssertEqual(error as? WhisperAudioLeaseError, .spanTooLong)
        }
        XCTAssertThrowsError(
            try lease.makeSpan(
                startSample: 0,
                endSample: Int64.max,
                sampleRate: 16_000
            )
        ) { error in
            XCTAssertEqual(error as? WhisperAudioLeaseError, .spanTooLong)
        }
    }

    func testChildAudioUsesPrivatePermissionsAndRetiresExactlyOnce() throws {
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }

        let lease = try WhisperAudioLease.create(in: parent)
        let child = try lease.makeChildFile()
        let childDirectory = child.url.deletingLastPathComponent()
        XCTAssertEqual(try permissions(of: childDirectory), 0o700)

        try Data([0]).write(to: child.url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: child.url.path
        )
        XCTAssertEqual(try permissions(of: child.url), 0o600)

        lease.finish()
        XCTAssertTrue(FileManager.default.fileExists(atPath: childDirectory.path))

        child.retire()
        child.delete()
        child.delete()

        XCTAssertFalse(FileManager.default.fileExists(atPath: childDirectory.path))
        XCTAssertTrue(lease.isCleaned)
        XCTAssertFalse(FileManager.default.fileExists(atPath: lease.directoryURL.path))
    }

    func testCancellationWaitsForEveryChildHolderBeforeDeletingSession() throws {
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }

        let lease = try WhisperAudioLease.create(in: parent)
        let canonical = lease.makeCanonicalFile()
        let childHolder = try XCTUnwrap(canonical.acquireLeaseHolder())

        lease.cancel()
        canonical.delete()
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: lease.directoryURL.path),
            "The outstanding child holder must prevent use-after-delete."
        )

        childHolder.release()
        XCTAssertTrue(lease.isCleaned)
        XCTAssertFalse(FileManager.default.fileExists(atPath: lease.directoryURL.path))
    }

    func testRapidSessionCancelStartCleanupDoesNotReuseOldLease() throws {
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }

        var directories = Set<URL>()
        for _ in 0..<32 {
            let lease = try WhisperAudioLease.create(in: parent)
            let canonical = lease.makeCanonicalFile()
            directories.insert(lease.directoryURL)

            lease.cancel()
            canonical.delete()
            XCTAssertTrue(lease.isCleaned)
        }

        XCTAssertEqual(directories.count, 32)
        for directory in directories {
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        }
    }

    func testNewSessionIsIndependentAfterCancelledSessionReleasesItsSpan() throws {
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }

        let first = try WhisperAudioLease.create(in: parent)
        var staleSpan: WhisperAudioSpan? = try first.makeSpan(
            startSample: 0,
            endSample: 1,
            sampleRate: 16_000
        )
        first.cancel()

        let second = try WhisperAudioLease.create(in: parent)
        var currentSpan: WhisperAudioSpan? = try second.makeSpan(
            startSample: 0,
            endSample: 1,
            sampleRate: 16_000
        )
        XCTAssertNotEqual(first.directoryURL, second.directoryURL)
        XCTAssertNotEqual(staleSpan?.url, currentSpan?.url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.directoryURL.path))

        staleSpan = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.directoryURL.path))
        second.cancel()
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.directoryURL.path))
        currentSpan = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.directoryURL.path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "whisper_hotkey-audio-lease-test-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        return directory
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (try XCTUnwrap(
            (attributes[.posixPermissions] as? NSNumber)?.intValue
        )) & 0o777
    }
}
