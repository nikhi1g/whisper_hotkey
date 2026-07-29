import XCTest
@testable import WhisperHotkeyShell

final class BadgePresentationDurationTests: XCTestCase {
    func testNoSpeechDismissesTwiceAsFastAsStandardErrors() {
        XCTAssertEqual(
            BadgePresentationDuration.noSpeech * 2,
            BadgePresentationDuration.standardError
        )
    }
}
