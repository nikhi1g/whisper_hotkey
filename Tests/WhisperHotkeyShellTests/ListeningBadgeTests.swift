import AppKit
import XCTest
@testable import WhisperHotkeyShell

final class ListeningBadgeTests: XCTestCase {
    func testNormalTimerAlwaysShowsElapsedAndLimit() {
        let metrics = ListeningBadgeMetrics(elapsed: 65.9, limit: 600)
        XCTAssertEqual(metrics.timeText, "1:05 / 10:00")
        XCTAssertEqual(
            metrics.accessibilityText,
            "1:05 of 10:00, 8:54 remaining"
        )
        XCTAssertFalse(metrics.isWarning)
        XCTAssertEqual(metrics.warningProgress, 0)
        XCTAssertEqual(metrics.progress, 65.9 / 600, accuracy: 0.001)
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

    func testLimitProgressClampsAtBothEnds() {
        XCTAssertEqual(
            ListeningBadgeMetrics(elapsed: -10, limit: 300).progress,
            0
        )
        let completed = ListeningBadgeMetrics(elapsed: 400, limit: 300)
        XCTAssertEqual(completed.progress, 1)
        XCTAssertEqual(completed.timeText, "5:00 / 5:00")
        XCTAssertEqual(
            completed.accessibilityText,
            "5:00 of 5:00, 0:00 remaining"
        )
    }

    @MainActor
    func testLongestVisibleLimitFitsItsCenteredTimerCell() {
        let label = NSTextField(labelWithString: "59:35 / 1:00:00")
        label.font = .monospacedDigitSystemFont(
            ofSize: 10.5,
            weight: .semibold
        )

        XCTAssertLessThanOrEqual(
            ceil(label.intrinsicContentSize.width),
            ListeningBadgeLayout().timeFrame.width
        )
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
    func testControllerKeepsInitialOriginAcrossStateAndAnchorChanges() {
        let controller = CaretBadgeController()
        controller.present(
            .listening,
            caretFrame: CGRect(x: 200, y: 200, width: 1, height: 18),
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
        )
        let listeningOrigin = controller.panelFrameForTesting.origin

        controller.present(
            .transcribing,
            caretFrame: CGRect(x: 900, y: 600, width: 1, height: 18),
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
        )
        XCTAssertEqual(controller.panelFrameForTesting.origin, listeningOrigin)

        controller.present(
            .error("Try again"),
            caretFrame: nil,
            fieldFrame: CGRect(x: 40, y: 50, width: 400, height: 60),
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
        )
        XCTAssertEqual(controller.panelFrameForTesting.origin, listeningOrigin)
        controller.hide()
    }

    @MainActor
    func testNewListeningSessionMayCaptureANewOrigin() {
        let controller = CaretBadgeController()
        let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        controller.present(
            .listening,
            caretFrame: CGRect(x: 200, y: 200, width: 1, height: 18),
            screenFrame: screen
        )
        let firstOrigin = controller.panelFrameForTesting.origin
        controller.hide()

        controller.present(
            .listening,
            caretFrame: CGRect(x: 800, y: 500, width: 1, height: 18),
            screenFrame: screen
        )
        XCTAssertNotEqual(controller.panelFrameForTesting.origin, firstOrigin)
        controller.hide()
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

    @MainActor
    func testNativeAppKitHitTestingClicksControlCentersAndVisibleEdge() {
        var stopped = 0
        var submitted = 0
        let controller = CaretBadgeController(
            actions: CaretBadgeActions(
                stopAndInsert: { stopped += 1 },
                sendAndSubmit: { submitted += 1 }
            )
        )
        controller.present(
            .listening,
            caretFrame: CGRect(x: 200, y: 200, width: 1, height: 18),
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
        )
        let layout = ListeningBadgeLayout()

        controller.clickBadgeForTesting(
            at: CGPoint(
                x: layout.stopButtonFrame.midX,
                y: layout.stopButtonFrame.midY
            )
        )
        controller.clickBadgeForTesting(
            at: CGPoint(
                x: layout.sendButtonFrame.maxX - 0.5,
                y: layout.sendButtonFrame.midY
            )
        )

        XCTAssertEqual(stopped, 1)
        XCTAssertEqual(submitted, 1)
        controller.hide()
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
        let layout = ListeningBadgeLayout()
        XCTAssertEqual(layout.size, CGSize(width: 281, height: 48))
        XCTAssertEqual(layout.waveformFrame.minX, 12)
        XCTAssertEqual(layout.size.width - layout.sendButtonFrame.maxX, 12)
        XCTAssertEqual(
            layout.timeFrame.minX - layout.waveformFrame.maxX,
            3
        )
        XCTAssertEqual(
            layout.stopButtonFrame.minX - layout.timeFrame.maxX,
            3
        )
        XCTAssertEqual(
            layout.sendButtonFrame.minX - layout.stopButtonFrame.maxX,
            3
        )
        XCTAssertEqual(
            layout.stopButtonFrame.width,
            layout.stopButtonFrame.height
        )
        XCTAssertEqual(
            layout.sendButtonFrame.width,
            layout.sendButtonFrame.height
        )
        XCTAssertEqual(layout.stopButtonFrame.minY, 7)
        XCTAssertEqual(layout.sendButtonFrame.minY, 6)
        XCTAssertEqual(layout.limitTrackFrame.minX, 12)
        XCTAssertEqual(layout.size.width - layout.limitTrackFrame.maxX, 12)
        XCTAssertEqual(layout.limitTrackFrame.height, 1.5)
    }

    func testEveryBadgeLabelIsGeometricallyCenteredWithMargins() {
        let listening = ListeningBadgeLayout()
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
        XCTAssertEqual(StatusBadgeLayout.height, 38)
        XCTAssertEqual(
            StatusBadgeLayout.maximumWidth,
            ListeningBadgeLayout().size.width
        )
    }

    func testWaveformBarsAreTwoThirdsOfPreviousThicknessAndCentered() {
        XCTAssertEqual(AudioWaveformStyle.barWidth, 1.6)
        let count = 23
        let width: CGFloat = 88
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
