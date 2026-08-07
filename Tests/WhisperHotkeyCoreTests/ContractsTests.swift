import XCTest
@testable import WhisperHotkeyCore

final class ContractsTests: XCTestCase {
    func testBusyPhasesAreExplicit() {
        XCTAssertTrue(DictationPhase.preparing.isBusy)
        XCTAssertTrue(DictationPhase.listening.isBusy)
        XCTAssertTrue(DictationPhase.transcribing.isBusy)
        XCTAssertTrue(DictationPhase.inserting.isBusy)
        XCTAssertFalse(DictationPhase.idle.isBusy)
        XCTAssertFalse(DictationPhase.failed.isBusy)
    }

    func testControlProtocolRoundTrips() throws {
        let request = ControlRequest(command: .disableLogin)
        let data = try JSONEncoder().encode(request)
        XCTAssertEqual(try JSONDecoder().decode(ControlRequest.self, from: data), request)
    }

    func testSetupVerificationRequiresEveryReadinessField() {
        let ready = RuntimeStatus(
            running: true,
            phase: .idle,
            microphoneGranted: true,
            accessibilityGranted: true,
            inputMonitoringGranted: true,
            loginItemEnabled: true,
            helperAvailable: true,
            modelAvailable: true
        )
        XCTAssertTrue(ready.setupIsVerified)

        let requirements: [WritableKeyPath<RuntimeStatus, Bool>] = [
            \.running,
            \.microphoneGranted,
            \.accessibilityGranted,
            \.loginItemEnabled,
            \.helperAvailable,
            \.modelAvailable,
        ]
        for requirement in requirements {
            var missing = ready
            missing[keyPath: requirement] = false
            XCTAssertFalse(missing.setupIsVerified)
        }
    }

    /// Input Monitoring is reported but not required, matching
    /// `SetupReadiness.isReady`. The event tap runs on the Accessibility
    /// grant, and requiring listen access here made `verify-setup` -- which
    /// `run.sh` blocks on until it succeeds -- unable to ever return.
    func testSetupVerificationDoesNotRequireInputMonitoring() {
        let status = RuntimeStatus(
            running: true,
            phase: .idle,
            microphoneGranted: true,
            accessibilityGranted: true,
            inputMonitoringGranted: false,
            loginItemEnabled: true,
            helperAvailable: true,
            modelAvailable: true
        )
        XCTAssertTrue(status.setupIsVerified)
    }
}
