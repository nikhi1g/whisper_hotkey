import CoreGraphics
import XCTest
@testable import WhisperHotkeySystem

final class BadgeAnchorResolverTests: XCTestCase {
    func testAccessibilityCaretWins() {
        let caret = CGRect(x: 100, y: 200, width: 2, height: 18)

        XCTAssertEqual(
            BadgeAnchorResolver.resolve(
                caretRect: caret,
                fieldRect: CGRect(x: 80, y: 180, width: 400, height: 60)
            ),
            BadgeAnchorGeometry(
                caretRect: caret,
                fieldRect: CGRect(x: 80, y: 180, width: 400, height: 60)
            )
        )
    }

    func testMissingCaretHasNoApproximateFallback() {
        XCTAssertEqual(
            BadgeAnchorResolver.resolve(caretRect: nil),
            BadgeAnchorGeometry(caretRect: nil, fieldRect: nil)
        )
    }

    func testInvalidFieldDoesNotDiscardUsableCaret() {
        let caret = CGRect(x: 100, y: 200, width: 2, height: 18)

        XCTAssertEqual(
            BadgeAnchorResolver.resolve(
                caretRect: caret,
                fieldRect: .null
            ),
            BadgeAnchorGeometry(caretRect: caret, fieldRect: nil)
        )
    }
}
