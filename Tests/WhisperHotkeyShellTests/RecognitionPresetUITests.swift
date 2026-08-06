import AppKit
import XCTest
@testable import WhisperHotkeyShell
import WhisperHotkeyCore
import WhisperHotkeySystem

/// The Recognition row is the only recognition control most people will touch,
/// so it has to be honest about which of the two presets is in effect and stop
/// claiming one when the advanced controls have diverged.
final class RecognitionPresetUITests: XCTestCase {
    @MainActor
    private func controller(
        engine: RecognitionEngine,
        variant: ParakeetVariant,
        processing: ModelProcessingMode
    ) -> AdvancedSettingsWindowController {
        let controller = AdvancedSettingsWindowController(
            stateProvider: {
                AdvancedSettingsState(
                    selectedHotkey: .rightCommand,
                    activationMode: .hold,
                    selectedModel: .largeV3TurboQ5,
                    selectedParakeetVariant: variant,
                    selectedEngine: engine,
                    decodingProfile: .precision,
                    processingMode: processing,
                    recordingLimit: .minutes10,
                    availableModels: Set(DictationModel.allCases),
                    availableEngines: Set(RecognitionEngine.allCases),
                    configurationEnabled: true
                )
            },
            actions: AdvancedSettingsActions(
                selectDictationMode: { _ in },
                selectHotkey: { _ in },
                selectModel: { _ in },
                selectRecordingLimit: { _ in }
            ),
            loginItemManager: LoginItemManager(
                service: PresetFakeLoginItemService(),
                preferenceStore: PresetFakeLoginPreferenceStore()
            )
        )
        // Touching the window loads it, which builds the controls and runs the
        // first refresh. Without this the segmented controls have no segments.
        _ = controller.window
        controller.refresh()
        return controller
    }

    @MainActor
    func testOnlyTheTwoPresetsAreOffered() {
        let controller = controller(
            engine: .parakeetCoreML,
            variant: .accurate,
            processing: .decodeWhileSpeaking
        )
        XCTAssertEqual(
            controller.presetChipLabelsForTesting,
            ["Fast", "Accurate"]
        )
    }

    @MainActor
    func testAPresetConfigurationHidesTheAdvancedControls() {
        for (variant, expected) in [
            (ParakeetVariant.fast, RecognitionPreset.fast),
            (ParakeetVariant.accurate, RecognitionPreset.accurate),
        ] {
            let controller = controller(
                engine: .parakeetCoreML,
                variant: variant,
                processing: .decodeWhileSpeaking
            )
            XCTAssertEqual(controller.selectedPresetForTesting, expected)
            XCTAssertFalse(
                controller.advancedRecognitionVisibleForTesting,
                "\(expected) should fold the advanced controls away"
            )
        }
    }

    /// A configuration that matches no preset must not leave one highlighted,
    /// and must show the controls responsible for the divergence.
    @MainActor
    func testCustomShowsAdvancedAndSelectsNoPreset() {
        let controller = controller(
            engine: .whisperCppMetal,
            variant: .accurate,
            processing: .afterRecording
        )
        XCTAssertNil(controller.selectedPresetForTesting)
        XCTAssertTrue(controller.advancedRecognitionVisibleForTesting)
    }

    @MainActor
    func testEverythingStillFitsInBothStates() {
        for engine in [RecognitionEngine.parakeetCoreML, .whisperCppMetal] {
            let controller = controller(
                engine: engine,
                variant: .accurate,
                processing: engine == .parakeetCoreML
                    ? .decodeWhileSpeaking
                    : .afterRecording
            )
            XCTAssertTrue(
                controller.controlsFitWindowForTesting,
                controller.controlsOutsideWindowForTesting
                    .joined(separator: ", ")
            )
        }
    }
}

@MainActor
private final class PresetFakeLoginItemService: LoginItemService {
    var state: LoginItemServiceState = .notRegistered
    func register() throws { state = .enabled }
    func unregister() throws { state = .notRegistered }
    func openLoginItemsSettings() {}
}

@MainActor
private final class PresetFakeLoginPreferenceStore: LoginItemPreferenceStoring {
    var explicitlyDisabled = false
}
