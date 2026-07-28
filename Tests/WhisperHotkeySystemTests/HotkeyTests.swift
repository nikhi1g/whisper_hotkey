import CoreGraphics
import XCTest
import WhisperHotkeyCore
@testable import WhisperHotkeySystem

final class HotkeyTests: XCTestCase {
    func testRightCommandPressAndReleaseEmitExactlyOnce() {
        var reducer = GlobalInputReducer()

        XCTAssertEqual(
            reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true)),
            GlobalInputRouting(consume: true, actions: [.hotkey(.pressed)])
        )
        XCTAssertEqual(
            reducer.route(key(.keyDown, MacVirtualKey.rightCommand, command: true, repeat: true)),
            GlobalInputRouting(consume: true)
        )
        XCTAssertEqual(
            reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: false)),
            GlobalInputRouting(consume: true, actions: [.hotkey(.released)])
        )
        XCTAssertEqual(
            reducer.route(key(.keyUp, MacVirtualKey.rightCommand, command: false)),
            GlobalInputRouting(consume: true)
        )
    }

    func testRightCommandReleaseStillEmitsWhileLeftCommandKeepsFlagSet() {
        var reducer = GlobalInputReducer()
        _ = reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true))

        XCTAssertEqual(
            reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true)),
            GlobalInputRouting(consume: true, actions: [.hotkey(.released)])
        )
    }

    func testLeftCommandIsUntouched() {
        var reducer = GlobalInputReducer()

        XCTAssertEqual(
            reducer.route(key(.flagsChanged, 55, command: true)),
            GlobalInputRouting(consume: false)
        )
        XCTAssertEqual(
            reducer.route(key(.flagsChanged, 55, command: false)),
            GlobalInputRouting(consume: false)
        )
    }

    func testEscapeCancelsActiveHoldAndConsumesItsKeyPair() {
        var reducer = GlobalInputReducer()
        _ = reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true))

        XCTAssertEqual(
            reducer.route(key(.keyDown, MacVirtualKey.escape, command: true)),
            GlobalInputRouting(consume: true, actions: [.hotkey(.cancel)])
        )
        XCTAssertEqual(
            reducer.route(key(.keyUp, MacVirtualKey.escape, command: true)),
            GlobalInputRouting(consume: true)
        )
        XCTAssertEqual(
            reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: false)),
            GlobalInputRouting(consume: true)
        )
    }

    func testRightCommandSuppressesEveryOtherKeyUntilPhysicalRelease() {
        var reducer = GlobalInputReducer()
        _ = reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true))

        XCTAssertEqual(
            reducer.route(key(.keyDown, MacVirtualKey.c, command: true)),
            GlobalInputRouting(consume: true)
        )
        XCTAssertEqual(
            reducer.route(key(.keyUp, MacVirtualKey.c, command: true)),
            GlobalInputRouting(consume: true)
        )
        XCTAssertEqual(
            reducer.route(key(.flagsChanged, 56, command: true)),
            GlobalInputRouting(consume: true)
        )
        XCTAssertEqual(
            reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: false)),
            GlobalInputRouting(consume: true, actions: [.hotkey(.released)])
        )
        XCTAssertEqual(
            reducer.route(key(.keyDown, MacVirtualKey.c, command: true)),
            GlobalInputRouting(consume: false, actions: [.copyOrCut])
        )
    }

    func testEscapeKeepsOtherKeysSuppressedUntilRightCommandRelease() {
        var reducer = GlobalInputReducer()
        _ = reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true))

        XCTAssertEqual(
            reducer.route(key(.keyDown, MacVirtualKey.escape, command: true)),
            GlobalInputRouting(consume: true, actions: [.hotkey(.cancel)])
        )
        XCTAssertEqual(
            reducer.route(key(.keyDown, MacVirtualKey.v, command: true)),
            GlobalInputRouting(consume: true)
        )
        XCTAssertEqual(
            reducer.route(key(.keyUp, MacVirtualKey.escape, command: true)),
            GlobalInputRouting(consume: true)
        )
        XCTAssertEqual(
            reducer.route(key(.keyDown, 0, command: true)),
            GlobalInputRouting(consume: true)
        )
        XCTAssertEqual(
            reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: false)),
            GlobalInputRouting(consume: true)
        )
        XCTAssertEqual(
            reducer.route(key(.keyDown, 0, command: false)),
            GlobalInputRouting(consume: false)
        )
        XCTAssertNil(reducer.reset())
    }

    func testResetCancelsOneActiveHold() {
        var reducer = GlobalInputReducer()
        _ = reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true))

        XCTAssertEqual(reducer.reset(), .cancel)
        XCTAssertNil(reducer.reset())
    }

    func testToggleModeStartsAndStopsOnSuccessivePresses() {
        var reducer = GlobalInputReducer(activationMode: .toggle)

        XCTAssertEqual(
            reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true)),
            GlobalInputRouting(consume: true, actions: [.hotkey(.pressed)])
        )
        XCTAssertEqual(
            reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: false)),
            GlobalInputRouting(consume: true)
        )
        XCTAssertEqual(
            reducer.route(key(.keyDown, 0, command: false)),
            GlobalInputRouting(consume: false)
        )
        XCTAssertEqual(
            reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true)),
            GlobalInputRouting(consume: true, actions: [.hotkey(.released)])
        )
        XCTAssertEqual(
            reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: false)),
            GlobalInputRouting(consume: true)
        )
    }

    func testEscapeCancelsToggleSessionAfterCommandIsReleased() {
        var reducer = GlobalInputReducer(activationMode: .toggle)
        _ = reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true))
        _ = reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: false))

        XCTAssertEqual(
            reducer.route(key(.keyDown, MacVirtualKey.escape, command: false)),
            GlobalInputRouting(consume: true, actions: [.hotkey(.cancel)])
        )
        XCTAssertEqual(
            reducer.route(key(.keyUp, MacVirtualKey.escape, command: false)),
            GlobalInputRouting(consume: true)
        )
        XCTAssertNil(reducer.reset())
    }

    func testChangingModeCancelsActiveToggleAndResetsGesture() {
        var reducer = GlobalInputReducer(activationMode: .toggle)
        _ = reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true))
        _ = reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: false))

        XCTAssertEqual(reducer.setActivationMode(.hold), .cancel)
        XCTAssertEqual(reducer.activationMode, .hold)
        XCTAssertNil(reducer.reset())
        XCTAssertEqual(
            reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true)),
            GlobalInputRouting(consume: true, actions: [.hotkey(.pressed)])
        )
    }

    func testRejectedToggleStartCanBeSynchronizedBackToIdle() {
        var reducer = GlobalInputReducer(activationMode: .toggle)
        _ = reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true))
        _ = reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: false))
        reducer.synchronizeToggleSession(isActive: false)

        XCTAssertNil(reducer.reset())
        XCTAssertEqual(
            reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true)),
            GlobalInputRouting(consume: true, actions: [.hotkey(.pressed)])
        )
    }

    func testClipboardShortcutsAreObservedButNotConsumed() {
        var reducer = GlobalInputReducer()

        XCTAssertEqual(
            reducer.route(key(.keyDown, MacVirtualKey.v, command: true)),
            GlobalInputRouting(consume: false, actions: [.manualPaste])
        )
        XCTAssertEqual(
            reducer.route(key(.keyDown, MacVirtualKey.c, command: true)),
            GlobalInputRouting(consume: false, actions: [.copyOrCut])
        )
    }

    private func key(
        _ kind: GlobalKeyEventKind,
        _ keyCode: Int64,
        command: Bool,
        repeat isAutoRepeat: Bool = false
    ) -> GlobalKeyEvent {
        GlobalKeyEvent(
            kind: kind,
            keyCode: keyCode,
            commandIsDown: command,
            isAutoRepeat: isAutoRepeat
        )
    }
}

@MainActor
final class GlobalHotkeyMonitorDeliveryTests: XCTestCase {
    func testHotkeyDeliveryIsDeferredOrderedAndUsesPhysicalTimestamps() async {
        var deliveries: [(HotkeyAction, UInt64)] = []
        var didCaptureReleaseTarget = false
        let delivered = expectation(description: "ordered hotkey delivery")
        delivered.expectedFulfillmentCount = 2
        let monitor = GlobalHotkeyMonitor(
            captureReleaseTarget: {
                didCaptureReleaseTarget = true
                return nil
            },
            clipboard: ClipboardTransactionController()
        ) { action, _, timestampNanoseconds in
            deliveries.append((action, timestampNanoseconds))
            delivered.fulfill()
        }
        let press = event(
            keyCode: MacVirtualKey.rightCommand,
            commandIsDown: true,
            timestampNanoseconds: 1_000
        )
        let release = event(
            keyCode: MacVirtualKey.rightCommand,
            commandIsDown: false,
            timestampNanoseconds: 1_250
        )

        XCTAssertTrue(
            monitor.shouldConsumeTapEvent(type: .flagsChanged, event: press)
        )
        XCTAssertTrue(
            monitor.shouldConsumeTapEvent(type: .flagsChanged, event: release)
        )
        XCTAssertTrue(deliveries.isEmpty)
        XCTAssertFalse(didCaptureReleaseTarget)

        await fulfillment(of: [delivered], timeout: 1)
        XCTAssertEqual(deliveries.map(\.0), [.pressed, .released])
        XCTAssertEqual(deliveries.map(\.1), [1_000, 1_250])
        XCTAssertTrue(didCaptureReleaseTarget)
    }

    func testToggleSecondPressCapturesInsertionTarget() async {
        var deliveries: [HotkeyAction] = []
        var targetCaptureCount = 0
        let delivered = expectation(description: "toggle start and finish")
        delivered.expectedFulfillmentCount = 2
        let monitor = GlobalHotkeyMonitor(
            captureReleaseTarget: {
                targetCaptureCount += 1
                return nil
            },
            clipboard: ClipboardTransactionController()
        ) { action, _, _ in
            deliveries.append(action)
            delivered.fulfill()
        }
        monitor.setActivationMode(.toggle)

        XCTAssertTrue(
            monitor.shouldConsumeTapEvent(
                type: .flagsChanged,
                event: event(
                    keyCode: MacVirtualKey.rightCommand,
                    commandIsDown: true,
                    timestampNanoseconds: 10_000
                )
            )
        )
        XCTAssertTrue(
            monitor.shouldConsumeTapEvent(
                type: .flagsChanged,
                event: event(
                    keyCode: MacVirtualKey.rightCommand,
                    commandIsDown: false,
                    timestampNanoseconds: 10_100
                )
            )
        )
        XCTAssertTrue(
            monitor.shouldConsumeTapEvent(
                type: .flagsChanged,
                event: event(
                    keyCode: MacVirtualKey.rightCommand,
                    commandIsDown: true,
                    timestampNanoseconds: 11_000
                )
            )
        )

        await fulfillment(of: [delivered], timeout: 1)
        XCTAssertEqual(deliveries, [.pressed, .released])
        XCTAssertEqual(targetCaptureCount, 1)
    }

    func testTapDisableCancellationUsesDisablingEventTimestamp() async {
        var deliveries: [(HotkeyAction, UInt64)] = []
        let delivered = expectation(description: "press and cancellation")
        delivered.expectedFulfillmentCount = 2
        let monitor = GlobalHotkeyMonitor(
            captureReleaseTarget: { nil },
            clipboard: ClipboardTransactionController()
        ) { action, _, timestampNanoseconds in
            deliveries.append((action, timestampNanoseconds))
            delivered.fulfill()
        }
        let press = event(
            keyCode: MacVirtualKey.rightCommand,
            commandIsDown: true,
            timestampNanoseconds: 2_000
        )
        let disabled = event(
            keyCode: 0,
            commandIsDown: false,
            timestampNanoseconds: 2_100
        )

        XCTAssertTrue(
            monitor.shouldConsumeTapEvent(type: .flagsChanged, event: press)
        )
        XCTAssertFalse(
            monitor.shouldConsumeTapEvent(
                type: .tapDisabledByTimeout,
                event: disabled
            )
        )
        XCTAssertTrue(deliveries.isEmpty)

        await fulfillment(of: [delivered], timeout: 1)
        XCTAssertEqual(deliveries.map(\.0), [.pressed, .cancel])
        XCTAssertEqual(deliveries.map(\.1), [2_000, 2_100])
    }

    func testClipboardNotificationsRemainOrderedAndSyntheticPasteIsIgnored() async {
        let pasteboard = HotkeyTestPasteboard()
        let clipboard = ClipboardTransactionController(
            pasteboard: pasteboard,
            restorationDelay: 0.001
        )
        XCTAssertTrue(clipboard.installLease("transcript"))

        var deliveries: [String] = []
        let delivered = expectation(description: "ordered action delivery")
        delivered.expectedFulfillmentCount = 4
        clipboard.onLeaseStateChange = { phase in
            deliveries.append(String(describing: phase))
            delivered.fulfill()
        }
        let monitor = GlobalHotkeyMonitor(
            captureReleaseTarget: { nil },
            clipboard: clipboard
        ) { action, _, _ in
            deliveries.append(String(describing: action))
            delivered.fulfill()
        }
        let press = event(
            keyCode: MacVirtualKey.rightCommand,
            commandIsDown: true,
            timestampNanoseconds: 3_000
        )
        let release = event(
            keyCode: MacVirtualKey.rightCommand,
            commandIsDown: false,
            timestampNanoseconds: 3_050
        )
        let syntheticPaste = event(
            keyCode: MacVirtualKey.v,
            commandIsDown: true,
            timestampNanoseconds: 3_100,
            synthetic: true
        )
        let manualPaste = event(
            keyCode: MacVirtualKey.v,
            commandIsDown: true,
            timestampNanoseconds: 3_200
        )
        let copy = event(
            keyCode: MacVirtualKey.c,
            commandIsDown: true,
            timestampNanoseconds: 3_300
        )

        XCTAssertTrue(
            monitor.shouldConsumeTapEvent(type: .flagsChanged, event: press)
        )
        XCTAssertTrue(
            monitor.shouldConsumeTapEvent(type: .flagsChanged, event: release)
        )
        XCTAssertFalse(
            monitor.shouldConsumeTapEvent(type: .keyDown, event: syntheticPaste)
        )
        XCTAssertFalse(
            monitor.shouldConsumeTapEvent(type: .keyDown, event: manualPaste)
        )
        XCTAssertFalse(
            monitor.shouldConsumeTapEvent(type: .keyDown, event: copy)
        )
        XCTAssertTrue(deliveries.isEmpty)

        await fulfillment(of: [delivered], timeout: 1)
        XCTAssertEqual(
            deliveries,
            ["pressed", "released", "restorationPending", "inactive"]
        )
    }

    private func event(
        keyCode: Int64,
        commandIsDown: Bool,
        timestampNanoseconds: UInt64,
        synthetic: Bool = false
    ) -> CGEvent {
        let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(keyCode),
            keyDown: commandIsDown
        )!
        event.flags = commandIsDown ? .maskCommand : []
        event.timestamp = timestampNanoseconds
        if synthetic {
            event.setIntegerValueField(
                .eventSourceUserData,
                value: GlobalHotkeyMonitor.syntheticEventMarker
            )
        }
        return event
    }
}

@MainActor
private final class HotkeyTestPasteboard: PasteboardAccess {
    private(set) var changeCount = 1

    func snapshotReadableContents() -> ClipboardSnapshot {
        ClipboardSnapshot(items: [])
    }

    func replaceContents(withPlainText _: String) -> Int? {
        changeCount += 1
        return changeCount
    }

    func restore(_: ClipboardSnapshot) -> Int {
        changeCount += 1
        return changeCount
    }
}
