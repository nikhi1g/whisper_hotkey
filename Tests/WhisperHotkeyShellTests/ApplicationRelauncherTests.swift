import Foundation
import XCTest
@testable import WhisperHotkeyShell

final class ApplicationRelauncherTests: XCTestCase {
    @MainActor
    func testSchedulesBundledLauncherToWaitForCurrentProcess() throws {
        let expectedURL = URL(fileURLWithPath: "/Applications/Test.app/launcher")
        var launchedURL: URL?
        var launchedArguments: [String] = []
        let relauncher = ApplicationRelauncher(
            launcherURL: expectedURL,
            processIdentifier: 42
        ) { url, arguments in
            launchedURL = url
            launchedArguments = arguments
        }

        try relauncher.schedule()

        XCTAssertEqual(launchedURL, expectedURL)
        XCTAssertEqual(launchedArguments, ["--wait-for-pid", "42"])
    }

    @MainActor
    func testRefusesMissingLauncher() {
        let relauncher = ApplicationRelauncher(
            launcherURL: nil,
            processIdentifier: 42,
            launch: { _, _ in
                XCTFail("Missing launcher must not be invoked")
            }
        )

        XCTAssertThrowsError(try relauncher.schedule()) { error in
            XCTAssertEqual(
                error as? ApplicationRelaunchError,
                .missingBundledLauncher
            )
        }
    }

    @MainActor
    func testRefusesInvalidProcessIdentifier() {
        let relauncher = ApplicationRelauncher(
            launcherURL: URL(fileURLWithPath: "/launcher"),
            processIdentifier: 0,
            launch: { _, _ in
                XCTFail("Invalid process identifier must not launch")
            }
        )

        XCTAssertThrowsError(try relauncher.schedule()) { error in
            XCTAssertEqual(
                error as? ApplicationRelaunchError,
                .invalidProcessIdentifier
            )
        }
    }

    @MainActor
    func testSchedulesVerifiedUpdateBeforeRelaunch() throws {
        let launcherURL = URL(fileURLWithPath: "/Applications/Test.app/launcher")
        let cleanupURL = URL(
            fileURLWithPath: "/private/tmp/update-1",
            isDirectory: true
        )
        let update = PreparedSoftwareUpdate(
            applicationURL: cleanupURL.appendingPathComponent(
                "whisper_hotkey.app",
                isDirectory: true
            ),
            cleanupDirectoryURL: cleanupURL
        )
        var launchedArguments: [String] = []
        let relauncher = ApplicationRelauncher(
            launcherURL: launcherURL,
            processIdentifier: 42
        ) { _, arguments in
            launchedArguments = arguments
        }

        try relauncher.scheduleUpdate(update, version: "3.2.0")

        XCTAssertEqual(
            launchedArguments,
            [
                "--install-update", update.applicationURL.path,
                "--cleanup-directory", cleanupURL.path,
                "--version", "3.2.0",
                "--wait-for-pid", "42",
            ]
        )
    }
}
