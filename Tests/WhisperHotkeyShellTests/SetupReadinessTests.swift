import XCTest
@testable import WhisperHotkeyShell

/// 3.7.0 dropped Input Monitoring from the setup window on the theory that
/// granting Accessibility already covered the event tap. Accessibility covers
/// *creating* the tap and delivers `flagsChanged`, which is why the dictation
/// modifier kept working and setup still reported ready. `keyDown` is only
/// delivered to a tap holding `kTCCServiceListenEvent`, and Return and Escape
/// are `keyDown`, so the completion shortcuts silently stopped working.
final class SetupReadinessTests: XCTestCase {
    private func readiness(
        accessibility: Bool,
        inputMonitoring: Bool
    ) -> SetupReadiness {
        SetupReadiness(
            microphoneGranted: true,
            accessibilityGranted: accessibility,
            inputMonitoringGranted: inputMonitoring,
            modelAvailable: true,
            helperAvailable: true
        )
    }

    /// The row is unconditional. Hiding it removed the only place the
    /// permission could be granted from, and an app with no row in the Input
    /// Monitoring list has nothing for the user to switch on.
    func testInputMonitoringIsAlwaysItsOwnStep() {
        for accessibility in [true, false] {
            for inputMonitoring in [true, false] {
                XCTAssertTrue(
                    readiness(
                        accessibility: accessibility,
                        inputMonitoring: inputMonitoring
                    ).requiresInputMonitoringStep
                )
            }
        }
    }

    /// Setup is not complete without listen access, however healthy the rest
    /// of the window looks. This is the check whose removal let a build ship
    /// reporting "Setup verified" with Return doing nothing.
    func testListenAccessIsRequiredForReadiness() {
        XCTAssertFalse(
            readiness(accessibility: true, inputMonitoring: false).isReady
        )
        XCTAssertTrue(
            readiness(accessibility: true, inputMonitoring: true).isReady
        )
    }

    /// Accessibility remains mandatory too: it is what authorises the tap and
    /// the synthetic paste.
    func testAccessibilityIsRequiredForReadiness() {
        XCTAssertFalse(
            readiness(accessibility: false, inputMonitoring: true).isReady
        )
    }
}
