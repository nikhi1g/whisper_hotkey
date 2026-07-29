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

    func testEscapeStopsAndInsertsActiveHoldAndConsumesItsKeyPair() {
        var reducer = GlobalInputReducer()
        _ = reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true))
        XCTAssertEqual(reducer.holdActivationFired(), .pressed)

        XCTAssertEqual(
            reducer.route(key(.keyDown, MacVirtualKey.escape, command: true)),
            GlobalInputRouting(
                consume: true,
                actions: [.disarmHold, .hotkey(.stopAndInsert)]
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

    func testPauseModeUsesSuccessivePressesLikeAToggleSession() {
        var reducer = GlobalInputReducer(activationMode: .pause)

        _ = reducer.route(
            key(
                .flagsChanged,
                MacVirtualKey.rightCommand,
                command: true
            )
        )
        XCTAssertEqual(
            reducer.route(
                key(
                    .flagsChanged,
                    MacVirtualKey.rightCommand,
                    command: false
                )
            ),
            GlobalInputRouting(
                consume: false,
                actions: [.hotkey(.pressed)]
            )
        )
        reducer.synchronizeToggleSession(isActive: true)
        _ = reducer.route(
            key(
                .flagsChanged,
                MacVirtualKey.rightCommand,
                command: true
            )
        )
        XCTAssertEqual(
            reducer.route(
                key(
                    .flagsChanged,
                    MacVirtualKey.rightCommand,
                    command: false
                )
            ),
            GlobalInputRouting(
                consume: false,
                actions: [.hotkey(.released)]
            )
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

    func testEscapeStopsAndInsertsToggleSessionAfterCommandIsReleased() {
        var reducer = GlobalInputReducer(activationMode: .toggle)
        _ = reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true))
        _ = reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: false))

        XCTAssertEqual(
            reducer.route(key(.keyDown, MacVirtualKey.escape, command: false)),
            GlobalInputRouting(
                consume: true,
                actions: [.hotkey(.stopAndInsert)]
            )
        )
        XCTAssertEqual(
            reducer.route(key(.keyUp, MacVirtualKey.escape, command: false)),
            GlobalInputRouting(consume: true)
        )
        XCTAssertNil(reducer.reset())
    }

    func testReturnSendsActiveToggleSessionAndConsumesItsKeyPair() {
        var reducer = GlobalInputReducer(activationMode: .toggle)
        _ = reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true))
        _ = reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: false))

        XCTAssertEqual(
            reducer.route(key(.keyDown, MacVirtualKey.returnKey, command: false)),
            GlobalInputRouting(
                consume: true,
                actions: [.hotkey(.insertAndSubmit)]
            )
        )
        XCTAssertEqual(
            reducer.route(
                key(
                    .keyDown,
                    MacVirtualKey.returnKey,
                    command: false,
                    repeat: true
                )
            ),
            GlobalInputRouting(consume: true)
        )
        XCTAssertEqual(
            reducer.route(key(.keyUp, MacVirtualKey.returnKey, command: false)),
            GlobalInputRouting(consume: true)
        )
        XCTAssertNil(reducer.reset())
    }

    func testKeypadEnterSendsActiveHoldAndDisarmsRelease() {
        var reducer = GlobalInputReducer()
        _ = reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true))
        XCTAssertEqual(reducer.holdActivationFired(), .pressed)

        XCTAssertEqual(
            reducer.route(key(.keyDown, MacVirtualKey.keypadEnter, command: true)),
            GlobalInputRouting(
                consume: true,
                actions: [.disarmHold, .hotkey(.insertAndSubmit)]
            )
        )
        XCTAssertEqual(
            reducer.route(key(.keyUp, MacVirtualKey.keypadEnter, command: true)),
            GlobalInputRouting(consume: true)
        )
        XCTAssertEqual(
            reducer.route(
                key(
                    .flagsChanged,
                    MacVirtualKey.rightCommand,
                    command: false
                )
            ),
            GlobalInputRouting(consume: false, actions: [.disarmHold])
        )
    }

    func testEscapeAndReturnPassThroughWhenDictationIsInactive() {
        var reducer = GlobalInputReducer()

        for keyCode in [
            MacVirtualKey.escape,
            MacVirtualKey.returnKey,
            MacVirtualKey.keypadEnter,
        ] {
            XCTAssertEqual(
                reducer.route(key(.keyDown, keyCode, command: false)),
                GlobalInputRouting(consume: false)
            )
            XCTAssertEqual(
                reducer.route(key(.keyUp, keyCode, command: false)),
                GlobalInputRouting(consume: false)
            )
        }
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

    func testEverySelectableHotkeyHasUniqueCodeAndVisibleName() {
        XCTAssertEqual(
            Set(HotkeyKey.allCases.map(\.virtualKeyCode)).count,
            HotkeyKey.allCases.count
        )
        for hotkey in HotkeyKey.allCases {
            XCTAssertFalse(hotkey.displayName.isEmpty)
        }
    }

    func testRightShiftCanDriveAFullHoldWhileOppositeShiftRemainsDown() {
        var reducer = GlobalInputReducer(hotkey: .rightShift)

        XCTAssertEqual(
            reducer.route(key(.flagsChanged, MacVirtualKey.rightShift, command: true)),
            GlobalInputRouting(consume: false, actions: [.armHold])
        )
        XCTAssertEqual(reducer.holdActivationFired(), .pressed)
        XCTAssertEqual(
            reducer.route(key(.flagsChanged, MacVirtualKey.rightShift, command: true)),
            GlobalInputRouting(
                consume: false,
                actions: [.disarmHold, .hotkey(.released)]
            )
        )
    }

    func testSelectedModifierChordPassesThroughAndCancelsBareCandidate() {
        var reducer = GlobalInputReducer(hotkey: .leftOption)
        _ = reducer.route(key(.flagsChanged, MacVirtualKey.leftOption, command: true))

        XCTAssertEqual(
            reducer.route(key(.keyDown, MacVirtualKey.c, command: true)),
            GlobalInputRouting(consume: false, actions: [.disarmHold])
        )
        XCTAssertNil(reducer.holdActivationFired())
    }

    func testEscapeCanBeDedicatedHoldKey() {
        var reducer = GlobalInputReducer(hotkey: .escape)

        XCTAssertEqual(
            reducer.route(key(.keyDown, MacVirtualKey.escape, command: false)),
            GlobalInputRouting(consume: true, actions: [.armHold])
        )
        XCTAssertEqual(reducer.holdActivationFired(), .pressed)
        XCTAssertEqual(
            reducer.route(key(.keyUp, MacVirtualKey.escape, command: false)),
            GlobalInputRouting(
                consume: true,
                actions: [.disarmHold, .hotkey(.released)]
            )
        )
    }

    func testCapsLockAlwaysUsesSuccessiveToggleEvents() {
        var reducer = GlobalInputReducer(
            activationMode: .hold,
            hotkey: .capsLock
        )

        XCTAssertEqual(reducer.activationMode, .toggle)
        XCTAssertNil(reducer.setActivationMode(.hold))
        XCTAssertEqual(
            reducer.route(key(.flagsChanged, MacVirtualKey.capsLock, command: true)),
            GlobalInputRouting(consume: false, actions: [.hotkey(.pressed)])
        )
        XCTAssertEqual(
            reducer.route(key(.flagsChanged, MacVirtualKey.capsLock, command: false)),
            GlobalInputRouting(consume: false, actions: [.hotkey(.released)])
        )
    }

    func testFunctionKeyCanDriveToggleMode() {
        var reducer = GlobalInputReducer(
            activationMode: .toggle,
            hotkey: .function
        )

        XCTAssertEqual(
            reducer.route(key(.flagsChanged, MacVirtualKey.function, command: true)),
            GlobalInputRouting(consume: false)
        )
        XCTAssertEqual(
            reducer.route(key(.flagsChanged, MacVirtualKey.function, command: false)),
            GlobalInputRouting(consume: false, actions: [.hotkey(.pressed)])
        )
    }

    func testChangingSelectedHotkeyCancelsActiveSessionOnce() {
        var reducer = GlobalInputReducer(hotkey: .rightControl)
        _ = reducer.route(key(.flagsChanged, MacVirtualKey.rightControl, command: true))
        _ = reducer.holdActivationFired()

        XCTAssertEqual(reducer.setHotkey(.leftControl), .cancel)
        XCTAssertEqual(reducer.hotkey, .leftControl)
        XCTAssertNil(reducer.reset())
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
            selectedModifierIsDown: command,
            isAutoRepeat: isAutoRepeat
        )
    }
}

@MainActor
final class GlobalHotkeyMonitorDeliveryTests: XCTestCase {
    func testRecordingControllerClickDoesNotCancelModifierSession() async {
        var deliveries: [HotkeyAction] = []
        let started = expectation(description: "hold started")
        let released = expectation(description: "hold released")
        let monitor = GlobalHotkeyMonitor(
            captureInsertionContext: { nil },
            shouldIgnorePointerDown: { true },
            holdActivationDelay: .milliseconds(1)
        ) { action, _, _ in
            deliveries.append(action)
            if action == .pressed {
                started.fulfill()
            } else if action == .released {
                released.fulfill()
            }
        }
        let press = event(
            keyCode: MacVirtualKey.rightCommand,
            commandIsDown: true,
            timestampNanoseconds: 700
        )
        let mouseDown = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: .zero,
            mouseButton: .left
        )!
        let release = event(
            keyCode: MacVirtualKey.rightCommand,
            commandIsDown: false,
            timestampNanoseconds: 900
        )

        XCTAssertFalse(
            monitor.shouldConsumeTapEvent(type: .flagsChanged, event: press)
        )
        await fulfillment(of: [started], timeout: 1)
        XCTAssertFalse(
            monitor.shouldConsumeTapEvent(type: .leftMouseDown, event: mouseDown)
        )
        XCTAssertFalse(
            monitor.shouldConsumeTapEvent(type: .flagsChanged, event: release)
        )
        await fulfillment(of: [released], timeout: 1)
        XCTAssertEqual(deliveries, [.pressed, .released])
    }

    func testHotkeyDeliveryIsDeferredOrderedAndUsesPhysicalTimestamps() async {
        var deliveries: [(HotkeyAction, UInt64)] = []
        var didCaptureInsertionContext = false
        let started = expectation(description: "hold started after dwell")
        let released = expectation(description: "hold released")
        let monitor = GlobalHotkeyMonitor(
            captureInsertionContext: {
                didCaptureInsertionContext = true
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
        XCTAssertFalse(didCaptureInsertionContext)

        XCTAssertFalse(
            monitor.shouldConsumeTapEvent(type: .flagsChanged, event: release)
        )
        await fulfillment(of: [released], timeout: 1)
        XCTAssertEqual(deliveries.map(\.0), [.pressed, .released])
        XCTAssertEqual(deliveries.map(\.1), [1_000, 1_250])
        XCTAssertTrue(didCaptureInsertionContext)
    }

    func testToggleSecondPressCapturesInsertionTarget() async {
        var deliveries: [HotkeyAction] = []
        var contextCaptureCount = 0
        let delivered = expectation(description: "toggle start and finish")
        delivered.expectedFulfillmentCount = 2
        let monitor = GlobalHotkeyMonitor(
            captureInsertionContext: {
                contextCaptureCount += 1
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
        XCTAssertEqual(contextCaptureCount, 1)
    }

    func testReturnCompletionCapturesInsertionTargetAndConsumesKeyPair() async {
        let expectedContext = DictationInsertionContext(
            surroundingText: SurroundingText(
                beforeSelection: "before",
                afterSelection: "after"
            ),
            caretRect: CGRect(x: 10, y: 20, width: 1, height: 16)
        )
        var deliveries: [(HotkeyAction, DictationInsertionContext?)] = []
        let delivered = expectation(description: "toggle start and send")
        delivered.expectedFulfillmentCount = 2
        let monitor = GlobalHotkeyMonitor(
            captureInsertionContext: { expectedContext }
        ) { action, context, _ in
            deliveries.append((action, context))
            delivered.fulfill()
        }
        monitor.setActivationMode(.toggle)

        XCTAssertFalse(
            monitor.shouldConsumeTapEvent(
                type: .flagsChanged,
                event: event(
                    keyCode: MacVirtualKey.rightCommand,
                    commandIsDown: true,
                    timestampNanoseconds: 12_000
                )
            )
        )
        XCTAssertFalse(
            monitor.shouldConsumeTapEvent(
                type: .flagsChanged,
                event: event(
                    keyCode: MacVirtualKey.rightCommand,
                    commandIsDown: false,
                    timestampNanoseconds: 12_100
                )
            )
        )

        let returnDown = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(MacVirtualKey.returnKey),
            keyDown: true
        )!
        returnDown.timestamp = 12_200
        let returnUp = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(MacVirtualKey.returnKey),
            keyDown: false
        )!
        returnUp.timestamp = 12_300

        XCTAssertTrue(
            monitor.shouldConsumeTapEvent(type: .keyDown, event: returnDown)
        )
        XCTAssertTrue(
            monitor.shouldConsumeTapEvent(type: .keyUp, event: returnUp)
        )

        await fulfillment(of: [delivered], timeout: 1)
        XCTAssertEqual(deliveries.map(\.0), [.pressed, .insertAndSubmit])
        XCTAssertNil(deliveries[0].1)
        XCTAssertEqual(deliveries[1].1, expectedContext)
    }

    func testTapDisableCancellationUsesDisablingEventTimestamp() async {
        var deliveries: [(HotkeyAction, UInt64)] = []
        let started = expectation(description: "hold started")
        let cancelled = expectation(description: "hold cancelled")
        let monitor = GlobalHotkeyMonitor(
            captureInsertionContext: { nil },
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
            captureInsertionContext: { nil },
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

    func testMonitorUsesSelectedModifierFlag() async {
        var deliveries: [HotkeyAction] = []
        let started = expectation(description: "right shift hold starts")
        let monitor = GlobalHotkeyMonitor(
            captureInsertionContext: { nil },
            holdActivationDelay: .milliseconds(1)
        ) { action, _, _ in
            deliveries.append(action)
            started.fulfill()
        }
        monitor.setHotkey(.rightShift)
        let press = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(MacVirtualKey.rightShift),
            keyDown: true
        )!
        press.flags = .maskShift
        press.timestamp = 5_000

        XCTAssertFalse(
            monitor.shouldConsumeTapEvent(type: .flagsChanged, event: press)
        )
        await fulfillment(of: [started], timeout: 1)
        XCTAssertEqual(deliveries, [.pressed])
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
