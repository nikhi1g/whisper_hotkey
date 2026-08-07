import XCTest
@testable import WhisperHotkeyCore

/// The flat list replaces the engine × model matrix in the interface, so it has
/// to keep every configuration that matrix could reach. A missing pairing is a
/// silently removed capability.
final class RecognitionChoiceTests: XCTestCase {
    func testEveryReachableEngineAndModelPairingIsOffered() {
        for engine in RecognitionEngine.allCases {
            switch engine {
            case .parakeetCoreML:
                for variant in ParakeetVariant.allCases {
                    XCTAssertNotNil(
                        RecognitionChoice.matching(
                            engine: engine,
                            model: .baseEnglish,
                            parakeetVariant: variant
                        ),
                        "no option for Parakeet \(variant)"
                    )
                }
            case .whisperCppMetal:
                // Whisper carries one option now, so every stored model has to
                // resolve to it rather than leaving the picker blank.
                for model in DictationModel.allCases {
                    XCTAssertEqual(
                        RecognitionChoice.matching(
                            engine: engine,
                            model: model,
                            parakeetVariant: .accurate
                        ),
                        .whisperTurboMetal,
                        "no option for \(engine) with \(model)"
                    )
                }
            }
        }
    }

    /// Engines retired in 3.5.7 and 3.5.9. A saved preference naming one must
    /// still resolve to something rather than dropping to the default: the two
    /// Core ML paths to Metal, which runs the same weights, and Cohere to
    /// Parakeet Accurate, which is bundled and beats it everywhere but clean
    /// read speech.
    func testRetiredEnginesMigrateToMetal() {
        let defaults = UserDefaults(
            suiteName: "RecognitionChoiceTests.\(UUID().uuidString)"
        )!
        for (rawValue, expected) in [
            ("whisperCppCoreML", RecognitionEngine.whisperCppMetal),
            ("whisperKitCoreML", .whisperCppMetal),
            ("cohereCoreML", .parakeetCoreML),
        ] {
            defaults.set(
                rawValue,
                forKey: WhisperHotkeyPreferenceKeys.recognitionEngine
            )
            XCTAssertEqual(
                RecognitionEngine.selected(defaults: defaults),
                expected,
                "\(rawValue) did not migrate"
            )
        }
    }

    func testEachOptionRoundTripsThroughItsStoredConfiguration() {
        for choice in RecognitionChoice.allCases {
            XCTAssertEqual(
                RecognitionChoice.matching(
                    engine: choice.engine,
                    model: choice.model,
                    parakeetVariant: choice.parakeetVariant
                ),
                choice
            )
        }
    }

    func testOptionsAreUniquelyNamedWithinTheWholeList() {
        // The picker is one flat menu, so two options sharing a label would be
        // indistinguishable even under different headings.
        let names = RecognitionChoice.allCases.map(\.displayName)
        XCTAssertEqual(Set(names).count, names.count)
    }

    func testBundledOptionsQuoteNoDownload() {
        XCTAssertNil(RecognitionChoice.parakeetAccurate.downloadDescription)
        XCTAssertNil(RecognitionChoice.whisperTurboMetal.downloadDescription)
        XCTAssertNotNil(RecognitionChoice.parakeetUnified.downloadDescription)
    }

    func testDefaultIsABundledParakeetOption() {
        let choice = RecognitionChoice.defaultChoice
        XCTAssertEqual(choice.engine, .parakeetCoreML)
        XCTAssertNil(choice.downloadDescription)
    }
}
