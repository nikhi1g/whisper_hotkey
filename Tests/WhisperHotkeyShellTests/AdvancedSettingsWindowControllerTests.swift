import AppKit
import XCTest
@testable import WhisperHotkeyShell
import WhisperHotkeyCore
import WhisperHotkeySystem

final class AdvancedSettingsWindowControllerTests: XCTestCase {
    func testDictationModeTitlesAreExplicit() {
        XCTAssertEqual(
            DictationModePresentation.optionTitle(for: .hold),
            "Press and Hold"
        )
        XCTAssertEqual(
            DictationModePresentation.optionTitle(for: .toggle),
            "Toggle"
        )
        XCTAssertEqual(
            DictationModePresentation.optionTitle(for: .pause),
            "Pause Mode"
        )
    }

    func testModelChipTitlesStayCompact() {
        XCTAssertEqual(
            DictationModel.allCases.map(DictationModelPresentation.chipTitle),
            ["Base", "Small", "Medium", "Turbo"]
        )
    }

    @MainActor
    func testPopulatesSelectionsAndMarksUnavailableModels() {
        let box = AdvancedSettingsStateBox(
            makeAdvancedSettingsState(
                hotkey: .rightOption,
                mode: .toggle,
                model: .smallEnglish,
                keepModelReady: true,
                internalDictionaryEntries: ["Codex", "Claude Code"],
                limit: .minutes5,
                availableModels: [.baseEnglish, .smallEnglish]
            )
        )
        let service = AdvancedSettingsFakeLoginItemService(state: .enabled)
        let controller = makeController(box: box, service: service)

        XCTAssertEqual(controller.selectedHotkeyForTesting, .rightOption)
        XCTAssertEqual(controller.selectedModeForTesting, .toggle)
        XCTAssertEqual(controller.selectedModelForTesting, .smallEnglish)
        XCTAssertTrue(controller.keepModelReadyForTesting)
        XCTAssertEqual(
            controller.internalDictionaryEntriesForTesting,
            ["Codex", "Claude Code"]
        )
        XCTAssertEqual(controller.selectedLimitForTesting, .minutes5)
        XCTAssertEqual(controller.selectedThemeForTesting, .githubDarkDimmed)
        XCTAssertTrue(controller.configurationControlsEnabledForTesting)
        XCTAssertTrue(controller.modeControlEnabledForTesting)
        XCTAssertEqual(controller.modelIsEnabledForTesting(.smallEnglish), true)
        XCTAssertEqual(controller.modelIsEnabledForTesting(.mediumEnglish), false)
        XCTAssertEqual(
            controller.modelTitleForTesting(.mediumEnglish),
            "\(DictationModel.mediumEnglish.menuTitle): Not Installed"
        )
        XCTAssertTrue(controller.usesChipSelectionForTesting)
        XCTAssertTrue(
            controller.controlsFitWindowForTesting,
            controller.controlsOutsideWindowForTesting.joined(separator: ", ")
        )
        XCTAssertEqual(
            controller.summaryValuesForTesting,
            [
                "Right Option", "Toggle", "Small Metal Ready", "5 Minutes",
                "Dimmed", "Login On",
            ]
        )
        XCTAssertEqual(
            controller.helpAccessibilityLabelForTesting,
            "Open User Guide"
        )
        XCTAssertGreaterThan(
            controller.helpButtonFrameForTesting.midX,
            540
        )
        XCTAssertTrue(controller.loginItemIsOnForTesting)
        XCTAssertEqual(controller.loginStatusTextForTesting, "Enabled")
        XCTAssertEqual(
            controller.window?.contentView?.frame.size,
            CGSize(width: 620, height: 630)
        )
        XCTAssertEqual(
            controller.window?.title,
            "Settings for whisper_hotkey"
        )
    }

    @MainActor
    func testUserGuideExplainsEveryModeModelAndActiveShortcut() {
        let state = makeAdvancedSettingsState(
            hotkey: .rightOption,
            mode: .toggle,
            model: .largeV3TurboQ5,
            keepModelReady: true,
            limit: .minutes5,
            availableModels: Set(DictationModel.allCases)
        )
        let sections = UserGuideContent.sections(for: state)
        let rows = sections.flatMap(\.rows)

        XCTAssertEqual(sections.first?.title, "DICTATION")
        XCTAssertTrue(
            rows.contains(
                UserGuideRow(
                    key: "Right Option",
                    title: "Tap to start or stop",
                    detail: "Tap once to listen and again to transcribe and insert."
                )
            )
        )
        XCTAssertTrue(
            ["Press and Hold", "Toggle", "Pause Mode"].allSatisfy { title in
                rows.contains(where: { $0.title == title })
            }
        )
        XCTAssertTrue(
            ["Base", "Small", "Medium", "Turbo"].allSatisfy { title in
                rows.contains(where: { $0.title == title })
            }
        )
        XCTAssertTrue(
            rows.contains(
                UserGuideRow(
                    key: "on",
                    title: "Keep Model Ready",
                    detail: "On: the selected model stays loaded for the fastest response and higher idle memory use."
                )
            )
        )
        XCTAssertTrue(
            ["Discard", "Insert and send", "Stop and insert"].allSatisfy {
                title in rows.contains(where: { $0.title == title })
            }
        )
        XCTAssertTrue(
            [
                "Dictation key", "Internal dictionary", "Recording limit",
                "Theme", "Open at Login",
            ].allSatisfy {
                title in rows.contains(where: { $0.title == title })
            }
        )

        let viewController = UserGuideViewController(
            sections: sections,
            theme: .nord
        )
        viewController.preferredContentSize = NSSize(width: 440, height: 540)
        let renderedText = viewController.renderedTextForTesting
        XCTAssertFalse(renderedText.isEmpty)
        XCTAssertTrue(viewController.renderedTextHasVisibleFrameForTesting)
        XCTAssertTrue(renderedText.contains("RIGHT OPTION"))
        XCTAssertTrue(renderedText.contains("Press and Hold"))
        XCTAssertTrue(renderedText.contains("Turbo"))
        XCTAssertTrue(renderedText.contains("Return or keypad Enter"))
        XCTAssertEqual(viewController.appliedThemeForTesting, .nord)
        XCTAssertTrue(viewController.backgroundIsOpaqueForTesting)
    }

    @MainActor
    func testEachPreferenceControlRoutesExactlyOnceAndRefreshDoesNotDuplicateOptions() {
        let box = AdvancedSettingsStateBox(
            makeAdvancedSettingsState(
                availableModels: Set(DictationModel.allCases),
                availableEngines: Set(RecognitionEngine.allCases)
            )
        )
        var selectedHotkeys: [HotkeyKey] = []
        var selectedModes: [HotkeyActivationMode] = []
        var selectedModels: [DictationModel] = []
        var selectedEngines: [RecognitionEngine] = []
        var readinessSelections: [Bool] = []
        var dictionarySelections: [[String]] = []
        var selectedLimits: [RecordingLimit] = []
        var selectedThemes: [BadgeTheme] = []
        let controller = AdvancedSettingsWindowController(
            stateProvider: { box.value },
            actions: AdvancedSettingsActions(
                selectDictationMode: { selectedModes.append($0) },
                selectHotkey: { selectedHotkeys.append($0) },
                selectModel: { selectedModels.append($0) },
                selectEngine: { selectedEngines.append($0) },
                setKeepModelReady: { readinessSelections.append($0) },
                setInternalDictionary: { dictionarySelections.append($0) },
                selectRecordingLimit: { selectedLimits.append($0) },
                selectTheme: { selectedThemes.append($0) }
            ),
            loginItemManager: makeLoginItemManager()
        )
        let initialCounts = controller.optionCountsForTesting

        controller.selectHotkeyForTesting(.leftShift)
        controller.selectModeForTesting(.toggle)
        controller.selectModelForTesting(.largeV3TurboQ5)
        controller.selectEngineForTesting(.whisperKitCoreML)
        controller.setKeepModelReadyForTesting(true)
        controller.setInternalDictionaryForTesting(
            [" Codex ", "Claude Code", "codex"]
        )
        controller.selectLimitForTesting(.minutes30)
        controller.selectThemeForTesting(.nord)

        XCTAssertEqual(selectedHotkeys, [.leftShift])
        XCTAssertEqual(selectedModes, [.toggle])
        XCTAssertEqual(selectedModels, [.largeV3TurboQ5])
        XCTAssertEqual(selectedEngines, [.whisperKitCoreML])
        XCTAssertEqual(readinessSelections, [true])
        XCTAssertEqual(dictionarySelections, [["Codex", "Claude Code"]])
        XCTAssertEqual(selectedLimits, [.minutes30])
        XCTAssertEqual(selectedThemes, [.nord])

        box.value = makeAdvancedSettingsState(
            hotkey: .leftShift,
            mode: .toggle,
            model: .largeV3TurboQ5,
            keepModelReady: true,
            internalDictionaryEntries: ["Codex", "Claude Code"],
            limit: .minutes30,
            theme: .nord,
            availableModels: Set(DictationModel.allCases),
            availableEngines: Set(RecognitionEngine.allCases)
        )
        controller.refresh()
        controller.refresh()

        XCTAssertEqual(controller.selectedHotkeyForTesting, .leftShift)
        XCTAssertEqual(controller.selectedModeForTesting, .toggle)
        XCTAssertEqual(controller.selectedModelForTesting, .largeV3TurboQ5)
        XCTAssertEqual(controller.selectedEngineForTesting, .whisperCppMetal)
        XCTAssertTrue(controller.keepModelReadyForTesting)
        XCTAssertEqual(
            controller.internalDictionaryEntriesForTesting,
            ["Codex", "Claude Code"]
        )
        XCTAssertEqual(controller.selectedLimitForTesting, .minutes30)
        XCTAssertEqual(controller.selectedThemeForTesting, .nord)
        XCTAssertEqual(controller.optionCountsForTesting, initialCounts)
        XCTAssertEqual(
            controller.windowBackgroundForTesting,
            BadgeThemePalette.palette(for: .nord).background.withAlphaComponent(1)
        )
    }

    @MainActor
    func testCapsLockForcesToggle() {
        let box = AdvancedSettingsStateBox(
            makeAdvancedSettingsState(
                hotkey: .capsLock,
                mode: .toggle
            )
        )
        var selectedModes: [HotkeyActivationMode] = []
        let controller = AdvancedSettingsWindowController(
            stateProvider: { box.value },
            actions: AdvancedSettingsActions(
                selectDictationMode: { selectedModes.append($0) },
                selectHotkey: { _ in },
                selectModel: { _ in },
                selectRecordingLimit: { _ in }
            ),
            loginItemManager: makeLoginItemManager()
        )

        XCTAssertEqual(controller.selectedModeForTesting, .toggle)
        XCTAssertTrue(controller.modeControlEnabledForTesting)
        controller.selectModeForTesting(.hold)
        XCTAssertTrue(selectedModes.isEmpty)
        XCTAssertEqual(controller.selectedModeForTesting, .toggle)
        controller.selectModeForTesting(.pause)
        XCTAssertEqual(selectedModes, [.pause])
    }

    @MainActor
    func testBusyStateDisablesAndRejectsEveryMutation() {
        let box = AdvancedSettingsStateBox(
            makeAdvancedSettingsState(
                availableModels: Set(DictationModel.allCases),
                configurationEnabled: false
            )
        )
        let service = AdvancedSettingsFakeLoginItemService()
        var mutationCount = 0
        let controller = AdvancedSettingsWindowController(
            stateProvider: { box.value },
            actions: AdvancedSettingsActions(
                selectDictationMode: { _ in mutationCount += 1 },
                selectHotkey: { _ in mutationCount += 1 },
                selectModel: { _ in mutationCount += 1 },
                setKeepModelReady: { _ in mutationCount += 1 },
                setInternalDictionary: { _ in mutationCount += 1 },
                selectRecordingLimit: { _ in mutationCount += 1 },
                selectTheme: { _ in mutationCount += 1 },
                loginItemChanged: { mutationCount += 1 }
            ),
            loginItemManager: makeLoginItemManager(service: service)
        )

        XCTAssertFalse(controller.configurationControlsEnabledForTesting)
        XCTAssertFalse(controller.modeControlEnabledForTesting)
        controller.selectHotkeyForTesting(.leftControl)
        controller.selectModeForTesting(.toggle)
        controller.selectModelForTesting(.smallEnglish)
        controller.setKeepModelReadyForTesting(true)
        controller.setInternalDictionaryForTesting(["Codex"])
        controller.selectLimitForTesting(.seconds30)
        controller.selectThemeForTesting(.dracula)
        controller.setLoginItemForTesting(enabled: true)

        XCTAssertEqual(mutationCount, 0)
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(service.unregisterCallCount, 0)
    }

    @MainActor
    func testSelectedMissingModelCanRecoverToAnInstalledModel() {
        let box = AdvancedSettingsStateBox(
            makeAdvancedSettingsState(
                model: .mediumEnglish,
                availableModels: [.baseEnglish]
            )
        )
        var selectedModels: [DictationModel] = []
        let controller = AdvancedSettingsWindowController(
            stateProvider: { box.value },
            actions: AdvancedSettingsActions(
                selectDictationMode: { _ in },
                selectHotkey: { _ in },
                selectModel: { selectedModels.append($0) },
                selectRecordingLimit: { _ in }
            ),
            loginItemManager: makeLoginItemManager()
        )

        XCTAssertEqual(controller.selectedModelForTesting, .mediumEnglish)
        XCTAssertEqual(controller.modelIsEnabledForTesting(.mediumEnglish), false)
        XCTAssertTrue(controller.configurationControlsEnabledForTesting)

        controller.selectModelForTesting(.baseEnglish)
        XCTAssertEqual(selectedModels, [.baseEnglish])
    }

    @MainActor
    func testOpenAtLoginUsesSharedManagerForExplicitEnableAndDisable() {
        let box = AdvancedSettingsStateBox(makeAdvancedSettingsState())
        let service = AdvancedSettingsFakeLoginItemService()
        let preferences = AdvancedSettingsFakeLoginPreferenceStore()
        let manager = LoginItemManager(
            service: service,
            preferenceStore: preferences
        )
        var changeCount = 0
        let controller = AdvancedSettingsWindowController(
            stateProvider: { box.value },
            actions: AdvancedSettingsActions(
                selectDictationMode: { _ in },
                selectHotkey: { _ in },
                selectModel: { _ in },
                selectRecordingLimit: { _ in },
                loginItemChanged: { changeCount += 1 }
            ),
            loginItemManager: manager
        )

        XCTAssertFalse(controller.loginItemIsOnForTesting)
        controller.setLoginItemForTesting(enabled: true)
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertTrue(controller.loginItemIsOnForTesting)
        XCTAssertFalse(preferences.explicitlyDisabled)

        controller.setLoginItemForTesting(enabled: false)
        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertFalse(controller.loginItemIsOnForTesting)
        XCTAssertTrue(preferences.explicitlyDisabled)
        XCTAssertEqual(changeCount, 2)
    }

    @MainActor
    func testLoginApprovalStateOffersSystemSettings() {
        let box = AdvancedSettingsStateBox(makeAdvancedSettingsState())
        let service = AdvancedSettingsFakeLoginItemService(
            state: .requiresApproval
        )
        let controller = makeController(box: box, service: service)

        XCTAssertTrue(controller.loginItemIsOnForTesting)
        XCTAssertEqual(
            controller.loginStatusTextForTesting,
            "Approval needed"
        )
        XCTAssertTrue(controller.loginSettingsIsVisibleForTesting)
        XCTAssertTrue(
            controller.controlsFitWindowForTesting,
            controller.controlsOutsideWindowForTesting.joined(separator: ", ")
        )

        controller.openLoginSettingsForTesting()
        XCTAssertEqual(service.openSettingsCallCount, 1)
    }

    @MainActor
    func testNativeAppKitHitTestingClicksLoginToggleCenterAndVisibleEdge() {
        let box = AdvancedSettingsStateBox(makeAdvancedSettingsState())
        let service = AdvancedSettingsFakeLoginItemService()
        let controller = makeController(box: box, service: service)

        XCTAssertTrue(
            controller.clickLoginToggleForTesting(atVisibleEdge: false)
        )
        XCTAssertEqual(service.registerCallCount, 1)

        XCTAssertTrue(
            controller.clickLoginToggleForTesting(atVisibleEdge: true)
        )
        XCTAssertEqual(service.unregisterCallCount, 1)
    }
}

@MainActor
private final class AdvancedSettingsStateBox {
    var value: AdvancedSettingsState

    init(_ value: AdvancedSettingsState) {
        self.value = value
    }
}

private func makeAdvancedSettingsState(
    hotkey: HotkeyKey = .rightCommand,
    mode: HotkeyActivationMode = .hold,
    model: DictationModel = .baseEnglish,
    keepModelReady: Bool = false,
    internalDictionaryEntries: [String] = [],
    limit: RecordingLimit = .minutes10,
    theme: BadgeTheme = .defaultTheme,
    availableModels: Set<DictationModel> = [.baseEnglish],
    availableEngines: Set<RecognitionEngine> = [.whisperCppMetal],
    configurationEnabled: Bool = true
) -> AdvancedSettingsState {
    AdvancedSettingsState(
        selectedHotkey: hotkey,
        activationMode: mode,
        selectedModel: model,
        keepModelReady: keepModelReady,
        internalDictionaryEntries: internalDictionaryEntries,
        recordingLimit: limit,
        selectedTheme: theme,
        availableModels: availableModels,
        availableEngines: availableEngines,
        configurationEnabled: configurationEnabled
    )
}

@MainActor
private func makeController(
    box: AdvancedSettingsStateBox,
    service: AdvancedSettingsFakeLoginItemService
) -> AdvancedSettingsWindowController {
    AdvancedSettingsWindowController(
        stateProvider: { box.value },
        actions: AdvancedSettingsActions(
            selectDictationMode: { _ in },
            selectHotkey: { _ in },
            selectModel: { _ in },
            selectRecordingLimit: { _ in }
        ),
        loginItemManager: makeLoginItemManager(service: service)
    )
}

@MainActor
private func makeLoginItemManager(
    service: AdvancedSettingsFakeLoginItemService =
        AdvancedSettingsFakeLoginItemService()
) -> LoginItemManager {
    LoginItemManager(
        service: service,
        preferenceStore: AdvancedSettingsFakeLoginPreferenceStore()
    )
}

@MainActor
private final class AdvancedSettingsFakeLoginItemService: LoginItemService {
    var state: LoginItemServiceState
    var registerCallCount = 0
    var unregisterCallCount = 0
    var openSettingsCallCount = 0

    init(state: LoginItemServiceState = .notRegistered) {
        self.state = state
    }

    func register() throws {
        registerCallCount += 1
        state = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        state = .notRegistered
    }

    func openLoginItemsSettings() {
        openSettingsCallCount += 1
    }
}

@MainActor
private final class AdvancedSettingsFakeLoginPreferenceStore:
    LoginItemPreferenceStoring
{
    var explicitlyDisabled = false
}
