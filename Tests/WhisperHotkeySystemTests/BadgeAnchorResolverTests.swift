import CoreGraphics
import XCTest
@testable import WhisperHotkeySystem

final class BadgeAnchorResolverTests: XCTestCase {
    func testAccessibilityCaretWins() {
        let caret = CGRect(x: 100, y: 200, width: 2, height: 18)

        XCTAssertEqual(
            BadgeAnchorResolver.resolve(
                caretRect: caret
            ),
            BadgeAnchorGeometry(caretRect: caret)
        )
    }

    func testMissingCaretHasNoApproximateFallback() {
        XCTAssertEqual(
            BadgeAnchorResolver.resolve(caretRect: nil),
            BadgeAnchorGeometry(caretRect: nil)
        )
    }
}
