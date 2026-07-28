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

    func testIdleTitleDescribesSelectedGesture() {
        XCTAssertEqual(
            MenuBarState.idle.title(
                toggleDictationEnabled: false,
                hotkey: .rightCommand
            ),
            "Ready: hold Right Command"
        )
        XCTAssertEqual(
            MenuBarState.idle.title(
                toggleDictationEnabled: true,
                hotkey: .leftShift
            ),
            "Ready: press Left Shift"
        )
    }

    func testRecordingLimitParentTitleExposesSelection() {
        XCTAssertEqual(
            RecordingLimitMenuPresentation.title(for: .seconds30),
            "Recording Limit: 30 Seconds"
        )
        XCTAssertEqual(
            RecordingLimitMenuPresentation.title(for: .hour1),
            "Recording Limit: 1 Hour"
        )
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

    @MainActor
    func testRestartIsImmediatelyBeforeQuitAndRoutesItsAction() {
        var restartCount = 0
        let controller = MenuBarController(
            toggleDictationEnabled: true,
            selectedHotkey: .rightOption,
            selectedModel: .baseEnglish,
            recordingLimit: .minutes5,
            availableModels: [.baseEnglish],
            hasLastDictation: false,
            actions: MenuBarActions(
                showSetup: {},
                cancelDictation: {},
                copyLastDictation: {},
                toggleDictationMode: {},
                selectHotkey: { _ in },
                selectModel: { _ in },
                selectRecordingLimit: { _ in },
                restart: { restartCount += 1 },
                quit: {}
            )
        )
        let titles = controller.menuItemTitlesForTesting
        let restartIndex = try! XCTUnwrap(
            titles.firstIndex(of: "Restart whisper_hotkey")
        )

        XCTAssertEqual(titles[restartIndex + 1], "Quit whisper_hotkey")
        controller.activateMenuItemForTesting(
            titled: "Restart whisper_hotkey"
        )
        XCTAssertEqual(restartCount, 1)
    }
}
