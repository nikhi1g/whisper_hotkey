import AppKit
import XCTest
@testable import WhisperHotkeyShell

final class ListeningBadgeTests: XCTestCase {
    func testNormalTimerShowsOnlyElapsedTime() {
        let metrics = ListeningBadgeMetrics(elapsed: 65.9, limit: 600)
        XCTAssertEqual(metrics.timeText, "1:05")
        XCTAssertEqual(
            metrics.accessibilityText,
            "1:05 of 10:00, 8:55 remaining"
        )
        XCTAssertFalse(metrics.isWarning)
        XCTAssertEqual(metrics.warningProgress, 0)
        XCTAssertEqual(metrics.progress, 65.9 / 600, accuracy: 0.001)
    }

    func testFinalMinuteShowsRemainingCountdownAndWarningProgress() {
        let metrics = ListeningBadgeMetrics(elapsed: 575, limit: 600)
        XCTAssertEqual(metrics.timeText, "0:25 left")
        XCTAssertTrue(metrics.isWarning)
        XCTAssertEqual(metrics.warningProgress, 35.0 / 60.0, accuracy: 0.001)

        let beforeWarning = ListeningBadgeMetrics(
            elapsed: 539.9,
            limit: 600
        )
        XCTAssertEqual(beforeWarning.timeText, "8:59")
        XCTAssertFalse(beforeWarning.isWarning)

        let warningBoundary = ListeningBadgeMetrics(
            elapsed: 540,
            limit: 600
        )
        XCTAssertEqual(warningBoundary.timeText, "1:00 left")
        XCTAssertTrue(warningBoundary.isWarning)
        XCTAssertEqual(warningBoundary.warningProgress, 0)
    }

    func testHourLimitUsesCompactFinalMinuteCountdown() {
        let metrics = ListeningBadgeMetrics(elapsed: 3_575, limit: 3_600)
        XCTAssertEqual(metrics.timeText, "0:25 left")
        XCTAssertTrue(metrics.isWarning)
    }

    func testThirtySecondLimitUsesItsWholeDurationForWarningShift() {
        let start = ListeningBadgeMetrics(elapsed: 0, limit: 30)
        XCTAssertEqual(start.timeText, "0:30 left")
        XCTAssertTrue(start.isWarning)
        XCTAssertEqual(start.warningProgress, 0)

        let halfway = ListeningBadgeMetrics(elapsed: 15, limit: 30)
        XCTAssertEqual(halfway.timeText, "0:15 left")
        XCTAssertEqual(halfway.warningProgress, 0.5)
    }

    func testLimitProgressClampsAtBothEnds() {
        XCTAssertEqual(
            ListeningBadgeMetrics(elapsed: -10, limit: 300).progress,
            0
        )
        let completed = ListeningBadgeMetrics(elapsed: 400, limit: 300)
        XCTAssertEqual(completed.progress, 1)
        XCTAssertEqual(completed.timeText, "0:00 left")
        XCTAssertEqual(
            completed.accessibilityText,
            "5:00 of 5:00, 0:00 remaining"
        )
    }

    @MainActor
    func testLongestVisibleCountdownFitsItsCenteredTimerCell() {
        let label = NSTextField(labelWithString: "1:00 left")
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
    func testLimitTrackAppearsOnlyDuringFinalMinute() {
        let controller = CaretBadgeController()
        controller.present(
            .listening,
            caretFrame: CGRect(x: 200, y: 200, width: 1, height: 18),
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
        )

        controller.updateListening(elapsed: 10, limit: 300, level: 0.3)
        XCTAssertEqual(controller.listeningTextForTesting, "0:10")
        XCTAssertFalse(controller.limitTrackIsVisibleForTesting)

        controller.updateListening(elapsed: 245, limit: 300, level: 0.3)
        XCTAssertEqual(controller.listeningTextForTesting, "0:55 left")
        XCTAssertTrue(controller.limitTrackIsVisibleForTesting)
        let orange = try? XCTUnwrap(
            controller.listeningTimerColorForTesting.usingColorSpace(
                .deviceRGB
            )
        )

        controller.updateListening(elapsed: 299, limit: 300, level: 0.3)
        let nearRed = try? XCTUnwrap(
            controller.listeningTimerColorForTesting.usingColorSpace(
                .deviceRGB
            )
        )
        XCTAssertGreaterThan(
            orange?.greenComponent ?? 0,
            nearRed?.greenComponent ?? 1
        )
        controller.hide()
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
    func testControllerKeepsInitialFrameAcrossStateAndAnchorChanges() {
        let controller = CaretBadgeController()
        controller.present(
            .listening,
            caretFrame: CGRect(x: 200, y: 200, width: 1, height: 18),
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
        )
        let listeningFrame = controller.panelFrameForTesting

        controller.present(
            .transcribing,
            caretFrame: CGRect(x: 900, y: 600, width: 1, height: 18),
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
        )
        XCTAssertEqual(controller.panelFrameForTesting, listeningFrame)

        controller.present(
            .error("Try again"),
            caretFrame: nil,
            fieldFrame: CGRect(x: 40, y: 50, width: 400, height: 60),
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
        )
        XCTAssertEqual(controller.panelFrameForTesting, listeningFrame)

        controller.present(
            .busy,
            caretFrame: CGRect(x: 1_100, y: 700, width: 1, height: 18),
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
        )
        XCTAssertEqual(controller.panelFrameForTesting, listeningFrame)
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
    func testRepeatedSessionsReuseOneRegisteredPanel() {
        let baseline = CaretBadgeController.registeredPanelCountForTesting
        let controller = CaretBadgeController()
        let countWithController = CaretBadgeController.registeredPanelCountForTesting
        XCTAssertEqual(countWithController, baseline + 1)
        XCTAssertFalse(controller.panelCanHideForTesting)
        let panelIdentifier = controller.panelIdentifierForTesting

        let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        for index in 0..<100 {
            controller.present(
                .listening,
                caretFrame: CGRect(
                    x: 200 + CGFloat(index),
                    y: 200,
                    width: 1,
                    height: 18
                ),
                screenFrame: screen
            )
            controller.hide()
            XCTAssertEqual(
                controller.panelIdentifierForTesting,
                panelIdentifier,
                "Session \(index) replaced the reusable AppKit panel"
            )
            XCTAssertEqual(
                CaretBadgeController.registeredPanelCountForTesting,
                countWithController,
                "Session \(index) retained a superseded AppKit panel"
            )
        }
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

    @MainActor
    func testListeningBackgroundDragsWithoutStealingButtonHitboxes() {
        let controller = CaretBadgeController()
        let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        controller.present(
            .listening,
            caretFrame: CGRect(x: 200, y: 200, width: 1, height: 18),
            screenFrame: screen
        )
        let layout = ListeningBadgeLayout()

        XCTAssertTrue(
            controller.badgeBackgroundIsDraggableForTesting(
                at: CGPoint(
                    x: layout.timeFrame.midX,
                    y: layout.timeFrame.midY
                )
            )
        )
        XCTAssertFalse(
            controller.badgeBackgroundIsDraggableForTesting(
                at: CGPoint(
                    x: layout.stopButtonFrame.midX,
                    y: layout.stopButtonFrame.midY
                )
            )
        )
        XCTAssertFalse(
            controller.badgeBackgroundIsDraggableForTesting(
                at: CGPoint(
                    x: layout.sendButtonFrame.midX,
                    y: layout.sendButtonFrame.midY
                )
            )
        )
        controller.hide()
    }

    @MainActor
    func testDraggedOriginPersistsAcrossUpdatesAndStatusChanges() {
        let controller = CaretBadgeController()
        let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        controller.present(
            .listening,
            caretFrame: CGRect(x: 200, y: 200, width: 1, height: 18),
            screenFrame: screen
        )

        controller.dragBadgeForTesting(to: CGPoint(x: 640, y: 420))
        let draggedFrame = controller.panelFrameForTesting
        XCTAssertEqual(draggedFrame.origin, CGPoint(x: 640, y: 420))

        controller.updateListening(elapsed: 15, limit: 300, level: 0.5)
        XCTAssertEqual(controller.panelFrameForTesting, draggedFrame)

        controller.present(.transcribing, screenFrame: screen)
        XCTAssertEqual(controller.panelFrameForTesting, draggedFrame)
        controller.hide()
    }

    @MainActor
    func testUndraggedBadgeSnapsToNewFocusedField() {
        let controller = CaretBadgeController()
        let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        controller.present(
            .listening,
            caretFrame: CGRect(x: 200, y: 200, width: 1, height: 18),
            fieldFrame: CGRect(x: 180, y: 180, width: 500, height: 60),
            screenFrame: screen
        )
        let originalFrame = controller.panelFrameForTesting

        XCTAssertTrue(controller.acceptsAutomaticAnchorUpdates)
        XCTAssertTrue(
            controller.updateAutomaticAnchor(
                caretFrame: CGRect(x: 800, y: 500, width: 1, height: 18),
                fieldFrame: CGRect(x: 760, y: 480, width: 500, height: 60),
                screenFrame: screen
            )
        )
        XCTAssertNotEqual(controller.panelFrameForTesting, originalFrame)
        XCTAssertEqual(
            controller.panelFrameForTesting,
            BadgePlacement.frame(
                caretFrame: CGRect(x: 800, y: 500, width: 1, height: 18),
                fieldFrame: CGRect(x: 760, y: 480, width: 500, height: 60),
                screenFrame: screen,
                badgeSize: ListeningBadgeLayout().size
            )
        )
        controller.hide()
    }

    @MainActor
    func testDraggingLocksAutomaticPlacementUntilNextSession() {
        let controller = CaretBadgeController()
        let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        controller.present(
            .listening,
            caretFrame: CGRect(x: 200, y: 200, width: 1, height: 18),
            screenFrame: screen
        )
        controller.dragBadgeForTesting(to: CGPoint(x: 640, y: 420))
        let draggedFrame = controller.panelFrameForTesting

        XCTAssertFalse(controller.acceptsAutomaticAnchorUpdates)
        XCTAssertFalse(
            controller.updateAutomaticAnchor(
                caretFrame: CGRect(x: 800, y: 500, width: 1, height: 18),
                fieldFrame: nil,
                screenFrame: screen
            )
        )
        XCTAssertEqual(controller.panelFrameForTesting, draggedFrame)

        controller.hide()
        controller.present(
            .listening,
            caretFrame: CGRect(x: 200, y: 200, width: 1, height: 18),
            screenFrame: screen
        )
        XCTAssertTrue(controller.acceptsAutomaticAnchorUpdates)
        controller.hide()
    }

    @MainActor
    func testInaccessibleFocusChangePreservesAutomaticBadgePosition() {
        let controller = CaretBadgeController()
        let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        controller.present(
            .listening,
            caretFrame: CGRect(x: 200, y: 200, width: 1, height: 18),
            screenFrame: screen
        )
        let originalFrame = controller.panelFrameForTesting

        XCTAssertFalse(
            controller.updateAutomaticAnchor(
                caretFrame: nil,
                fieldFrame: nil,
                screenFrame: screen
            )
        )
        XCTAssertEqual(controller.panelFrameForTesting, originalFrame)
        XCTAssertTrue(controller.acceptsAutomaticAnchorUpdates)
        controller.hide()
    }

    @MainActor
    func testDraggingClampsTheWholeBadgeInsideItsSessionScreen() {
        let controller = CaretBadgeController()
        let screen = CGRect(x: 0, y: 0, width: 300, height: 200)
        controller.present(
            .listening,
            caretFrame: CGRect(x: 100, y: 100, width: 1, height: 18),
            screenFrame: screen
        )

        controller.dragBadgeForTesting(to: CGPoint(x: 500, y: -100))
        XCTAssertEqual(
            controller.panelFrameForTesting,
            CGRect(
                x: screen.maxX - 8 - ListeningBadgeLayout().size.width,
                y: screen.minY + 8,
                width: ListeningBadgeLayout().size.width,
                height: ListeningBadgeLayout().size.height
            )
        )
        controller.hide()
    }

    @MainActor
    func testPointerFallbackPlacesClickableSendButtonUnderPointer() {
        var submitted = 0
        let controller = CaretBadgeController(
            actions: CaretBadgeActions(
                stopAndInsert: {},
                sendAndSubmit: { submitted += 1 }
            )
        )
        let pointer = CGPoint(x: 700, y: 500)
        controller.present(
            .listening,
            caretFrame: nil,
            fieldFrame: nil,
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            pointerLocation: pointer
        )
        let frame = controller.panelFrameForTesting
        let sendButtonFrame = ListeningBadgeLayout().sendButtonFrame
        let localPointer = CGPoint(
            x: pointer.x - frame.minX,
            y: pointer.y - frame.minY
        )

        XCTAssertEqual(localPointer.x, sendButtonFrame.midX)
        XCTAssertEqual(localPointer.y, sendButtonFrame.midY)
        controller.clickBadgeForTesting(at: localPointer)
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
        XCTAssertEqual(layout.size, CGSize(width: 218, height: 44))
        XCTAssertEqual(layout.waveformFrame.minX, 10)
        XCTAssertEqual(layout.timeFrame.width, 50)
        XCTAssertEqual(layout.size.width - layout.sendButtonFrame.maxX, 10)
        XCTAssertEqual(
            layout.timeFrame.minX - layout.waveformFrame.maxX,
            2
        )
        XCTAssertEqual(
            layout.stopButtonFrame.minX - layout.timeFrame.maxX,
            2
        )
        XCTAssertEqual(
            layout.sendButtonFrame.minX - layout.stopButtonFrame.maxX,
            2
        )
        XCTAssertEqual(
            layout.stopButtonFrame.width,
            layout.stopButtonFrame.height
        )
        XCTAssertEqual(
            layout.sendButtonFrame.width,
            layout.sendButtonFrame.height
        )
        XCTAssertEqual(layout.stopButtonFrame.minY, 6)
        XCTAssertEqual(layout.sendButtonFrame.minY, 5)
        XCTAssertEqual(layout.limitTrackFrame.minX, 13)
        XCTAssertEqual(layout.size.width - layout.limitTrackFrame.maxX, 13)
        XCTAssertEqual(layout.limitTrackFrame.minY, 4)
        XCTAssertEqual(layout.limitTrackFrame.height, 1.5)
        XCTAssertEqual(RuntimeBadgeLayout.size, layout.size)
    }

    @MainActor
    func testBadgeUsesBorderlessFlatVisualStyleEvenDuringWarning() {
        let controller = CaretBadgeController()
        controller.present(
            .listening,
            caretFrame: CGRect(x: 200, y: 200, width: 1, height: 18),
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
        )
        controller.updateListening(
            elapsed: 295,
            limit: 300,
            level: 0.5
        )

        XCTAssertEqual(
            controller.visualStyleForTesting,
            BadgeVisualStyleSnapshot(
                borderWidth: 0,
                hasGradientLayer: false,
                hasShadow: true,
                usesContinuousCorners: true
            )
        )
        controller.hide()
    }

    func testEveryBadgeLabelIsGeometricallyCenteredWithMargins() {
        let listening = ListeningBadgeLayout()
        let timerFrame = BadgeTextLayout.centeredFrame(
            in: listening.timeFrame,
            contentHeight: 15.2
        )
        XCTAssertEqual(timerFrame.midX, listening.timeFrame.midX)
        XCTAssertEqual(timerFrame.midY, listening.timeFrame.midY)

        let statusSize = StatusBadgeLayout.size
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
        XCTAssertEqual(statusSize, ListeningBadgeLayout().size)
    }

    func testWaveformBarsAreTwoThirdsOfPreviousThicknessAndCentered() {
        XCTAssertEqual(AudioWaveformStyle.barWidth, 1.6)
        let count = 23
        let width: CGFloat = 76
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
