import AppKit
import XCTest
@testable import WhisperHotkeyShell

final class MenuBarControllerTests: XCTestCase {
    func testEveryStateHasVisibleSymbolAndTitle() {
        let states: [MenuBarState] = [
            .starting,
            .idle,
            .preparing,
            .listening,
            .transcribing,
            .inserting,
            .cancelled,
            .unavailable,
            .failed,
        ]

        for state in states {
            XCTAssertFalse(state.symbolName.isEmpty)
            XCTAssertFalse(state.title.isEmpty)
        }
    }

    func testOnlyActiveDictationStatesCanCancel() {
        XCTAssertTrue(MenuBarState.preparing.canCancel)
        XCTAssertTrue(MenuBarState.listening.canCancel)
        XCTAssertTrue(MenuBarState.transcribing.canCancel)
        XCTAssertTrue(MenuBarState.inserting.canCancel)

        XCTAssertFalse(MenuBarState.starting.canCancel)
        XCTAssertFalse(MenuBarState.idle.canCancel)
        XCTAssertFalse(MenuBarState.cancelled.canCancel)
        XCTAssertFalse(MenuBarState.unavailable.canCancel)
        XCTAssertFalse(MenuBarState.failed.canCancel)
    }

    @MainActor
    func testSystemSymbolsExistOnSupportedMacOS() {
        let states: [MenuBarState] = [
            .starting,
            .idle,
            .preparing,
            .listening,
            .transcribing,
            .inserting,
            .cancelled,
            .unavailable,
            .failed,
        ]

        for state in states {
            XCTAssertNotNil(
                NSImage(
                    systemSymbolName: state.symbolName,
                    accessibilityDescription: nil
                ),
                "Missing SF Symbol \(state.symbolName)"
            )
        }
    }
}
