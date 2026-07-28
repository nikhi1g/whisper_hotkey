import XCTest
@testable import WhisperHotkeySystem

final class TextInsertionTests: XCTestCase {
    func testAddsSpacesBetweenWords() {
        let context = SurroundingText(
            beforeSelection: "o",
            selectedText: "",
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
            selectedText: "",
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
            selectedText: "old words",
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
                    selectedText: "",
                    afterSelection: "."
                )
            ),
            " world"
        )
    }
}
