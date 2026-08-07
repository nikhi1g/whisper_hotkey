import XCTest
@testable import WhisperHotkeyShell

/// Every permission the setup window lists is one more thing a new user has to
/// understand before dictating once, so a step that is never actually required
/// must not be shown.
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

    /// The normal machine: Accessibility satisfies the event tap's listen
    /// check, so Input Monitoring resolves itself and is never its own step.
    func testInputMonitoringIsNotAStepWhenAccessibilitySatisfiesIt() {
        XCTAssertFalse(
            readiness(accessibility: true, inputMonitoring: true)
                .requiresInputMonitoringStep
        )
    }

    /// Before Accessibility is granted the preflight fails too, but the fix is
    /// the Accessibility row. Showing both asks for two permissions to solve
    /// one problem.
    func testInputMonitoringIsNotAStepBeforeAccessibilityIsGranted() {
        XCTAssertFalse(
            readiness(accessibility: false, inputMonitoring: false)
                .requiresInputMonitoringStep
        )
    }

    /// The case that justifies keeping the check: an OS where Accessibility no
    /// longer implies listen access. The step has to reappear, or the hotkey
    /// silently does nothing with no way to fix it from the window.
    func testInputMonitoringBecomesAStepWhenItStillFailsAfterAccessibility() {
        XCTAssertTrue(
            readiness(accessibility: true, inputMonitoring: false)
                .requiresInputMonitoringStep
        )
    }

    /// Listen access is not a precondition for readiness. The event tap is a
    /// `.defaultTap`, which Accessibility authorises; `kTCCServiceListenEvent`
    /// is a separate grant the app never registers for, so requiring it here
    /// left setup permanently incomplete on a Mac where the hotkey worked.
    /// Whether the tap can actually be created is settled by creating it, and
    /// `reconcileRuntime` reopens setup when that fails.
    func testAccessibilityAloneIsEnoughForSetupToBeReady() {
        XCTAssertTrue(
            readiness(accessibility: true, inputMonitoring: false).isReady
        )
        XCTAssertTrue(
            readiness(accessibility: true, inputMonitoring: true).isReady
        )
    }

    /// Accessibility remains mandatory; dropping the listen check must not
    /// have made the permission that authorises the tap optional too.
    func testAccessibilityIsStillRequired() {
        XCTAssertFalse(
            readiness(accessibility: false, inputMonitoring: true).isReady
        )
    }
}
