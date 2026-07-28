import XCTest
@testable import WhisperHotkeySystem

final class TargetValidationTests: XCTestCase {
    private let context = SurroundingText(
        beforeSelection: "a",
        selectedText: "b",
        afterSelection: "c"
    )

    func testMatchingFocusedTargetAndSelectionAreValid() {
        XCTAssertEqual(
            TargetValidator.validate(
                captured: captured(),
                current: current()
            ),
            .valid
        )
    }

    func testChangedFocusIsRejected() {
        XCTAssertEqual(
            TargetValidator.validate(
                captured: captured(),
                current: current(isSameElement: false)
            ),
            .invalid(.focusChanged)
        )
    }

    func testChangedSelectionIsRejected() {
        XCTAssertEqual(
            TargetValidator.validate(
                captured: captured(),
                current: current(selectionRange: NSRange(location: 4, length: 0))
            ),
            .invalid(.selectionChanged)
        )
    }

    func testSecureAndUneditableTargetsAreRejected() {
        XCTAssertEqual(
            TargetValidator.validate(
                captured: captured(isSecure: true),
                current: current(isSecure: true)
            ),
            .invalid(.secure)
        )
        XCTAssertEqual(
            TargetValidator.validate(
                captured: captured(isEditable: false),
                current: current(isEditable: false)
            ),
            .invalid(.notEditable)
        )
    }

    func testChangedSurroundingTextIsRejected() {
        XCTAssertEqual(
            TargetValidator.validate(
                captured: captured(),
                current: current(
                    surroundingText: SurroundingText(
                        beforeSelection: "x",
                        selectedText: "b",
                        afterSelection: "c"
                    )
                )
            ),
            .invalid(.surroundingTextChanged)
        )
    }

    func testUnreadableCurrentSurroundingTextFailsClosed() {
        XCTAssertEqual(
            TargetValidator.validate(
                captured: captured(),
                current: CurrentTargetState(
                    processIdentifier: 100,
                    isSameElement: true,
                    selectionRange: NSRange(location: 1, length: 1),
                    isSecure: false,
                    isEditable: true,
                    surroundingText: nil
                )
            ),
            .invalid(.surroundingTextChanged)
        )
    }

    private func captured(
        isSecure: Bool = false,
        isEditable: Bool = true
    ) -> CapturedTargetState {
        CapturedTargetState(
            processIdentifier: 100,
            selectionRange: NSRange(location: 1, length: 1),
            isSecure: isSecure,
            isEditable: isEditable,
            surroundingText: context
        )
    }

    private func current(
        isSameElement: Bool = true,
        selectionRange: NSRange? = NSRange(location: 1, length: 1),
        isSecure: Bool = false,
        isEditable: Bool = true,
        surroundingText: SurroundingText? = nil
    ) -> CurrentTargetState {
        CurrentTargetState(
            processIdentifier: 100,
            isSameElement: isSameElement,
            selectionRange: selectionRange,
            isSecure: isSecure,
            isEditable: isEditable,
            surroundingText: surroundingText ?? context
        )
    }
}
