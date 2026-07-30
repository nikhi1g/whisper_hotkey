import Foundation
import XCTest
@testable import WhisperHotkeyCore

final class PreferenceTests: XCTestCase {
    func testModelChoicesStartAtBaseAndHaveUniqueFiles() {
        XCTAssertEqual(DictationModel.allCases.first, .baseEnglish)
        XCTAssertEqual(
            Set(DictationModel.allCases.map(\.fileName)).count,
            DictationModel.allCases.count
        )
        XCTAssertEqual(
            DictationModel.largeV3TurboQ5.fileName,
            "ggml-large-v3-turbo-q5_0.bin"
        )
    }

    func testModelLimitAndThemePreferencesPersistAndRejectUnknownValues() {
        let suite = "whisper_hotkey-tests-\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(DictationModel.selected(defaults: defaults), .baseEnglish)
        XCTAssertEqual(RecordingLimit.selected(defaults: defaults), .minutes10)
        XCTAssertEqual(BadgeTheme.selected(defaults: defaults), .githubDarkDimmed)

        defaults.set(
            DictationModel.smallEnglish.rawValue,
            forKey: WhisperHotkeyPreferenceKeys.dictationModel
        )
        defaults.set(
            RecordingLimit.minutes30.rawValue,
            forKey: WhisperHotkeyPreferenceKeys.recordingLimit
        )
        defaults.set(
            BadgeTheme.rosePine.rawValue,
            forKey: WhisperHotkeyPreferenceKeys.badgeTheme
        )
        XCTAssertEqual(DictationModel.selected(defaults: defaults), .smallEnglish)
        XCTAssertEqual(RecordingLimit.selected(defaults: defaults), .minutes30)
        XCTAssertEqual(BadgeTheme.selected(defaults: defaults), .rosePine)

        defaults.set(
            "unknown",
            forKey: WhisperHotkeyPreferenceKeys.dictationModel
        )
        defaults.set(
            "unknown",
            forKey: WhisperHotkeyPreferenceKeys.recordingLimit
        )
        defaults.set("unknown", forKey: WhisperHotkeyPreferenceKeys.badgeTheme)
        XCTAssertEqual(DictationModel.selected(defaults: defaults), .baseEnglish)
        XCTAssertEqual(RecordingLimit.selected(defaults: defaults), .minutes10)
        XCTAssertEqual(BadgeTheme.selected(defaults: defaults), .githubDarkDimmed)
    }

    func testProcessingModeDefaultsMigratesAndPersists() {
        let suite = "whisper-hotkey-readiness-\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(
            ModelProcessingMode.selected(defaults: defaults),
            .afterRecording
        )
        defaults.set(
            true,
            forKey: WhisperHotkeyPreferenceKeys.keepModelReady
        )
        XCTAssertEqual(
            ModelProcessingMode.selected(defaults: defaults),
            .modelReady
        )

        ModelProcessingMode.decodeWhileSpeaking.persist(defaults: defaults)
        XCTAssertEqual(
            ModelProcessingMode.selected(defaults: defaults),
            .decodeWhileSpeaking
        )
        XCTAssertTrue(
            defaults.bool(forKey: WhisperHotkeyPreferenceKeys.keepModelReady)
        )
        XCTAssertTrue(ModelProcessingMode.modelReady.keepsModelReady)
        XCTAssertTrue(
            ModelProcessingMode.decodeWhileSpeaking.decodesWhileSpeaking
        )
        XCTAssertFalse(ModelProcessingMode.afterRecording.keepsModelReady)
        XCTAssertEqual(
            ModelProcessingMode.allCases.map(\.displayName),
            ["After Recording", "Model Ready", "Decode While Speaking"]
        )
    }

    func testRecognitionEnginesDefaultToMetalAndPersist() {
        let suite = "whisper_hotkey-engines-\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(
            RecognitionEngine.selected(defaults: defaults),
            .whisperCppMetal
        )
        XCTAssertEqual(
            RecognitionEngine.allCases,
            [.whisperCppMetal, .whisperCppCoreML, .whisperKitCoreML]
        )
        defaults.set(
            RecognitionEngine.whisperKitCoreML.rawValue,
            forKey: WhisperHotkeyPreferenceKeys.recognitionEngine
        )
        XCTAssertEqual(
            RecognitionEngine.selected(defaults: defaults),
            .whisperKitCoreML
        )
        defaults.set(
            "unknown",
            forKey: WhisperHotkeyPreferenceKeys.recognitionEngine
        )
        XCTAssertEqual(
            RecognitionEngine.selected(defaults: defaults),
            .whisperCppMetal
        )
    }

    func testDecodingProfileDefaultsToPrecisionAndPersists() {
        let suite = "whisper_hotkey-decoding-\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(
            DecodingProfile.selected(defaults: defaults),
            .precision
        )
        XCTAssertEqual(
            DecodingProfile.allCases,
            [.precision, .adaptive]
        )
        defaults.set(
            DecodingProfile.adaptive.rawValue,
            forKey: WhisperHotkeyPreferenceKeys.decodingProfile
        )
        XCTAssertEqual(
            DecodingProfile.selected(defaults: defaults),
            .adaptive
        )
        defaults.set(
            "unknown",
            forKey: WhisperHotkeyPreferenceKeys.decodingProfile
        )
        XCTAssertEqual(
            DecodingProfile.selected(defaults: defaults),
            .precision
        )
    }

    func testRecordingLimitsCoverThirtySecondsThroughOneHour() {
        XCTAssertEqual(RecordingLimit.allCases.first?.seconds, 30)
        XCTAssertEqual(RecordingLimit.allCases.last?.seconds, 3_600)
        XCTAssertEqual(
            RecordingLimit.allCases.map(\.seconds),
            RecordingLimit.allCases.map(\.seconds).sorted()
        )
    }

    func testThemePickerProvidesElevenNamedPresets() {
        XCTAssertEqual(BadgeTheme.allCases.count, 11)
        XCTAssertEqual(BadgeTheme.allCases.first, .githubDarkDimmed)
        XCTAssertEqual(
            Set(BadgeTheme.allCases.map(\.displayName)).count,
            BadgeTheme.allCases.count
        )
    }
}
