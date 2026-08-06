import XCTest
@testable import WhisperHotkeyCore

final class RecognitionPresetTests: XCTestCase {
    func testOnlyTwoPresetsAreSelectable() {
        // Custom is a reported state, never something a user picks.
        XCTAssertEqual(RecognitionPreset.selectable, [.fast, .accurate])
        XCTAssertFalse(RecognitionPreset.selectable.contains(.custom))
    }

    func testEachPresetResolvesToADistinctConfiguration() {
        let resolutions = RecognitionPreset.selectable.map(\.resolution)
        XCTAssertEqual(Set(resolutions.map(\.parakeetVariant)).count, 2)
    }

    func testResolutionsRoundTripThroughMatching() {
        for preset in RecognitionPreset.selectable {
            let resolution = preset.resolution
            XCTAssertEqual(
                RecognitionPreset.matching(
                    engine: resolution.engine,
                    parakeetVariant: resolution.parakeetVariant,
                    processingMode: resolution.processingMode
                ),
                preset
            )
        }
    }

    func testDivergingFromAPresetReportsCustom() {
        XCTAssertEqual(
            RecognitionPreset.matching(
                engine: .whisperCppMetal,
                parakeetVariant: .accurate,
                processingMode: .decodeWhileSpeaking
            ),
            .custom
        )
        XCTAssertEqual(
            RecognitionPreset.matching(
                engine: .parakeetCoreML,
                parakeetVariant: .accurate,
                processingMode: .afterRecording
            ),
            .custom
        )
    }

    /// Parakeet has no beam search, so a stored decoding profile cannot change
    /// what a preset does and must not be able to knock it into Custom.
    func testDecodingProfileIsNotPartOfPresetIdentity() {
        for preset in RecognitionPreset.selectable {
            let resolution = preset.resolution
            XCTAssertFalse(resolution.engine.usesWhisperDecoding)
        }
    }

    func testBothPresetsUseAnEngineThatShipsInsideTheApp() {
        // Neither preset may require a download to honor its label.
        for preset in RecognitionPreset.selectable {
            XCTAssertEqual(preset.resolution.engine, .parakeetCoreML)
        }
    }
}
