import CoreGraphics
import XCTest
@testable import WhisperHotkeySystem

final class ScreenCoordinatesTests: XCTestCase {
    private let primaryScreen = CGRect(x: 0, y: 0, width: 1_440, height: 900)

    func testFlipsAccessibilityRectIntoAppKitScreenSpace() {
        XCTAssertEqual(
            convert(CGRect(x: 120, y: 40, width: 2, height: 20)),
            CGRect(x: 120, y: 840, width: 2, height: 20)
        )
        XCTAssertEqual(
            convert(CGRect(x: 120, y: 880, width: 2, height: 20)),
            CGRect(x: 120, y: 0, width: 2, height: 20)
        )
    }

    func testDisplayLeftOfPrimaryPreservesNegativeX() {
        XCTAssertEqual(
            convert(CGRect(x: -1_200, y: 100, width: 10, height: 20)),
            CGRect(x: -1_200, y: 780, width: 10, height: 20)
        )
    }

    func testDisplayAbovePrimaryMapsNegativeAccessibilityYAbovePrimary() {
        XCTAssertEqual(
            convert(CGRect(x: 100, y: -700, width: 10, height: 20)),
            CGRect(x: 100, y: 1_580, width: 10, height: 20)
        )
    }

    func testDisplayBelowPrimaryMapsLargeAccessibilityYBelowPrimary() {
        XCTAssertEqual(
            convert(CGRect(x: 100, y: 950, width: 10, height: 20)),
            CGRect(x: 100, y: -70, width: 10, height: 20)
        )
    }

    func testTallerDisplayTopAlignedWithPrimaryCanExtendBelowPrimary() {
        XCTAssertEqual(
            convert(CGRect(x: 1_600, y: 1_000, width: 10, height: 20)),
            CGRect(x: 1_600, y: -120, width: 10, height: 20)
        )
    }

    private func convert(_ rect: CGRect) -> CGRect {
        AccessibilityScreenCoordinates.appKitRect(
            from: rect,
            primaryScreenFrame: primaryScreen
        )
    }
}
