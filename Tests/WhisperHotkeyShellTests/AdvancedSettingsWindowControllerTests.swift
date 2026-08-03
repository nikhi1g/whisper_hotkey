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
                decodingProfile: .adaptive,
                processingMode: .decodeWhileSpeaking,
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
        XCTAssertEqual(
            controller.selectedDecodingProfileForTesting,
            .adaptive
        )
        XCTAssertEqual(
            controller.selectedProcessingModeForTesting,
            .decodeWhileSpeaking
        )
        XCTAssertEqual(
            controller.internalDictionaryEntriesForTesting,
            ["Codex", "Claude Code"]
        )
        XCTAssertEqual(controller.selectedLimitForTesting, .minutes5)
        XCTAssertEqual(
            controller.selectedThemeForTesting,
            .builtIn(.githubDarkDimmed)
        )
        XCTAssertEqual(
            controller.selectableThemeCountForTesting,
            BadgeTheme.allCases.count
        )
        XCTAssertEqual(
            controller.themeSectionTitlesForTesting,
            ["Dark", "Light"]
        )
        XCTAssertTrue(controller.configurationControlsEnabledForTesting)
        XCTAssertTrue(controller.keepsLatestDictationForTesting)
        XCTAssertTrue(controller.modeControlEnabledForTesting)
        XCTAssertEqual(controller.modelIsEnabledForTesting(.smallEnglish), true)
        XCTAssertEqual(controller.modelIsEnabledForTesting(.mediumEnglish), false)
        XCTAssertEqual(
            controller.modelTitleForTesting(.mediumEnglish),
            "\(DictationModel.mediumEnglish.menuTitle): Not Installed"
        )
        XCTAssertTrue(controller.usesChipSelectionForTesting)
        XCTAssertEqual(
            controller.optionCountsForTesting[5],
            ModelProcessingMode.allCases.count
        )
        XCTAssertTrue(
            controller.controlsFitWindowForTesting,
            controller.controlsOutsideWindowForTesting.joined(separator: ", ")
        )
        XCTAssertEqual(
            controller.summaryValuesForTesting,
            [
                "Right Option", "Toggle",
                "Small Metal Smart Decode Decode While Speaking", "5 Minutes",
                "Dimmed", "Login On",
            ]
        )
        let summaryFrames = controller.summaryFramesForTesting
        XCTAssertEqual(summaryFrames.count, 6)
        XCTAssertEqual(
            Set(summaryFrames.prefix(3).map(\.midY)).count,
            1
        )
        XCTAssertEqual(
            Set(summaryFrames.suffix(3).map(\.midY)).count,
            1
        )
        XCTAssertNotEqual(summaryFrames[0].midY, summaryFrames[3].midY)
        XCTAssertLessThan(summaryFrames[3].midY, summaryFrames[0].midY)
        XCTAssertEqual(
            controller.helpAccessibilityLabelForTesting,
            "Open User Guide"
        )
        XCTAssertTrue(controller.versionTextForTesting.hasPrefix("Version "))
        XCTAssertEqual(
            controller.githubAccessibilityLabelForTesting,
            "Open whisper_hotkey on GitHub"
        )
        XCTAssertFalse(controller.automaticallyChecksForUpdatesForTesting)
        XCTAssertEqual(controller.softwareUpdateStatusForTesting, "")
        XCTAssertTrue(controller.checkForUpdatesIsEnabledForTesting)
        XCTAssertGreaterThan(
            controller.helpButtonFrameForTesting.midX,
            540
        )
        XCTAssertTrue(controller.loginItemIsOnForTesting)
        XCTAssertEqual(controller.loginStatusTextForTesting, "Enabled")
        XCTAssertEqual(
            controller.window?.contentView?.frame.size,
            CGSize(width: 620, height: 700)
        )
        XCTAssertEqual(
            controller.window?.title,
            "Settings for whisper_hotkey"
        )
        XCTAssertTrue(controller.supportsStandardWindowCommandsForTesting)
        XCTAssertTrue(controller.usesScrollableSettingsContentForTesting)
    }

    @MainActor
    func testCustomThemeEditorExpandsInlineWithoutOpeningASheet() {
        let box = AdvancedSettingsStateBox(makeAdvancedSettingsState())
        let controller = makeController(
            box: box,
            service: AdvancedSettingsFakeLoginItemService()
        )

        controller.openNewThemeEditorForTesting()

        XCTAssertTrue(controller.customThemeEditorIsInlineForTesting)
        XCTAssertTrue(controller.customThemeEditorExpandedWindowForTesting)
        XCTAssertNil(controller.window?.attachedSheet)

        controller.closeCustomThemeEditorForTesting()
        XCTAssertFalse(controller.customThemeEditorIsInlineForTesting)
    }

    @MainActor
    func testUserGuideShowsCurrentPathBeforeUnselectedAlternatives() {
        let state = makeAdvancedSettingsState(
            hotkey: .rightOption,
            mode: .toggle,
            model: .largeV3TurboQ5,
            processingMode: .modelReady,
            limit: .minutes5,
            availableModels: Set(DictationModel.allCases)
        )
        let sections = UserGuideContent.sections(
            for: state,
            loginItemEnabled: true
        )
        let currentRows = sections[0].rows
        let alternativeRows = sections[1].rows

        XCTAssertEqual(sections.map(\.title), [
            "YOUR CURRENT PATH",
            "OTHER OPTIONS",
        ])
        XCTAssertEqual(currentRows.first?.key, "active")
        XCTAssertEqual(
            currentRows.first?.title,
            "Right Option: Toggle: Turbo"
        )
        XCTAssertTrue(
            currentRows.first?.detail.contains("Tap Right Option") == true
        )
        XCTAssertTrue(
            [
                "Right Option", "Toggle", "Turbo", "Metal",
                "Precision", "Model Ready", "5 Minutes",
                "GitHub Dark Dimmed", "Open at Login",
            ].allSatisfy { title in
                currentRows.contains(where: { $0.title == title })
            }
        )
        XCTAssertTrue(
            ["Discard", "Insert and send", "Stop and insert"].allSatisfy {
                title in currentRows.contains(where: { $0.title == title })
            }
        )
        XCTAssertTrue(
            [
                "Press and Hold", "Pause Mode", "Base", "Small", "Medium",
                "After Recording", "Decode While Speaking",
            ].allSatisfy { title in
                alternativeRows.contains(where: { $0.title == title })
            }
        )
        XCTAssertFalse(
            ["Toggle", "Turbo", "Model Ready"].contains { selected in
                alternativeRows.contains(where: { $0.title == selected })
            }
        )
        XCTAssertTrue(
            alternativeRows.first(where: {
                $0.title == "Other dictation keys"
            })?.detail.contains("Right Command") == true
        )
        XCTAssertFalse(
            alternativeRows.first(where: {
                $0.title == "Other dictation keys"
            })?.detail.contains("Right Option,") == true
        )

        let viewController = UserGuideViewController(
            sections: sections,
            theme: .builtIn(.nord)
        )
        viewController.preferredContentSize = NSSize(width: 440, height: 540)
        let renderedText = viewController.renderedTextForTesting
        XCTAssertFalse(renderedText.isEmpty)
        XCTAssertTrue(viewController.renderedTextHasVisibleFrameForTesting)
        XCTAssertTrue(renderedText.contains("Right Option"))
        XCTAssertTrue(renderedText.contains("Press and Hold"))
        XCTAssertTrue(renderedText.contains("Turbo"))
        XCTAssertTrue(renderedText.contains("YOUR CURRENT PATH"))
        XCTAssertTrue(renderedText.contains("OTHER OPTIONS"))
        XCTAssertTrue(renderedText.contains("Return or keypad Enter"))
        XCTAssertEqual(
            viewController.appliedThemeForTesting,
            .builtIn(.nord)
        )
        XCTAssertTrue(viewController.backgroundIsOpaqueForTesting)
    }

    @MainActor
    func testWhisperKitUsesNativeDecodingAndDisablesProfileChoice() {
        let box = AdvancedSettingsStateBox(
            makeAdvancedSettingsState(
                engine: .whisperKitCoreML,
                decodingProfile: .adaptive,
                availableEngines: Set(RecognitionEngine.allCases)
            )
        )
        let controller = makeController(
            box: box,
            service: AdvancedSettingsFakeLoginItemService()
        )

        XCTAssertFalse(controller.decodingControlEnabledForTesting)
        XCTAssertEqual(
            controller.selectedDecodingProfileForTesting,
            .adaptive
        )
        XCTAssertTrue(
            controller.summaryValuesForTesting[2].contains("Native")
        )
    }

    @MainActor
    func testCustomThemeAppearsInCustomSectionAndCanBeSelected() {
        let custom = CustomBadgeTheme(
            name: "Terminal Lime",
            mode: .dark,
            backgroundHex: "#101216",
            textHex: "#F7F7F7",
            accentHex: "#AAFF00"
        )!
        let selection = BadgeThemeSelection.custom(custom)
        let box = AdvancedSettingsStateBox(
            makeAdvancedSettingsState(
                themeSelection: selection,
                customThemes: [custom]
            )
        )
        var selected: [BadgeThemeSelection] = []
        let controller = AdvancedSettingsWindowController(
            stateProvider: { box.value },
            actions: AdvancedSettingsActions(
                selectDictationMode: { _ in },
                selectHotkey: { _ in },
                selectModel: { _ in },
                selectRecordingLimit: { _ in },
                selectTheme: { selected.append($0) }
            ),
            loginItemManager: makeLoginItemManager()
        )

        XCTAssertEqual(controller.selectedThemeForTesting, selection)
        XCTAssertEqual(
            controller.selectableThemeCountForTesting,
            BadgeTheme.allCases.count + 1
        )
        XCTAssertEqual(
            controller.themeSectionTitlesForTesting,
            ["Dark", "Light", "Custom"]
        )
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
        var selectedDecodingProfiles: [DecodingProfile] = []
        var processingSelections: [ModelProcessingMode] = []
        var dictionarySelections: [[String]] = []
        var retentionSelections: [Bool] = []
        var selectedLimits: [RecordingLimit] = []
        var selectedThemes: [BadgeThemeSelection] = []
        var automaticUpdateSelections: [Bool] = []
        var updateCheckCount = 0
        let controller = AdvancedSettingsWindowController(
            stateProvider: { box.value },
            actions: AdvancedSettingsActions(
                selectDictationMode: { selectedModes.append($0) },
                selectHotkey: { selectedHotkeys.append($0) },
                selectModel: { selectedModels.append($0) },
                selectEngine: { selectedEngines.append($0) },
                selectDecodingProfile: {
                    selectedDecodingProfiles.append($0)
                },
                selectProcessingMode: { processingSelections.append($0) },
                setInternalDictionary: { dictionarySelections.append($0) },
                setKeepsLatestDictation: { retentionSelections.append($0) },
                selectRecordingLimit: { selectedLimits.append($0) },
                selectTheme: { selectedThemes.append($0) },
                setAutomaticallyChecksForUpdates: {
                    automaticUpdateSelections.append($0)
                },
                checkForUpdates: { updateCheckCount += 1 }
            ),
            loginItemManager: makeLoginItemManager()
        )
        let initialCounts = controller.optionCountsForTesting

        controller.selectHotkeyForTesting(.leftShift)
        controller.selectModeForTesting(.toggle)
        controller.selectModelForTesting(.largeV3TurboQ5)
        controller.selectDecodingProfileForTesting(.adaptive)
        controller.selectEngineForTesting(.whisperKitCoreML)
        controller.selectProcessingModeForTesting(.decodeWhileSpeaking)
        controller.setInternalDictionaryForTesting(
            [" Codex ", "Claude Code", "codex"]
        )
        controller.setKeepsLatestDictationForTesting(false)
        controller.selectLimitForTesting(.minutes30)
        controller.selectThemeForTesting(.nord)
        controller.setAutomaticUpdateChecksForTesting(true)
        controller.checkForUpdatesForTesting()

        XCTAssertEqual(selectedHotkeys, [.leftShift])
        XCTAssertEqual(selectedModes, [.toggle])
        XCTAssertEqual(selectedModels, [.largeV3TurboQ5])
        XCTAssertEqual(selectedEngines, [.whisperKitCoreML])
        XCTAssertEqual(selectedDecodingProfiles, [.adaptive])
        XCTAssertEqual(processingSelections, [.decodeWhileSpeaking])
        XCTAssertEqual(dictionarySelections, [["Codex", "Claude Code"]])
        XCTAssertEqual(retentionSelections, [false])
        XCTAssertEqual(selectedLimits, [.minutes30])
        XCTAssertEqual(selectedThemes, [.builtIn(.nord)])
        XCTAssertEqual(automaticUpdateSelections, [true])
        XCTAssertEqual(updateCheckCount, 1)

        box.value = makeAdvancedSettingsState(
            hotkey: .leftShift,
            mode: .toggle,
            model: .largeV3TurboQ5,
            decodingProfile: .adaptive,
            processingMode: .decodeWhileSpeaking,
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
        XCTAssertEqual(
            controller.selectedDecodingProfileForTesting,
            .adaptive
        )
        XCTAssertEqual(
            controller.selectedProcessingModeForTesting,
            .decodeWhileSpeaking
        )
        XCTAssertEqual(
            controller.internalDictionaryEntriesForTesting,
            ["Codex", "Claude Code"]
        )
        XCTAssertEqual(controller.selectedLimitForTesting, .minutes30)
        XCTAssertEqual(
            controller.selectedThemeForTesting,
            .builtIn(.nord)
        )
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
                selectProcessingMode: { _ in mutationCount += 1 },
                setInternalDictionary: { _ in mutationCount += 1 },
                setKeepsLatestDictation: { _ in mutationCount += 1 },
                selectRecordingLimit: { _ in mutationCount += 1 },
                selectTheme: { _ in mutationCount += 1 },
                loginItemChanged: { mutationCount += 1 },
                setAutomaticallyChecksForUpdates: { _ in
                    mutationCount += 1
                },
                checkForUpdates: { mutationCount += 1 }
            ),
            loginItemManager: makeLoginItemManager(service: service)
        )

        XCTAssertFalse(controller.configurationControlsEnabledForTesting)
        XCTAssertFalse(controller.modeControlEnabledForTesting)
        controller.selectHotkeyForTesting(.leftControl)
        controller.selectModeForTesting(.toggle)
        controller.selectModelForTesting(.smallEnglish)
        controller.selectProcessingModeForTesting(.decodeWhileSpeaking)
        controller.setInternalDictionaryForTesting(["Codex"])
        controller.setKeepsLatestDictationForTesting(false)
        controller.selectLimitForTesting(.seconds30)
        controller.selectThemeForTesting(.dracula)
        controller.setLoginItemForTesting(enabled: true)
        controller.setAutomaticUpdateChecksForTesting(true)
        controller.checkForUpdatesForTesting()

        XCTAssertEqual(mutationCount, 0)
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(service.unregisterCallCount, 0)
    }

    @MainActor
    func testUpdateControlsRenderAutomaticPreferenceAndCheckStatus() {
        let box = AdvancedSettingsStateBox(
            makeAdvancedSettingsState(
                automaticallyChecksForUpdates: true,
                softwareUpdateStatus: .available(
                    version: "3.2.0",
                    installable: true
                )
            )
        )
        let controller = makeController(
            box: box,
            service: AdvancedSettingsFakeLoginItemService()
        )

        XCTAssertTrue(controller.automaticallyChecksForUpdatesForTesting)
        XCTAssertEqual(
            controller.softwareUpdateStatusForTesting,
            "v3.2.0 available"
        )
        XCTAssertTrue(controller.checkForUpdatesIsEnabledForTesting)
        XCTAssertEqual(
            controller.checkForUpdatesTitleForTesting,
            "Update and Restart"
        )

        box.value = makeAdvancedSettingsState(
            automaticallyChecksForUpdates: true,
            softwareUpdateStatus: .checking
        )
        controller.refresh()

        XCTAssertEqual(controller.softwareUpdateStatusForTesting, "Checking...")
        XCTAssertFalse(controller.checkForUpdatesIsEnabledForTesting)
        XCTAssertTrue(
            controller.controlsFitWindowForTesting,
            controller.controlsOutsideWindowForTesting.joined(separator: ", ")
        )
    }

    @MainActor
    func testAvailableInstallableUpdateRoutesUpdateAndRestart() {
        let box = AdvancedSettingsStateBox(
            makeAdvancedSettingsState(
                softwareUpdateStatus: .available(
                    version: "3.2.0",
                    installable: true
                )
            )
        )
        var checkCount = 0
        var installCount = 0
        let controller = AdvancedSettingsWindowController(
            stateProvider: { box.value },
            actions: AdvancedSettingsActions(
                selectDictationMode: { _ in },
                selectHotkey: { _ in },
                selectModel: { _ in },
                selectRecordingLimit: { _ in },
                checkForUpdates: { checkCount += 1 },
                installUpdate: { installCount += 1 }
            ),
            loginItemManager: makeLoginItemManager()
        )

        controller.checkForUpdatesForTesting()

        XCTAssertEqual(checkCount, 0)
        XCTAssertEqual(installCount, 1)
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
    engine: RecognitionEngine = .whisperCppMetal,
    decodingProfile: DecodingProfile = .precision,
    processingMode: ModelProcessingMode = .afterRecording,
    internalDictionaryEntries: [String] = [],
    keepsLatestDictation: Bool = true,
    limit: RecordingLimit = .minutes10,
    theme: BadgeTheme = .defaultTheme,
    themeSelection: BadgeThemeSelection? = nil,
    customThemes: [CustomBadgeTheme] = [],
    availableModels: Set<DictationModel> = [.baseEnglish],
    availableEngines: Set<RecognitionEngine> = [.whisperCppMetal],
    configurationEnabled: Bool = true,
    automaticallyChecksForUpdates: Bool = false,
    softwareUpdateStatus: SoftwareUpdateStatus = .idle
) -> AdvancedSettingsState {
    AdvancedSettingsState(
        selectedHotkey: hotkey,
        activationMode: mode,
        selectedModel: model,
        selectedEngine: engine,
        decodingProfile: decodingProfile,
        processingMode: processingMode,
        internalDictionaryEntries: internalDictionaryEntries,
        keepsLatestDictation: keepsLatestDictation,
        recordingLimit: limit,
        selectedTheme: themeSelection ?? .builtIn(theme),
        customThemes: customThemes,
        availableModels: availableModels,
        availableEngines: availableEngines,
        configurationEnabled: configurationEnabled,
        automaticallyChecksForUpdates: automaticallyChecksForUpdates,
        softwareUpdateStatus: softwareUpdateStatus
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
