import XCTest
@testable import WhisperHotkeyCore

/// Reviewing-phase transitions for the post-processing flow:
/// transcribing -> reviewing -> inserting -> idle, plus the cancel and
/// invalid-event bounds. Existing transitions are covered by
/// `StateMachineTests` and remain untouched.
final class DictationStateMachineReviewTests: XCTestCase {
    private func machineInTranscribing() -> DictationStateMachine {
        var machine = DictationStateMachine()
        _ = machine.handle(.hotkeyPressed(at: 10))
        _ = machine.handle(.captureStarted)
        _ = machine.handle(.hotkeyReleased(at: 10.3))
        return machine
    }

    func testProcessingRequestedMovesTranscribingToReviewing() {
        var machine = machineInTranscribing()
        XCTAssertEqual(machine.handle(.processingRequested), [.requestProcessing])
        XCTAssertEqual(machine.phase, .reviewing)
    }

    func testReviewAcceptedInsertsThenFinishes() {
        var machine = machineInTranscribing()
        _ = machine.handle(.processingRequested)

        XCTAssertEqual(machine.handle(.reviewAccepted), [.deliverTranscript])
        XCTAssertEqual(machine.phase, .inserting)
        XCTAssertEqual(
            machine.handle(.deliveryFinished),
            [.showBadge(.hidden)]
        )
        XCTAssertEqual(machine.phase, .idle)
    }

    func testSecondReviewAcceptedInsertsNothing() {
        var machine = machineInTranscribing()
        _ = machine.handle(.processingRequested)
        _ = machine.handle(.reviewAccepted)

        XCTAssertEqual(machine.handle(.reviewAccepted), [])
        XCTAssertEqual(machine.phase, .inserting)
    }

    func testReviewCancelledRunsExistingCancelCleanup() {
        var machine = machineInTranscribing()
        _ = machine.handle(.processingRequested)

        XCTAssertEqual(
            machine.handle(.reviewCancelled),
            [.cancelSession, .showBadge(.hidden)]
        )
        XCTAssertEqual(machine.phase, .cancelled)
        XCTAssertEqual(
            machine.handle(.cancellationPresentationFinished),
            [.showBadge(.hidden)]
        )
        XCTAssertEqual(machine.phase, .idle)
    }

    func testGlobalCancelWorksWhileReviewing() {
        var machine = machineInTranscribing()
        _ = machine.handle(.processingRequested)

        XCTAssertEqual(
            machine.handle(.cancel),
            [.cancelSession, .showBadge(.hidden)]
        )
        XCTAssertEqual(machine.phase, .cancelled)
    }

    func testFailureWhileReviewingIsBounded() {
        var machine = machineInTranscribing()
        _ = machine.handle(.processingRequested)

        XCTAssertEqual(
            machine.handle(.failed("Processor unavailable")),
            [.cancelSession, .showBadge(.error("Processor unavailable"))]
        )
        XCTAssertEqual(machine.phase, .failed)
        XCTAssertEqual(machine.lastError, "Processor unavailable")
    }

    func testInvalidEventsAreIgnoredWhileReviewing() {
        var machine = machineInTranscribing()
        _ = machine.handle(.processingRequested)

        // A new press is not an error: it reports busy exactly like the
        // other active phases and starts nothing.
        XCTAssertEqual(
            machine.handle(.hotkeyPressed(at: 42)),
            [.showBadge(.busy)]
        )
        XCTAssertEqual(machine.phase, .reviewing)

        let ignored: [DictationEvent] = [
            .captureStarted,
            .hotkeyReleased(at: 42.3),
            .maximumDurationReached,
            .transcriptReady,
            .processingRequested,
            .deliveryFinished,
            .chunkedSessionFinished,
            .cancellationPresentationFinished,
            .errorPresentationFinished,
        ]
        for event in ignored {
            XCTAssertEqual(machine.handle(event), [], "unexpected effects for \(event)")
            XCTAssertEqual(machine.phase, .reviewing, "phase changed for \(event)")
        }
    }
}
