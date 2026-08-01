import XCTest
@testable import WhisperHotkeyCore

final class StateMachineTests: XCTestCase {
    func testNormalDictationLifecycle() {
        var machine = DictationStateMachine()

        XCTAssertEqual(
            machine.handle(.hotkeyPressed(at: 10)),
            [.showBadge(.listening), .beginSession]
        )
        XCTAssertEqual(machine.phase, .preparing)
        XCTAssertEqual(machine.handle(.captureStarted), [])
        XCTAssertEqual(machine.phase, .listening)
        XCTAssertEqual(
            machine.handle(.hotkeyReleased(at: 10.251)),
            [.finalizeRecording, .showBadge(.transcribing)]
        )
        XCTAssertEqual(machine.phase, .transcribing)
        XCTAssertEqual(machine.handle(.transcriptReady), [.deliverTranscript])
        XCTAssertEqual(machine.handle(.deliveryFinished), [.showBadge(.hidden)])
        XCTAssertEqual(machine.phase, .idle)
    }

    func testShortPressCancelsWithoutTranscription() {
        var machine = DictationStateMachine()
        _ = machine.handle(.hotkeyPressed(at: 20))

        XCTAssertEqual(
            machine.handle(.hotkeyReleased(at: 20.249)),
            [.cancelSession, .showBadge(.hidden)]
        )
        XCTAssertEqual(machine.phase, .idle)
    }

    func testBusyPressDoesNotStartSecondSession() {
        var machine = DictationStateMachine()
        _ = machine.handle(.hotkeyPressed(at: 1))
        _ = machine.handle(.hotkeyReleased(at: 2))

        XCTAssertEqual(
            machine.handle(.hotkeyPressed(at: 3)),
            [.showBadge(.busy)]
        )
        XCTAssertEqual(machine.phase, .transcribing)
    }

    func testMaximumDurationFinalizesExactlyOnce() {
        var machine = DictationStateMachine()
        _ = machine.handle(.hotkeyPressed(at: 1))

        XCTAssertEqual(
            machine.handle(.maximumDurationReached),
            [.finalizeRecording, .showBadge(.transcribing)]
        )
        XCTAssertEqual(machine.handle(.hotkeyReleased(at: 602)), [])
        XCTAssertEqual(machine.phase, .transcribing)
    }

    func testChunkedSessionFinishesAfterFinalTranscription() {
        var machine = DictationStateMachine()
        _ = machine.handle(.hotkeyPressed(at: 1))
        _ = machine.handle(.captureStarted)
        _ = machine.handle(.maximumDurationReached)

        XCTAssertEqual(
            machine.handle(.chunkedSessionFinished),
            [.showBadge(.hidden)]
        )
        XCTAssertEqual(machine.phase, .idle)
        XCTAssertEqual(machine.handle(.chunkedSessionFinished), [])
    }

    func testCancellationAndFailureAreBounded() {
        var machine = DictationStateMachine()
        _ = machine.handle(.hotkeyPressed(at: 1))
        XCTAssertEqual(
            machine.handle(.cancel),
            [.cancelSession, .showBadge(.hidden)]
        )
        XCTAssertEqual(machine.phase, .cancelled)
        XCTAssertEqual(
            machine.handle(.cancellationPresentationFinished),
            [.showBadge(.hidden)]
        )
        XCTAssertEqual(machine.phase, .idle)
        XCTAssertEqual(machine.handle(.cancellationPresentationFinished), [])

        machine = DictationStateMachine()
        _ = machine.handle(.hotkeyPressed(at: 1))
        XCTAssertEqual(
            machine.handle(.failed("Microphone unavailable")),
            [.cancelSession, .showBadge(.error("Microphone unavailable"))]
        )
        XCTAssertEqual(machine.phase, .failed)
        XCTAssertEqual(machine.lastError, "Microphone unavailable")
        XCTAssertEqual(
            machine.handle(.errorPresentationFinished),
            [.showBadge(.hidden)]
        )
        XCTAssertEqual(machine.phase, .idle)
    }
}
