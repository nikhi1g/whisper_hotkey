import CoreGraphics
import XCTest
@testable import WhisperHotkeyShell

final class BadgePlacementTests: XCTestCase {
    func testRuntimeAnchorFallsBackToPointer() {
        let anchor = BadgePlacement.runtimeAnchor(
            caretFrame: nil,
            fieldFrame: nil,
            pointerLocation: CGPoint(x: 420, y: 240)
        )

        XCTAssertEqual(
            anchor,
            CGRect(x: 420, y: 240, width: 1, height: 1)
        )
    }

    func testRuntimeAnchorPrefersExactCaret() {
        let caret = CGRect(x: 100, y: 200, width: 2, height: 20)
        let anchor = BadgePlacement.runtimeAnchor(
            caretFrame: caret,
            fieldFrame: CGRect(x: 20, y: 30, width: 300, height: 40),
            pointerLocation: CGPoint(x: 420, y: 240)
        )

        XCTAssertEqual(anchor, caret)
    }

    func testResolvedRuntimeAnchorDistinguishesPointerFallback() {
        XCTAssertEqual(
            BadgePlacement.resolvedRuntimeAnchor(
                caretFrame: nil,
                fieldFrame: nil,
                pointerLocation: CGPoint(x: 420, y: 240)
            ),
            .pointer(CGPoint(x: 420, y: 240))
        )
        XCTAssertEqual(
            BadgePlacement.resolvedRuntimeAnchor(
                caretFrame: CGRect(x: 100, y: 200, width: 1, height: 18),
                fieldFrame: nil,
                pointerLocation: CGPoint(x: 420, y: 240)
            ),
            .accessibility(
                CGRect(x: 100, y: 200, width: 1, height: 18)
            )
        )
    }

    func testZeroWidthCaretResolvesToSecondaryDisplay() {
        let index = BadgeScreenResolver.index(
            containing: CGRect(x: 1_800, y: 300, width: 0, height: 18),
            screenFrames: [
                CGRect(x: 0, y: 0, width: 1_440, height: 900),
                CGRect(x: 1_440, y: 0, width: 1_920, height: 1_080),
            ]
        )

        XCTAssertEqual(index, 1)
    }

    func testPlacesBadgeAboveCaretLine() {
        let frame = BadgePlacement.frame(
            caretFrame: CGRect(x: 100, y: 200, width: 2, height: 20),
            fieldFrame: nil,
            screenFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            badgeSize: CGSize(width: 100, height: 30)
        )

        XCTAssertEqual(frame, CGRect(x: 100, y: 228, width: 100, height: 30))
    }

    func testClampsHorizontalAlignmentAtRightScreenEdge() {
        let frame = BadgePlacement.frame(
            caretFrame: CGRect(x: 950, y: 200, width: 2, height: 20),
            fieldFrame: nil,
            screenFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            badgeSize: CGSize(width: 100, height: 30)
        )

        XCTAssertEqual(frame.origin.x, 892)
        XCTAssertEqual(frame.origin.y, 228)
    }

    func testPlacesAboveCompleteFieldInsteadOfObscuringItsCaret() {
        let frame = BadgePlacement.frame(
            caretFrame: CGRect(x: 200, y: 35, width: 2, height: 20),
            fieldFrame: CGRect(x: 20, y: 30, width: 300, height: 40),
            screenFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            badgeSize: CGSize(width: 100, height: 30)
        )

        XCTAssertEqual(frame, CGRect(x: 20, y: 78, width: 100, height: 30))
        XCTAssertFalse(
            frame.intersects(CGRect(x: 20, y: 30, width: 300, height: 40))
        )
    }

    func testFlipsBelowFieldWhenTopEdgeHasNoRoom() {
        let field = CGRect(x: 20, y: 750, width: 300, height: 40)
        let frame = BadgePlacement.frame(
            caretFrame: CGRect(x: 200, y: 755, width: 2, height: 20),
            fieldFrame: field,
            screenFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            badgeSize: CGSize(width: 100, height: 30)
        )

        XCTAssertEqual(frame, CGRect(x: 20, y: 712, width: 100, height: 30))
        XCTAssertFalse(frame.intersects(field))
    }

    func testFallsBackToVisibleScreenCornerAndClamps() {
        let frame = BadgePlacement.frame(
            caretFrame: nil,
            fieldFrame: nil,
            screenFrame: CGRect(x: 100, y: 50, width: 300, height: 200),
            badgeSize: CGSize(width: 100, height: 30)
        )

        XCTAssertEqual(frame, CGRect(x: 292, y: 58, width: 100, height: 30))
    }

    func testPointerHotspotIsDirectlyUnderPointerWhenSpacePermits() {
        let pointer = CGPoint(x: 500, y: 400)
        let hotspot = CGPoint(x: 80, y: 20)
        let frame = BadgePlacement.frame(
            pointerLocation: pointer,
            badgeHotspot: hotspot,
            screenFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            badgeSize: CGSize(width: 100, height: 30)
        )

        XCTAssertEqual(frame, CGRect(x: 420, y: 380, width: 100, height: 30))
        XCTAssertEqual(
            CGPoint(x: frame.minX + hotspot.x, y: frame.minY + hotspot.y),
            pointer
        )
    }

    func testPreservedOriginSurvivesBadgeSizeChanges() {
        let frame = BadgePlacement.frame(
            preservingOrigin: CGPoint(x: 110, y: 195),
            screenFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            badgeSize: CGSize(width: 180, height: 38)
        )

        XCTAssertEqual(frame, CGRect(x: 110, y: 195, width: 180, height: 38))
    }

    func testPreservedOriginClampsLargerBadgeInsideScreen() {
        let frame = BadgePlacement.frame(
            preservingOrigin: CGPoint(x: 850, y: 770),
            screenFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            badgeSize: CGSize(width: 180, height: 38)
        )

        XCTAssertEqual(frame, CGRect(x: 812, y: 754, width: 180, height: 38))
    }
}
