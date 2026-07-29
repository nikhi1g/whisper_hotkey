import XCTest
@testable import WhisperHotkeyCore

final class DictationContextPromptTests: XCTestCase {
    func testContextTailIsTrimmedAndStrictlyBounded() {
        XCTAssertNil(DictationContextPrompt.boundedTail(of: " \n "))
        XCTAssertEqual(
            DictationContextPrompt.boundedTail(of: "  prior sentence. \n"),
            "prior sentence."
        )

        let source = String(repeating: "a", count: 300)
        let result = DictationContextPrompt.boundedTail(of: source)
        XCTAssertEqual(
            result?.count,
            DictationContextPrompt.maximumCharacters
        )
        XCTAssertEqual(result, String(repeating: "a", count: 240))
    }
}
