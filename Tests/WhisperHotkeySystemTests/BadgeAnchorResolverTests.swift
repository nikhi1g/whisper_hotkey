import CoreGraphics
import XCTest
@testable import WhisperHotkeySystem

final class BadgeAnchorResolverTests: XCTestCase {
    func testAccessibilityCaretWins() {
        let caret = CGRect(x: 100, y: 200, width: 2, height: 18)
        let field = CGRect(x: 20, y: 150, width: 400, height: 90)

        XCTAssertEqual(
            BadgeAnchorResolver.resolve(
                caretRect: caret,
                fieldRect: field,
                pointerLocation: CGPoint(x: 80, y: 180)
            ),
            BadgeAnchorGeometry(caretRect: caret, fieldRect: field)
        )
    }

    func testPointerAnchorsInsideFieldWhenCaretIsUnavailable() {
        let field = CGRect(x: 20, y: 150, width: 400, height: 90)

        XCTAssertEqual(
            BadgeAnchorResolver.resolve(
                caretRect: nil,
                fieldRect: field,
                pointerLocation: CGPoint(x: 80, y: 180)
            ),
            BadgeAnchorGeometry(
                caretRect: CGRect(x: 80, y: 171, width: 2, height: 18),
                fieldRect: field
            )
        )
    }

    func testFieldWinsWhenPointerIsOutsideIt() {
        let field = CGRect(x: 20, y: 150, width: 400, height: 90)

        XCTAssertEqual(
            BadgeAnchorResolver.resolve(
                caretRect: nil,
                fieldRect: field,
                pointerLocation: CGPoint(x: 700, y: 500)
            ),
            BadgeAnchorGeometry(caretRect: nil, fieldRect: field)
        )
    }

    func testPointerReplacesScreenCornerFallback() {
        XCTAssertEqual(
            BadgeAnchorResolver.resolve(
                caretRect: nil,
                fieldRect: nil,
                pointerLocation: CGPoint(x: 640, y: 360)
            ),
            BadgeAnchorGeometry(
                caretRect: CGRect(x: 640, y: 351, width: 2, height: 18),
                fieldRect: nil
            )
        )
    }
}
