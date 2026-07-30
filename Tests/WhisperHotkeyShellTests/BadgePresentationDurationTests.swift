import XCTest
@testable import WhisperHotkeyShell

final class BadgePresentationDurationTests: XCTestCase {
    func testNoSpeechDismissesAfterTwoTenthsOfASecond() {
        XCTAssertEqual(
            BadgePresentationDuration.noSpeech,
            .milliseconds(200)
        )
    }

    func testNoSpeechDismissesBeforeCancelledMenuState() {
        XCTAssertGreaterThan(
            BadgePresentationDuration.cancelledMenuState,
            BadgePresentationDuration.noSpeech
        )
    }
}
