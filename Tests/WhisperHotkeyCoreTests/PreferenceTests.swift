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

    func testModelAndLimitPreferencesPersistAndRejectUnknownValues() {
        let suite = "whisper_hotkey-tests-\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(DictationModel.selected(defaults: defaults), .baseEnglish)
        XCTAssertEqual(RecordingLimit.selected(defaults: defaults), .minutes10)

        defaults.set(
            DictationModel.smallEnglish.rawValue,
            forKey: WhisperHotkeyPreferenceKeys.dictationModel
        )
        defaults.set(
            RecordingLimit.minutes30.rawValue,
            forKey: WhisperHotkeyPreferenceKeys.recordingLimit
        )
        XCTAssertEqual(DictationModel.selected(defaults: defaults), .smallEnglish)
        XCTAssertEqual(RecordingLimit.selected(defaults: defaults), .minutes30)

        defaults.set(
            "unknown",
            forKey: WhisperHotkeyPreferenceKeys.dictationModel
        )
        defaults.set(
            "unknown",
            forKey: WhisperHotkeyPreferenceKeys.recordingLimit
        )
        XCTAssertEqual(DictationModel.selected(defaults: defaults), .baseEnglish)
        XCTAssertEqual(RecordingLimit.selected(defaults: defaults), .minutes10)
    }

    func testRecordingLimitsCoverThirtySecondsThroughOneHour() {
        XCTAssertEqual(RecordingLimit.allCases.first?.seconds, 30)
        XCTAssertEqual(RecordingLimit.allCases.last?.seconds, 3_600)
        XCTAssertEqual(
            RecordingLimit.allCases.map(\.seconds),
            RecordingLimit.allCases.map(\.seconds).sorted()
        )
    }
}
