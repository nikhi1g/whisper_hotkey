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

    func testResetCancelsOneActiveHold() {
        var reducer = GlobalInputReducer()
        _ = reducer.route(key(.flagsChanged, MacVirtualKey.rightCommand, command: true))

        XCTAssertEqual(reducer.reset(), .cancel)
        XCTAssertNil(reducer.reset())
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
