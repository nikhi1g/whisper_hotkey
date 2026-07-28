import CoreGraphics
import XCTest
import WhisperHotkeyCore
@testable import WhisperHotkeySystem

final class HotkeyTests: XCTestCase {
    func testBareHoldArmsThenEmitsAfterDwellAndRelease() {
        var reducer = GlobalInputReducer()

        XCTAssertEqual(
            reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true)),
            GlobalInputRouting(consume: false, actions: [.armHold])
        )
        XCTAssertEqual(reducer.holdActivationFired(), .pressed)
        XCTAssertEqual(
            reducer.route(key(.keyDown, MacVirtualKey.rightCommand, command: true, repeat: true)),
            GlobalInputRouting(consume: false)
        )
        XCTAssertEqual(
            reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: false)),
            GlobalInputRouting(
                consume: false,
                actions: [.disarmHold, .hotkey(.released)]
            )
        )
        XCTAssertEqual(
            reducer.route(key(.keyUp, MacVirtualKey.rightCommand, command: false)),
            GlobalInputRouting(consume: false)
        )
    }

    func testRightCommandReleaseStillEmitsWhileLeftCommandKeepsFlagSet() {
        var reducer = GlobalInputReducer()
        _ = reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true))
        XCTAssertEqual(reducer.holdActivationFired(), .pressed)

        XCTAssertEqual(
            reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true)),
            GlobalInputRouting(
                consume: false,
                actions: [.disarmHold, .hotkey(.released)]
            )
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

    func testCommandChordBeforeDwellPassesThroughWithoutDictation() {
        var reducer = GlobalInputReducer()
        _ = reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true))

        XCTAssertEqual(
            reducer.route(key(.keyDown, MacVirtualKey.c, command: true)),
            GlobalInputRouting(
                consume: false,
                actions: [.disarmHold]
            )
        )
        XCTAssertNil(reducer.holdActivationFired())
        XCTAssertEqual(
            reducer.route(key(.keyUp, MacVirtualKey.c, command: true)),
            GlobalInputRouting(consume: false)
        )
        XCTAssertEqual(
            reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: false)),
            GlobalInputRouting(consume: false, actions: [.disarmHold])
        )
    }

    func testCommandChordAfterDwellCancelsDictationAndPassesThrough() {
        var reducer = GlobalInputReducer()
        _ = reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true))
        XCTAssertEqual(reducer.holdActivationFired(), .pressed)

        XCTAssertEqual(
            reducer.route(key(.keyDown, MacVirtualKey.c, command: true)),
            GlobalInputRouting(
                consume: false,
                actions: [.disarmHold, .hotkey(.cancel)]
            )
        )
        XCTAssertEqual(
            reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: false)),
            GlobalInputRouting(consume: false, actions: [.disarmHold])
        )
        XCTAssertNil(reducer.reset())
    }

    func testOtherModifierMarksRightCommandAsAChord() {
        var reducer = GlobalInputReducer()
        _ = reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true))

        XCTAssertEqual(
            reducer.route(key(.flagsChanged, 56, command: true)),
            GlobalInputRouting(consume: false, actions: [.disarmHold])
        )
        XCTAssertNil(reducer.holdActivationFired())
    }

    func testCommandClickMarksRightCommandAsAChord() {
        var reducer = GlobalInputReducer()
        _ = reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true))

        XCTAssertEqual(
            reducer.routePointerDown(),
            GlobalInputRouting(consume: false, actions: [.disarmHold])
        )
        XCTAssertNil(reducer.holdActivationFired())
    }

    func testEscapeCancelsActiveHoldAndConsumesItsKeyPair() {
        var reducer = GlobalInputReducer()
        _ = reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true))
        XCTAssertEqual(reducer.holdActivationFired(), .pressed)

        XCTAssertEqual(
            reducer.route(key(.keyDown, MacVirtualKey.escape, command: true)),
            GlobalInputRouting(
                consume: true,
                actions: [.disarmHold, .hotkey(.cancel)]
            )
        )
        XCTAssertEqual(
            reducer.route(key(.keyUp, MacVirtualKey.escape, command: true)),
            GlobalInputRouting(consume: true)
        )
        XCTAssertEqual(
            reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: false)),
            GlobalInputRouting(consume: false, actions: [.disarmHold])
        )
    }

    func testCommandEscapeBeforeDwellPassesThrough() {
        var reducer = GlobalInputReducer()
        _ = reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true))

        XCTAssertEqual(
            reducer.route(key(.keyDown, MacVirtualKey.escape, command: true)),
            GlobalInputRouting(consume: false, actions: [.disarmHold])
        )
        XCTAssertNil(reducer.reset())
    }

    func testResetDoesNotCancelAnArmedButUnstartedHold() {
        var reducer = GlobalInputReducer()
        _ = reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true))

        XCTAssertNil(reducer.reset())
    }

    func testResetCancelsOneActiveHold() {
        var reducer = GlobalInputReducer()
        _ = reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true))
        _ = reducer.holdActivationFired()

        XCTAssertEqual(reducer.reset(), .cancel)
        XCTAssertNil(reducer.reset())
    }

    func testToggleModeStartsAndStopsOnSuccessivePresses() {
        var reducer = GlobalInputReducer(activationMode: .toggle)

        XCTAssertEqual(
            reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true)),
            GlobalInputRouting(consume: false)
        )
        XCTAssertEqual(
            reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: false)),
            GlobalInputRouting(consume: false, actions: [.hotkey(.pressed)])
        )
        XCTAssertEqual(
            reducer.route(key(.keyDown, 0, command: false)),
            GlobalInputRouting(consume: false)
        )
        XCTAssertEqual(
            reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true)),
            GlobalInputRouting(consume: false)
        )
        XCTAssertEqual(
            reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: false)),
            GlobalInputRouting(consume: false, actions: [.hotkey(.released)])
        )
    }

    func testToggleModeCommandChordDoesNotToggleSession() {
        var reducer = GlobalInputReducer(activationMode: .toggle)
        _ = reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true))

        XCTAssertEqual(
            reducer.route(key(.keyDown, MacVirtualKey.c, command: true)),
            GlobalInputRouting(consume: false)
        )
        XCTAssertEqual(
            reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: false)),
            GlobalInputRouting(consume: false)
        )
        XCTAssertNil(reducer.reset())

        _ = reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true))
        XCTAssertEqual(
            reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: false)),
            GlobalInputRouting(consume: false, actions: [.hotkey(.pressed)])
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
            GlobalInputRouting(consume: false, actions: [.armHold])
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
            GlobalInputRouting(consume: false)
        )
        XCTAssertEqual(
            reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: false)),
            GlobalInputRouting(consume: false, actions: [.hotkey(.pressed)])
        )
    }

    func testOrdinaryCommandShortcutsPassWithoutActions() {
        var reducer = GlobalInputReducer()

        XCTAssertEqual(
            reducer.route(key(.keyDown, MacVirtualKey.v, command: true)),
            GlobalInputRouting(consume: false)
        )
        XCTAssertEqual(
            reducer.route(key(.keyDown, MacVirtualKey.c, command: true)),
            GlobalInputRouting(consume: false)
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
        let started = expectation(description: "hold started after dwell")
        let released = expectation(description: "hold released")
        let monitor = GlobalHotkeyMonitor(
            captureReleaseTarget: {
                didCaptureReleaseTarget = true
                return nil
            },
            holdActivationDelay: .milliseconds(1)
        ) { action, _, timestampNanoseconds in
            deliveries.append((action, timestampNanoseconds))
            if action == .pressed {
                started.fulfill()
            } else if action == .released {
                released.fulfill()
            }
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

        XCTAssertFalse(
            monitor.shouldConsumeTapEvent(type: .flagsChanged, event: press)
        )
        await fulfillment(of: [started], timeout: 1)
        XCTAssertEqual(deliveries.map(\.0), [.pressed])
        XCTAssertFalse(didCaptureReleaseTarget)

        XCTAssertFalse(
            monitor.shouldConsumeTapEvent(type: .flagsChanged, event: release)
        )
        await fulfillment(of: [released], timeout: 1)
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
            }
        ) { action, _, _ in
            deliveries.append(action)
            delivered.fulfill()
        }
        monitor.setActivationMode(.toggle)

        XCTAssertFalse(
            monitor.shouldConsumeTapEvent(
                type: .flagsChanged,
                event: event(
                    keyCode: MacVirtualKey.rightCommand,
                    commandIsDown: true,
                    timestampNanoseconds: 10_000
                )
            )
        )
        XCTAssertFalse(
            monitor.shouldConsumeTapEvent(
                type: .flagsChanged,
                event: event(
                    keyCode: MacVirtualKey.rightCommand,
                    commandIsDown: false,
                    timestampNanoseconds: 10_100
                )
            )
        )
        XCTAssertFalse(
            monitor.shouldConsumeTapEvent(
                type: .flagsChanged,
                event: event(
                    keyCode: MacVirtualKey.rightCommand,
                    commandIsDown: true,
                    timestampNanoseconds: 11_000
                )
            )
        )
        XCTAssertFalse(
            monitor.shouldConsumeTapEvent(
                type: .flagsChanged,
                event: event(
                    keyCode: MacVirtualKey.rightCommand,
                    commandIsDown: false,
                    timestampNanoseconds: 11_100
                )
            )
        )

        await fulfillment(of: [delivered], timeout: 1)
        XCTAssertEqual(deliveries, [.pressed, .released])
        XCTAssertEqual(targetCaptureCount, 1)
    }

    func testTapDisableCancellationUsesDisablingEventTimestamp() async {
        var deliveries: [(HotkeyAction, UInt64)] = []
        let started = expectation(description: "hold started")
        let cancelled = expectation(description: "hold cancelled")
        let monitor = GlobalHotkeyMonitor(
            captureReleaseTarget: { nil },
            holdActivationDelay: .milliseconds(1)
        ) { action, _, timestampNanoseconds in
            deliveries.append((action, timestampNanoseconds))
            if action == .pressed {
                started.fulfill()
            } else if action == .cancel {
                cancelled.fulfill()
            }
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

        XCTAssertFalse(
            monitor.shouldConsumeTapEvent(type: .flagsChanged, event: press)
        )
        await fulfillment(of: [started], timeout: 1)
        XCTAssertFalse(
            monitor.shouldConsumeTapEvent(
                type: .tapDisabledByTimeout,
                event: disabled
            )
        )
        await fulfillment(of: [cancelled], timeout: 1)
        XCTAssertEqual(deliveries.map(\.0), [.pressed, .cancel])
        XCTAssertEqual(deliveries.map(\.1), [2_000, 2_100])
    }

    func testCommandChordCancelsPendingHoldTimer() async {
        var deliveries: [HotkeyAction] = []
        let unexpectedDelivery = expectation(description: "no dictation")
        unexpectedDelivery.isInverted = true
        let monitor = GlobalHotkeyMonitor(
            captureReleaseTarget: { nil },
            holdActivationDelay: .milliseconds(20)
        ) { action, _, _ in
            deliveries.append(action)
            unexpectedDelivery.fulfill()
        }
        let press = event(
            keyCode: MacVirtualKey.rightCommand,
            commandIsDown: true,
            timestampNanoseconds: 3_000
        )
        let shortcut = event(
            keyCode: MacVirtualKey.c,
            commandIsDown: true,
            timestampNanoseconds: 3_050
        )
        let release = event(
            keyCode: MacVirtualKey.rightCommand,
            commandIsDown: false,
            timestampNanoseconds: 3_100
        )

        XCTAssertFalse(
            monitor.shouldConsumeTapEvent(type: .flagsChanged, event: press)
        )
        XCTAssertFalse(
            monitor.shouldConsumeTapEvent(type: .keyDown, event: shortcut)
        )
        XCTAssertFalse(
            monitor.shouldConsumeTapEvent(type: .flagsChanged, event: release)
        )

        await fulfillment(of: [unexpectedDelivery], timeout: 0.08)
        XCTAssertTrue(deliveries.isEmpty)
    }

    private func event(
        keyCode: Int64,
        commandIsDown: Bool,
        timestampNanoseconds: UInt64
    ) -> CGEvent {
        let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(keyCode),
            keyDown: commandIsDown
        )!
        event.flags = commandIsDown ? .maskCommand : []
        event.timestamp = timestampNanoseconds
        return event
    }
}
