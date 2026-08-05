import Foundation
import XCTest
@testable import WhisperHotkeyCore

final class ApplicationInstallLocationTests: XCTestCase {
    private let home = URL(
        fileURLWithPath: "/Users/tester",
        isDirectory: true
    )

    func testSystemApplicationsBundleNeedsNoOffer() {
        let location = ApplicationInstallLocator.locate(
            bundleURL: URL(fileURLWithPath: "/Applications/whisper_hotkey.app"),
            homeDirectory: home
        )
        XCTAssertEqual(location, .installed)
        XCTAssertFalse(location.needsInstallOffer)
    }

    func testUserApplicationsBundleNeedsNoOffer() {
        let location = ApplicationInstallLocator.locate(
            bundleURL: home
                .appendingPathComponent("Applications")
                .appendingPathComponent("whisper_hotkey.app"),
            homeDirectory: home
        )
        XCTAssertEqual(location, .installed)
    }

    /// Directory URLs spelled with and without a trailing slash name the same
    /// place. Comparing URLs rather than paths made them unequal, which put an
    /// app already in ~/Applications into `.unmanaged`.
    func testDirectoryURLSpellingDoesNotChangeTheLocation() {
        for isDirectory in [true, false] {
            let location = ApplicationInstallLocator.locate(
                bundleURL: home
                    .appendingPathComponent("Applications", isDirectory: true)
                    .appendingPathComponent(
                        "whisper_hotkey.app",
                        isDirectory: isDirectory
                    ),
                homeDirectory: URL(
                    fileURLWithPath: home.path,
                    isDirectory: isDirectory
                )
            )
            XCTAssertEqual(location, .installed)
        }
    }

    func testDownloadsBundleIsUnmanaged() {
        let location = ApplicationInstallLocator.locate(
            bundleURL: home
                .appendingPathComponent("Downloads")
                .appendingPathComponent("whisper_hotkey.app"),
            homeDirectory: home
        )
        XCTAssertEqual(location, .unmanaged)
        XCTAssertTrue(location.needsInstallOffer)
    }

    /// A quarantined download opened from Finder runs from a read-only shadow
    /// copy, which must be offered an install even though it cannot be moved.
    func testTranslocatedBundleIsDetected() {
        let translocated = URL(
            fileURLWithPath:
                "/private/var/folders/6z/T/AppTranslocation/E57CBD7F/d/whisper_hotkey.app"
        )
        let location = ApplicationInstallLocator.locate(
            bundleURL: translocated,
            homeDirectory: home
        )
        XCTAssertEqual(location, .translocated)
        XCTAssertTrue(location.needsInstallOffer)
    }

    /// A nested folder inside Applications is not an install; only the folder
    /// itself counts, so a bundle one level deeper still gets the offer.
    func testNestedFolderInsideApplicationsIsUnmanaged() {
        let location = ApplicationInstallLocator.locate(
            bundleURL: URL(
                fileURLWithPath: "/Applications/Utilities/whisper_hotkey.app"
            ),
            homeDirectory: home
        )
        XCTAssertEqual(location, .unmanaged)
    }

    func testDestinationPreservesBundleName() {
        let destination = ApplicationInstallLocator.destinationURL(
            for: home
                .appendingPathComponent("Downloads")
                .appendingPathComponent("whisper_hotkey.app")
        )
        XCTAssertEqual(
            destination.path,
            "/Applications/whisper_hotkey.app"
        )
    }
}
