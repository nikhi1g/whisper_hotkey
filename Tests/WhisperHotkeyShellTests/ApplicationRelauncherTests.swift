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
}
