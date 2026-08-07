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
            case .cohereCoreML:
                XCTAssertNotNil(
                    RecognitionChoice.matching(
                        engine: engine,
                        model: .baseEnglish,
                        parakeetVariant: .accurate
                    )
                )
            case .whisperCppMetal, .whisperCppCoreML, .whisperKitCoreML:
                for model in DictationModel.allCases {
                    XCTAssertNotNil(
                        RecognitionChoice.matching(
                            engine: engine,
                            model: model,
                            parakeetVariant: .accurate
                        ),
                        "no option for \(engine) with \(model)"
                    )
                }
            }
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
        XCTAssertNotNil(RecognitionChoice.cohereTranscribe.downloadDescription)
    }

    func testDefaultIsABundledParakeetOption() {
        let choice = RecognitionChoice.defaultChoice
        XCTAssertEqual(choice.engine, .parakeetCoreML)
        XCTAssertNil(choice.downloadDescription)
    }
}
