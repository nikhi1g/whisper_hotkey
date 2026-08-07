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
            ["Base", "Turbo"]
        )
    }

    @MainActor
    func testParakeetOffersAFourthEngineAndDisablesDecoding() {
        let box = AdvancedSettingsStateBox(
            makeAdvancedSettingsState(
                model: .largeV3TurboQ5,
                selectedParakeetVariant: .accurate,
                engine: .parakeetCoreML,
                decodingProfile: .adaptive,
                availableModels: Set(DictationModel.allCases),
                availableEngines: Set(RecognitionEngine.allCases)
            )
        )
        let controller = makeController(
            box: box,
            service: AdvancedSettingsFakeLoginItemService()
        )
        controller.showWindow(nil)

        // Index 3 is the recognition list: every option plus its group
        // headings and the separators between them.
        XCTAssertGreaterThanOrEqual(
            controller.optionCountsForTesting[3],
            RecognitionChoice.allCases.count
        )
        XCTAssertEqual(controller.selectedEngineForTesting, .parakeetCoreML)
        // A transducer has no beam search, so the row is gone, not greyed.
        XCTAssertFalse(controller.decodingRowVisibleForTesting)
        // One flat list holds every configuration, grouped by family, so no
        // combination is hidden behind a second control.
        XCTAssertEqual(
            controller.recognitionChoiceLabelsForTesting.count,
            RecognitionChoice.allCases.count
        )
        XCTAssertEqual(
            controller.recognitionChoiceHeadingsForTesting,
            RecognitionChoice.Group.allCases.map(\.displayName)
        )
        XCTAssertEqual(
            controller.recognitionRowTitlesForTesting,
            [
                "Quality", "Model", "Decoding", "Processing",
                "Internal dictionary", "Recording limit",
            ]
        )
        controller.close()
    }

    @MainActor
    func testParakeetSettingsFitTheWindow() {
        // Deliberately does not order the window on screen. showWindow lets the
        // host display constrain the frame, which made this assertion depend on
        // the machine rather than on the layout, and it failed on CI while
        // passing locally.
        let box = AdvancedSettingsStateBox(
            makeAdvancedSettingsState(
                model: .largeV3TurboQ5,
                selectedParakeetVariant: .accurate,
                engine: .parakeetCoreML,
                availableModels: Set(DictationModel.allCases),
                availableEngines: Set(RecognitionEngine.allCases)
            )
        )
        let controller = makeController(
            box: box,
            service: AdvancedSettingsFakeLoginItemService()
        )
        XCTAssertTrue(
            controller.controlsFitWindowForTesting,
            controller.controlsOutsideWindowForTesting.joined(separator: ", ")
        )
    }

    @MainActor
    func testInternalDictionaryRowIsHiddenOnAnEngineWithoutPrompts() {
        let box = AdvancedSettingsStateBox(
            makeAdvancedSettingsState(
                engine: .parakeetCoreML,
                internalDictionaryEntries: ["Codex", "projLab"],
                availableModels: Set(DictationModel.allCases),
                availableEngines: Set(RecognitionEngine.allCases)
            )
        )
        let controller = makeController(
            box: box,
            service: AdvancedSettingsFakeLoginItemService()
        )
        controller.showWindow(nil)

        // An engine that accepts no prompt has no vocabulary setting, so the
        // row is hidden rather than shown disabled under a sentence
        // explaining why it does nothing.
        XCTAssertFalse(controller.internalDictionaryRowVisibleForTesting)
        XCTAssertEqual(
            controller.internalDictionaryEntriesForTesting,
            ["Codex", "projLab"]
        )

        box.value = makeAdvancedSettingsState(
            engine: .whisperCppMetal,
            internalDictionaryEntries: ["Codex", "projLab"],
            availableModels: Set(DictationModel.allCases),
            availableEngines: Set(RecognitionEngine.allCases)
        )
        controller.refresh()

        XCTAssertTrue(controller.internalDictionaryRowVisibleForTesting)
        XCTAssertTrue(controller.internalDictionaryControlsEnabledForTesting)
        // Switching engines never touched the stored list.
        XCTAssertEqual(
            controller.internalDictionaryEntriesForTesting,
            ["Codex", "projLab"]
        )
        controller.close()
    }

    @MainActor
    func testSwitchingEnginesBackAndForthKeepsBothModelRowsUsable() {
        // The box is updated by the actions the way the application delegate
        // updates it, so the controller sees a changed engine on the refresh
        // that follows its own action.
        final class Selection {
            var engine: RecognitionEngine = .whisperCppMetal
            var model: DictationModel = .largeV3TurboQ5
            var variant: ParakeetVariant = .accurate
        }
        let selection = Selection()
        let controller = AdvancedSettingsWindowController(
            stateProvider: {
                makeAdvancedSettingsState(
                    model: selection.model,
                    selectedParakeetVariant: selection.variant,
                    engine: selection.engine,
                    availableModels: Set(DictationModel.allCases),
                    availableEngines: Set(RecognitionEngine.allCases)
                )
            },
            actions: AdvancedSettingsActions(
                selectDictationMode: { _ in },
                selectHotkey: { _ in },
                selectModel: { selection.model = $0 },
                selectParakeetVariant: { selection.variant = $0 },
                selectEngine: { selection.engine = $0 },
                selectRecordingLimit: { _ in }
            ),
            loginItemManager: makeLoginItemManager()
        )
        controller.showWindow(nil)

        for iteration in 0..<8 {
            controller.selectRecognitionChoiceForTesting(.parakeetAccurate)
            XCTAssertEqual(
                controller.recognitionChoiceLabelsForTesting.count,
                RecognitionChoice.allCases.count,
                "list lost options on iteration \(iteration)"
            )

            controller.selectRecognitionChoiceForTesting(.whisperTurboMetal)
            XCTAssertEqual(
                controller.recognitionChoiceLabelsForTesting.count,
                RecognitionChoice.allCases.count,
                "list lost options on iteration \(iteration)"
            )
        }
        controller.close()
    }

    @MainActor
    func testPopulatesSelectionsAndMarksUnavailableModels() {
        let box = AdvancedSettingsStateBox(
            makeAdvancedSettingsState(
                hotkey: .rightOption,
                mode: .toggle,
                model: .largeV3TurboQ5,
                decodingProfile: .adaptive,
                processingMode: .decodeWhileSpeaking,
                internalDictionaryEntries: ["Codex", "Claude Code"],
                limit: .minutes5,
                availableModels: [.baseEnglish, .largeV3TurboQ5]
            )
        )
        let service = AdvancedSettingsFakeLoginItemService(state: .enabled)
        let controller = makeController(box: box, service: service)

        XCTAssertEqual(controller.selectedHotkeyForTesting, .rightOption)
        XCTAssertEqual(controller.selectedModeForTesting, .toggle)
        XCTAssertEqual(controller.selectedModelForTesting, .largeV3TurboQ5)
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
        XCTAssertEqual(
            controller.recognitionChoiceIsEnabledForTesting(.whisperTurboMetal),
            true
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
            CGSize(width: 620, height: 744)
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
                "Press and Hold", "Pause Mode", "Base",
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
    func testCohereUsesNativeDecodingAndHidesTheProfileRow() {
        let box = AdvancedSettingsStateBox(
            makeAdvancedSettingsState(
                engine: .cohereCoreML,
                decodingProfile: .adaptive,
                availableEngines: Set(RecognitionEngine.allCases)
            )
        )
        let controller = makeController(
            box: box,
            service: AdvancedSettingsFakeLoginItemService()
        )
        controller.showWindow(nil)

        // The row is hidden rather than greyed. A disabled segmented control
        // still paints its selection, which reads as an active setting.
        XCTAssertFalse(controller.decodingRowVisibleForTesting)
        // The stored profile survives, so switching back to a whisper.cpp
        // engine restores the choice instead of resetting it.
        XCTAssertEqual(
            controller.selectedDecodingProfileForTesting,
            .adaptive
        )
        controller.close()
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
        var selectedChoices: [RecognitionChoice] = []
        var selectedDecodingProfiles: [DecodingProfile] = []
        var processingSelections: [ModelProcessingMode] = []
        var dictionaryAdditions: [[String]] = []
        var dictionaryRemovals: [String] = []
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
                selectRecognitionChoice: { selectedChoices.append($0) },
                selectDecodingProfile: {
                    selectedDecodingProfiles.append($0)
                },
                selectProcessingMode: { processingSelections.append($0) },
                addInternalDictionaryEntries: {
                    dictionaryAdditions.append($0)
                },
                removeInternalDictionaryEntry: {
                    dictionaryRemovals.append($0)
                },
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
        controller.selectDecodingProfileForTesting(.adaptive)
        controller.selectRecognitionChoiceForTesting(.whisperTurboMetal)
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
        XCTAssertEqual(selectedChoices, [.whisperTurboMetal])
        XCTAssertEqual(selectedDecodingProfiles, [.adaptive])
        XCTAssertEqual(processingSelections, [.decodeWhileSpeaking])
        XCTAssertEqual(dictionaryAdditions, [["Codex", "Claude Code"]])
        XCTAssertTrue(dictionaryRemovals.isEmpty)
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
    func testDictionaryDraftIsIsolatedFromExplicitExistingEntryRemoval() {
        let box = AdvancedSettingsStateBox(
            makeAdvancedSettingsState(
                internalDictionaryEntries: ["AGENTS.md", "Codex"]
            )
        )
        var additions: [[String]] = []
        var removals: [String] = []
        let controller = AdvancedSettingsWindowController(
            stateProvider: { box.value },
            actions: AdvancedSettingsActions(
                selectDictationMode: { _ in },
                selectHotkey: { _ in },
                selectModel: { _ in },
                addInternalDictionaryEntries: { additions.append($0) },
                removeInternalDictionaryEntry: { removals.append($0) },
                selectRecordingLimit: { _ in }
            ),
            loginItemManager: makeLoginItemManager()
        )

        controller.appendDictatedInternalDictionaryDraft(
            "Add SAM, and projLab"
        )
        XCTAssertEqual(
            controller.internalDictionaryDraftForTesting,
            "Add SAM, and projLab"
        )
        XCTAssertTrue(
            controller.internalDictionaryPreviewForTesting.contains(
                "Ready: SAM · projLab"
            )
        )

        controller.removeInternalDictionaryEntryForTesting(at: 0)
        XCTAssertEqual(removals, ["AGENTS.md"])
        XCTAssertEqual(
            controller.internalDictionaryDraftForTesting,
            "Add SAM, and projLab"
        )
        XCTAssertTrue(additions.isEmpty)

        controller.addInternalDictionaryDraftForTesting()
        XCTAssertEqual(additions, [["SAM", "projLab"]])
        XCTAssertEqual(controller.internalDictionaryDraftForTesting, "")
    }

    @MainActor
    func testDictionaryDraftCanOwnTheAppLocalDictationDestination() {
        let box = AdvancedSettingsStateBox(makeAdvancedSettingsState())
        let controller = makeController(
            box: box,
            service: AdvancedSettingsFakeLoginItemService()
        )

        XCTAssertFalse(controller.internalDictionaryDraftIsFocused)
        controller.appendDictatedInternalDictionaryDraft("Codex, projLab")
        controller.focusInternalDictionaryDraftForTesting()
        XCTAssertTrue(controller.internalDictionaryDraftIsFocused)
        XCTAssertTrue(controller.internalDictionaryDraftAddsOnReturnForTesting)
        XCTAssertEqual(
            controller.selectAllInternalDictionaryDraftForTesting(),
            NSRange(location: 0, length: "Codex, projLab".utf16.count)
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
                addInternalDictionaryEntries: { _ in mutationCount += 1 },
                removeInternalDictionaryEntry: { _ in mutationCount += 1 },
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
        controller.selectRecognitionChoiceForTesting(.whisperTurboMetal)
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

        box.value = makeAdvancedSettingsState(
            automaticallyChecksForUpdates: true,
            softwareUpdateStatus: .installationFailed
        )
        controller.refresh()

        XCTAssertEqual(controller.softwareUpdateStatusForTesting, "Update failed")
        XCTAssertTrue(controller.checkForUpdatesIsEnabledForTesting)
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
                model: .largeV3TurboQ5,
                availableModels: [.baseEnglish]
            )
        )
        var selectedChoices: [RecognitionChoice] = []
        let controller = AdvancedSettingsWindowController(
            stateProvider: { box.value },
            actions: AdvancedSettingsActions(
                selectDictationMode: { _ in },
                selectHotkey: { _ in },
                selectModel: { _ in },
                selectRecognitionChoice: { selectedChoices.append($0) },
                selectRecordingLimit: { _ in }
            ),
            loginItemManager: makeLoginItemManager()
        )

        XCTAssertEqual(controller.selectedModelForTesting, .largeV3TurboQ5)
        XCTAssertTrue(controller.configurationControlsEnabledForTesting)

        // An option whose model is not installed is still listed, so there is
        // always a way back to one that is.
        controller.selectRecognitionChoiceForTesting(.whisperTurboMetal)
        XCTAssertEqual(selectedChoices, [.whisperTurboMetal])
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
    selectedParakeetVariant: ParakeetVariant = .defaultVariant,
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
        selectedParakeetVariant: selectedParakeetVariant,
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
