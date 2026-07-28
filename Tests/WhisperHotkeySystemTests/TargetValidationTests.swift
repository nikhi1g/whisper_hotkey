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
                captured: captured(textMode: .unavailable),
                current: current(textMode: .unavailable)
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
                    role: kAXTextFieldRole,
                    subrole: nil,
                    textMode: .selectionAware,
                    selectionRange: NSRange(location: 1, length: 1),
                    isSecure: false,
                    surroundingText: nil
                )
            ),
            .invalid(.surroundingTextChanged)
        )
    }

    func testMatchingOpaqueTextTargetIsValidWithoutSelectionRange() {
        XCTAssertEqual(
            TargetValidator.validate(
                captured: captured(
                    textMode: .opaque,
                    selectionRange: nil,
                    surroundingText: nil
                ),
                current: current(
                    textMode: .opaque,
                    selectionRange: nil,
                    surroundingText: nil
                )
            ),
            .valid
        )
    }

    func testOpaqueTargetRequiresStableRoleAndSubrole() {
        XCTAssertEqual(
            TargetValidator.validate(
                captured: captured(
                    textMode: .opaque,
                    selectionRange: nil,
                    surroundingText: nil
                ),
                current: current(
                    role: kAXTextAreaRole,
                    textMode: .opaque,
                    selectionRange: nil,
                    surroundingText: nil
                )
            ),
            .invalid(.targetAttributesChanged)
        )
        XCTAssertEqual(
            TargetValidator.validate(
                captured: captured(
                    subrole: "AXSearchField",
                    textMode: .opaque,
                    selectionRange: nil,
                    surroundingText: nil
                ),
                current: current(
                    subrole: nil,
                    textMode: .opaque,
                    selectionRange: nil,
                    surroundingText: nil
                )
            ),
            .invalid(.targetAttributesChanged)
        )
    }

    func testOpaqueTargetRequiresStableProcess() {
        XCTAssertEqual(
            TargetValidator.validate(
                captured: captured(
                    textMode: .opaque,
                    selectionRange: nil,
                    surroundingText: nil
                ),
                current: current(
                    processIdentifier: 101,
                    textMode: .opaque,
                    selectionRange: nil,
                    surroundingText: nil
                )
            ),
            .invalid(.focusChanged)
        )
    }

    func testOpaqueTargetNeverAcceptsSecureCurrentField() {
        XCTAssertEqual(
            TargetValidator.validate(
                captured: captured(
                    textMode: .opaque,
                    selectionRange: nil,
                    surroundingText: nil
                ),
                current: current(
                    subrole: kAXSecureTextFieldSubrole,
                    textMode: .unavailable,
                    selectionRange: nil,
                    isSecure: true,
                    surroundingText: nil
                )
            ),
            .invalid(.secure)
        )
    }

    private func captured(
        role: String? = kAXTextFieldRole,
        subrole: String? = nil,
        textMode: TargetTextMode = .selectionAware,
        selectionRange: NSRange? = NSRange(location: 1, length: 1),
        isSecure: Bool = false,
        surroundingText: SurroundingText? = nil
    ) -> CapturedTargetState {
        CapturedTargetState(
            processIdentifier: 100,
            role: role,
            subrole: subrole,
            textMode: textMode,
            selectionRange: selectionRange,
            isSecure: isSecure,
            surroundingText: surroundingText ?? (
                textMode == .selectionAware ? context : nil
            )
        )
    }

    private func current(
        processIdentifier: pid_t = 100,
        isSameElement: Bool = true,
        role: String? = kAXTextFieldRole,
        subrole: String? = nil,
        textMode: TargetTextMode = .selectionAware,
        selectionRange: NSRange? = NSRange(location: 1, length: 1),
        isSecure: Bool = false,
        surroundingText: SurroundingText? = nil
    ) -> CurrentTargetState {
        CurrentTargetState(
            processIdentifier: processIdentifier,
            isSameElement: isSameElement,
            role: role,
            subrole: subrole,
            textMode: textMode,
            selectionRange: selectionRange,
            isSecure: isSecure,
            surroundingText: surroundingText ?? (
                textMode == .selectionAware ? context : nil
            )
        )
    }
}
