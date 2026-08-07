import XCTest
@testable import WhisperHotkeyShell
import WhisperHotkeyCore

/// The guide describes what is running. Naming a model or a decoding profile
/// that the selected engine does not use is the same class of defect as a
/// Settings row that reports a value it does not control.
final class UserGuidePopoverControllerTests: XCTestCase {
    private func state(
        engine: RecognitionEngine,
        variant: ParakeetVariant = .accurate
    ) -> AdvancedSettingsState {
        AdvancedSettingsState(
            selectedHotkey: .rightCommand,
            activationMode: .hold,
            selectedModel: .largeV3TurboQ5,
            selectedParakeetVariant: variant,
            selectedEngine: engine,
            decodingProfile: .precision,
            processingMode: .afterRecording,
            recordingLimit: .minutes10,
            availableModels: Set(DictationModel.allCases),
            availableEngines: Set(RecognitionEngine.allCases),
            configurationEnabled: true
        )
    }

    private func rows(
        _ state: AdvancedSettingsState
    ) -> [UserGuideRow] {
        UserGuideContent.sections(for: state).flatMap(\.rows)
    }

    func testParakeetGuideNamesItsOwnCheckpointAndNoWhisperModel() {
        let guide = rows(state(engine: .parakeetCoreML, variant: .fast))
        let modelRows = guide.filter { $0.key == "model" }
        XCTAssertEqual(modelRows.map(\.title), ["Fast", "Accurate", "Unified"])
        let whisperNames = Set(
            DictationModel.allCases.map(DictationModelPresentation.chipTitle)
        )
        XCTAssertTrue(
            guide.allSatisfy { !whisperNames.contains($0.title) },
            "guide named a whisper model while Parakeet was selected"
        )
    }

    func testDecodingIsAbsentForEnginesWithoutBeamSearch() {
        for engine in RecognitionEngine.allCases
        where !engine.usesWhisperDecoding {
            XCTAssertTrue(
                rows(state(engine: engine)).allSatisfy { $0.key != "decoding" },
                "\(engine) has no beam search but the guide showed decoding"
            )
        }
    }

    func testWhisperGuideStillDescribesItsModelAndDecoding() {
        let guide = rows(state(engine: .whisperCppMetal))
        XCTAssertEqual(
            guide.filter { $0.key == "model" }.first?.title,
            DictationModelPresentation.chipTitle(for: .largeV3TurboQ5)
        )
        XCTAssertEqual(
            guide.filter { $0.key == "decoding" }.first?.title,
            DecodingProfile.precision.displayName
        )
    }

    /// Decoding belongs directly after Engine. It is positioned by key rather
    /// than a fixed offset so a new row above it cannot displace it.
    func testDecodingFollowsEngineInTheCurrentPath() {
        let current = UserGuideContent.sections(
            for: state(engine: .whisperCppMetal)
        )[0].rows.map(\.key)
        guard let engineIndex = current.firstIndex(of: "engine") else {
            return XCTFail("no engine row")
        }
        XCTAssertEqual(current[current.index(after: engineIndex)], "decoding")
    }
}
