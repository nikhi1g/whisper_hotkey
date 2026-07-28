import XCTest
@testable import WhisperHotkeyShell

final class ListeningBadgeTests: XCTestCase {
    func testNormalTimerShowsElapsedOnly() {
        let metrics = ListeningBadgeMetrics(elapsed: 65.9, limit: 600)
        XCTAssertEqual(metrics.timeText, "1:05")
        XCTAssertFalse(metrics.isWarning)
        XCTAssertEqual(metrics.warningProgress, 0)
    }

    func testFinalThirtySecondsShowsFractionAndProgress() {
        let metrics = ListeningBadgeMetrics(elapsed: 575, limit: 600)
        XCTAssertEqual(metrics.timeText, "9:35 / 10:00")
        XCTAssertTrue(metrics.isWarning)
        XCTAssertEqual(metrics.warningProgress, 1.0 / 6.0, accuracy: 0.001)
    }

    func testHourLimitUsesHourClock() {
        let metrics = ListeningBadgeMetrics(elapsed: 3_575, limit: 3_600)
        XCTAssertEqual(metrics.timeText, "59:35 / 1:00:00")
        XCTAssertTrue(metrics.isWarning)
    }

    @MainActor
    func testControllerKeepsPanelVisibleAcrossListeningUpdates() {
        let controller = CaretBadgeController()
        controller.present(
            .listening,
            caretFrame: CGRect(x: 200, y: 200, width: 1, height: 18),
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
        )
        XCTAssertTrue(controller.isVisible)

        controller.updateListening(
            elapsed: 575,
            limit: 600,
            level: 0.8
        )
        XCTAssertTrue(controller.isVisible)

        controller.present(
            .transcribing,
            caretFrame: CGRect(x: 200, y: 200, width: 1, height: 18),
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
        )
        XCTAssertTrue(controller.isVisible)

        controller.hide()
        XCTAssertFalse(controller.isVisible)
    }
}
