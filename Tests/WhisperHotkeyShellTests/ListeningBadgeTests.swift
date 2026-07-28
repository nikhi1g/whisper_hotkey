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

    @MainActor
    func testListeningUpdateRestoresUnexpectedlyOrderedOutPanel() {
        let controller = CaretBadgeController()
        controller.present(
            .listening,
            caretFrame: nil,
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
        )
        controller.orderOutWithoutEndingPresentationForTesting()
        XCTAssertFalse(controller.isVisible)

        controller.updateListening(elapsed: 1, limit: 600, level: 0.4)

        XCTAssertTrue(controller.isVisible)
        controller.hide()
    }

    @MainActor
    func testControllerRoutesBothExplicitCompletionActions() {
        var stopped = 0
        var submitted = 0
        let controller = CaretBadgeController(
            actions: CaretBadgeActions(
                stopAndInsert: { stopped += 1 },
                sendAndSubmit: { submitted += 1 }
            )
        )

        controller.invokeStopAndInsertForTesting()
        controller.invokeSendAndSubmitForTesting()

        XCTAssertEqual(stopped, 1)
        XCTAssertEqual(submitted, 1)
    }

    func testWaveformHistoryIsSensitiveAndScrolls() {
        var history = AudioWaveformHistory(capacity: 3)
        history.append(0.1)
        XCTAssertGreaterThan(history.samples.last ?? 0, 0.2)

        history.append(0.4)
        history.append(0.8)
        history.append(1)
        XCTAssertEqual(history.samples.count, 3)
        XCTAssertEqual(history.samples.last, 1)
        XCTAssertGreaterThan(history.samples[2], history.samples[1])
    }

    func testVisiblePanelOnInactiveSpaceRequiresRecovery() {
        XCTAssertTrue(
            BadgePanelVisibility(
                isVisible: true,
                isOnActiveSpace: false
            ).requiresRecovery
        )
        XCTAssertFalse(
            BadgePanelVisibility(
                isVisible: true,
                isOnActiveSpace: true
            ).requiresRecovery
        )
    }

    @MainActor
    func testOverlayJoinsSpacesApplicationsAndFullScreen() {
        let behavior = CaretBadgeController.overlayCollectionBehavior
        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(behavior.contains(.canJoinAllApplications))
        XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
    }

    func testCompactListeningLayoutHasTightSquareControls() {
        let layout = ListeningBadgeLayout(isWarning: false)
        XCTAssertEqual(layout.size, CGSize(width: 244, height: 42))
        XCTAssertEqual(layout.waveformFrame.minX, 10)
        XCTAssertEqual(layout.size.width - layout.sendButtonFrame.maxX, 10)
        XCTAssertEqual(
            layout.timeFrame.minX - layout.waveformFrame.maxX,
            4
        )
        XCTAssertEqual(
            layout.stopButtonFrame.minX - layout.timeFrame.maxX,
            4
        )
        XCTAssertEqual(
            layout.sendButtonFrame.minX - layout.stopButtonFrame.maxX,
            4
        )
        XCTAssertEqual(
            layout.stopButtonFrame.width,
            layout.stopButtonFrame.height
        )
        XCTAssertEqual(
            layout.sendButtonFrame.width,
            layout.sendButtonFrame.height
        )
        XCTAssertGreaterThan(
            ListeningBadgeLayout(isWarning: true).size.width,
            layout.size.width
        )
    }

    func testEveryBadgeLabelIsGeometricallyCenteredWithMargins() {
        let listening = ListeningBadgeLayout(isWarning: false)
        let timerFrame = BadgeTextLayout.centeredFrame(
            in: listening.timeFrame,
            contentHeight: 15.2
        )
        XCTAssertEqual(timerFrame.midX, listening.timeFrame.midX)
        XCTAssertEqual(timerFrame.midY, listening.timeFrame.midY)

        let statusSize = StatusBadgeLayout.size(contentWidth: 80)
        let statusBounds = CGRect(origin: .zero, size: statusSize)
        let statusFrame = BadgeTextLayout.centeredFrame(
            in: statusBounds,
            horizontalInset: StatusBadgeLayout.horizontalMargin,
            contentHeight: 16
        )
        XCTAssertEqual(statusFrame.midX, statusBounds.midX)
        XCTAssertEqual(statusFrame.midY, statusBounds.midY)
        XCTAssertEqual(statusFrame.minX, StatusBadgeLayout.horizontalMargin)
        XCTAssertEqual(
            statusBounds.width - statusFrame.maxX,
            StatusBadgeLayout.horizontalMargin
        )
    }

    func testWaveformBarsAreTwoThirdsOfPreviousThicknessAndCentered() {
        XCTAssertEqual(AudioWaveformStyle.barWidth, 1.6)
        let count = 23
        let width: CGFloat = 100
        let gap = AudioWaveformStyle.gap(
            availableWidth: width,
            sampleCount: count
        )
        let drawnWidth = CGFloat(count) * AudioWaveformStyle.barWidth
            + CGFloat(count - 1) * gap

        XCTAssertEqual(
            drawnWidth,
            width - AudioWaveformStyle.horizontalInset * 2,
            accuracy: 0.001
        )
        XCTAssertEqual((width - drawnWidth) / 2, 4, accuracy: 0.001)
    }
}
