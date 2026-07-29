import AppKit
import XCTest
@testable import WhisperHotkeyShell
import WhisperHotkeySystem

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
            hasLastDictation: false,
            actions: MenuBarActions(
                showSetup: {},
                showAdvancedSettings: {},
                cancelDictation: {},
                copyLastDictation: {},
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

    @MainActor
    func testIdleMenuKeepsOnlyImmediateActionsAndRoutesAdvancedSettings() {
        var advancedSettingsCount = 0
        let controller = MenuBarController(
            toggleDictationEnabled: true,
            selectedHotkey: .rightOption,
            hasLastDictation: false,
            actions: MenuBarActions(
                showSetup: {},
                showAdvancedSettings: { advancedSettingsCount += 1 },
                cancelDictation: {},
                copyLastDictation: {},
                restart: {},
                quit: {}
            )
        )

        XCTAssertEqual(
            controller.visibleMenuItemTitlesForTesting,
            [
                "Starting…",
                "",
                "Open Setup…",
                "Settings…",
                "",
                "Restart whisper_hotkey",
                "Quit whisper_hotkey",
            ]
        )
        XCTAssertFalse(
            controller.menuItemTitlesForTesting.contains("Dictation Mode")
        )
        XCTAssertFalse(
            controller.menuItemTitlesForTesting.contains("Dictation Key")
        )
        XCTAssertFalse(
            controller.menuItemTitlesForTesting.contains("Whisper Model")
        )
        XCTAssertFalse(
            controller.menuItemTitlesForTesting.contains("Recording Limit")
        )

        controller.activateMenuItemForTesting(titled: "Settings…")
        XCTAssertEqual(advancedSettingsCount, 1)
    }

    @MainActor
    func testBusyMenuShowsCancelAndDisablesConfigurationWindows() {
        var cancellationCount = 0
        let controller = MenuBarController(
            toggleDictationEnabled: false,
            selectedHotkey: .rightCommand,
            hasLastDictation: false,
            actions: MenuBarActions(
                showSetup: {},
                showAdvancedSettings: {},
                cancelDictation: { cancellationCount += 1 },
                copyLastDictation: {},
                restart: {},
                quit: {}
            )
        )

        controller.update(
            .listening,
            toggleDictationEnabled: false,
            selectedHotkey: .rightCommand,
            hasLastDictation: false
        )

        XCTAssertTrue(
            controller.visibleMenuItemTitlesForTesting.contains(
                "Cancel Dictation"
            )
        )
        XCTAssertEqual(
            controller.menuItemIsEnabledForTesting(titled: "Open Setup…"),
            false
        )
        XCTAssertEqual(
            controller.menuItemIsEnabledForTesting(
                titled: "Settings…"
            ),
            false
        )
        controller.activateMenuItemForTesting(titled: "Cancel Dictation")
        XCTAssertEqual(cancellationCount, 1)
    }

    @MainActor
    func testCopyLastDictationAppearsOnlyAfterAResultExists() {
        let controller = MenuBarController(
            toggleDictationEnabled: false,
            selectedHotkey: .rightCommand,
            hasLastDictation: false,
            actions: MenuBarActions(
                showSetup: {},
                showAdvancedSettings: {},
                cancelDictation: {},
                copyLastDictation: {},
                restart: {},
                quit: {}
            )
        )

        XCTAssertFalse(
            controller.visibleMenuItemTitlesForTesting.contains(
                "Copy Last Dictation"
            )
        )
        controller.update(
            .idle,
            toggleDictationEnabled: false,
            selectedHotkey: .rightCommand,
            hasLastDictation: true
        )
        XCTAssertTrue(
            controller.visibleMenuItemTitlesForTesting.contains(
                "Copy Last Dictation"
            )
        )
    }
}
