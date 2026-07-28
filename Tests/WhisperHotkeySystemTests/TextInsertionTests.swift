import XCTest
@testable import WhisperHotkeySystem

final class TextInsertionTests: XCTestCase {
    func testAddsSpacesBetweenWords() {
        let context = SurroundingText(
            beforeSelection: "o",
            afterSelection: "w"
        )

        XCTAssertEqual(
            TextInsertionFormatter.insertionText(
                transcript: "new",
                surroundingText: context
            ),
            " new "
        )
    }

    func testDoesNotDuplicateWhitespace() {
        let context = SurroundingText(
            beforeSelection: " ",
            afterSelection: "\n"
        )

        XCTAssertEqual(
            TextInsertionFormatter.insertionText(
                transcript: " new ",
                surroundingText: context
            ),
            "new"
        )
    }

    func testSelectionReplacementUsesOutsideBoundaries() {
        let context = SurroundingText(
            beforeSelection: "(",
            afterSelection: ")"
        )

        XCTAssertEqual(
            TextInsertionFormatter.insertionText(
                transcript: "new words",
                surroundingText: context
            ),
            "new words"
        )
    }

    func testAddsSpaceAfterExistingCommaButNotBeforeClosingPunctuation() {
        XCTAssertEqual(
            TextInsertionFormatter.insertionText(
                transcript: "world",
                surroundingText: SurroundingText(
                    beforeSelection: ",",
                    afterSelection: "."
                )
            ),
            " world"
        )
    }

    func testAddsOneTrailingSpaceAtEndOfField() {
        XCTAssertEqual(
            TextInsertionFormatter.insertionText(
                transcript: "A complete sentence. ",
                surroundingText: SurroundingText(
                    beforeSelection: ".",
                    afterSelection: nil
                )
            ),
            " A complete sentence. "
        )
    }

    func testOpaqueContextStillAddsOneTrailingSpace() {
        XCTAssertEqual(
            TextInsertionFormatter.insertionText(
                transcript: "Next sentence.  ",
                surroundingText: nil
            ),
            "Next sentence. "
        )
    }
}
