import Foundation
import XCTest
@testable import WhisperHotkeyCore

final class PreferenceTests: XCTestCase {
    func testFirstRunPerformanceProfileRespectsMemoryAndAvailability() {
        let allModels = Set(DictationModel.allCases)
        let constrained = FirstRunPerformanceProfile.recommended(
            physicalMemory: 4 * 1_024 * 1_024 * 1_024,
            availableModels: allModels
        )
        XCTAssertEqual(constrained.model, .baseEnglish)
        XCTAssertEqual(constrained.engine, .whisperCppMetal)
        XCTAssertEqual(constrained.decodingProfile, .precision)
        XCTAssertEqual(constrained.processingMode, .afterRecording)

        let responsive = FirstRunPerformanceProfile.recommended(
            physicalMemory: 8 * 1_024 * 1_024 * 1_024,
            availableModels: allModels
        )
        XCTAssertEqual(responsive.model, .smallEnglish)
        XCTAssertEqual(responsive.processingMode, .decodeWhileSpeaking)

        let highQuality = FirstRunPerformanceProfile.recommended(
            physicalMemory: 16 * 1_024 * 1_024 * 1_024,
            availableModels: allModels
        )
        XCTAssertEqual(highQuality.model, .largeV3TurboQ5)
        XCTAssertEqual(highQuality.processingMode, .decodeWhileSpeaking)

        let bundledOnly = FirstRunPerformanceProfile.recommended(
            physicalMemory: 64 * 1_024 * 1_024 * 1_024,
            availableModels: [.baseEnglish]
        )
        XCTAssertEqual(bundledOnly.model, .baseEnglish)
    }

    func testFirstRunBootstrapAppliesOnlyToAnEmptyPreferenceDomain() {
        let freshSuite = "whisper-hotkey-first-run-\(UUID().uuidString)"
        let freshDefaults = try! XCTUnwrap(
            UserDefaults(suiteName: freshSuite)
        )
        defer { freshDefaults.removePersistentDomain(forName: freshSuite) }
        var freshApplyCount = 0

        FirstRunPreferenceBootstrap.applyIfNeeded(
            defaults: freshDefaults,
            bundleIdentifier: freshSuite,
            version: 1
        ) {
            freshApplyCount += 1
            freshDefaults.set("recommended", forKey: "profile")
        }
        FirstRunPreferenceBootstrap.applyIfNeeded(
            defaults: freshDefaults,
            bundleIdentifier: freshSuite,
            version: 1
        ) {
            freshApplyCount += 1
        }
        XCTAssertEqual(freshApplyCount, 1)
        XCTAssertEqual(freshDefaults.string(forKey: "profile"), "recommended")

        let existingSuite = "whisper-hotkey-existing-\(UUID().uuidString)"
        let existingDefaults = try! XCTUnwrap(
            UserDefaults(suiteName: existingSuite)
        )
        defer { existingDefaults.removePersistentDomain(forName: existingSuite) }
        existingDefaults.set("user choice", forKey: "profile")
        var existingApplyCount = 0

        FirstRunPreferenceBootstrap.applyIfNeeded(
            defaults: existingDefaults,
            bundleIdentifier: existingSuite,
            version: 1
        ) {
            existingApplyCount += 1
            existingDefaults.set("replacement", forKey: "profile")
        }
        XCTAssertEqual(existingApplyCount, 0)
        XCTAssertEqual(existingDefaults.string(forKey: "profile"), "user choice")
        XCTAssertEqual(
            existingDefaults.integer(
                forKey: WhisperHotkeyPreferenceKeys.firstRunDefaultsVersion
            ),
            1
        )
    }

    func testAutomaticUpdateChecksDefaultOffAndPersist() {
        let suite = "whisper_hotkey-updates-\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertFalse(
            AutomaticUpdateCheckPreference.isEnabled(defaults: defaults)
        )
        AutomaticUpdateCheckPreference.setEnabled(true, defaults: defaults)
        XCTAssertTrue(
            AutomaticUpdateCheckPreference.isEnabled(defaults: defaults)
        )
        AutomaticUpdateCheckPreference.setEnabled(false, defaults: defaults)
        XCTAssertFalse(
            AutomaticUpdateCheckPreference.isEnabled(defaults: defaults)
        )
    }

    func testSemanticVersionsCompareStableTagsNumerically() {
        XCTAssertEqual(SemanticVersion("v3.1.0"), SemanticVersion("3.1"))
        XCTAssertLessThan(
            try! XCTUnwrap(SemanticVersion("3.1.9")),
            try! XCTUnwrap(SemanticVersion("3.2.0"))
        )
        XCTAssertLessThan(
            try! XCTUnwrap(SemanticVersion("3.9.0")),
            try! XCTUnwrap(SemanticVersion("10.0.0"))
        )
        XCTAssertEqual(
            SemanticVersion("v3.1.0-preview.2"),
            SemanticVersion("3.1.0")
        )
        XCTAssertNil(SemanticVersion("preview"))
        XCTAssertNil(SemanticVersion("3..1"))
    }

    func testLastDictationRetentionDefaultsOnAndPersists() {
        let suite = "whisper_hotkey-retention-\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(
            LastDictationRetentionPreference.isEnabled(defaults: defaults)
        )
        LastDictationRetentionPreference.setEnabled(
            false,
            defaults: defaults
        )
        XCTAssertFalse(
            LastDictationRetentionPreference.isEnabled(defaults: defaults)
        )
        LastDictationRetentionPreference.setEnabled(
            true,
            defaults: defaults
        )
        XCTAssertTrue(
            LastDictationRetentionPreference.isEnabled(defaults: defaults)
        )
    }

    func testLastDictationBufferClearsImmediatelyAndRejectsDisabledWrites() {
        var buffer = LastDictationBuffer(isEnabled: true)

        buffer.retainSuccessful("  first successful dictation  ")
        XCTAssertEqual(buffer.transcript, "first successful dictation")

        buffer.setEnabled(false)
        XCTAssertNil(buffer.transcript)
        buffer.retainSuccessful("must not remain")
        XCTAssertNil(buffer.transcript)

        buffer.setEnabled(true)
        buffer.retainSuccessful("next successful dictation")
        XCTAssertEqual(buffer.transcript, "next successful dictation")
    }

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
            [
                .whisperCppMetal,
                .whisperCppCoreML,
                .whisperKitCoreML,
                .parakeetCoreML,
            ]
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

    func testThemePickerProvidesGroupedNamedPresets() {
        XCTAssertEqual(BadgeTheme.allCases.count, 24)
        XCTAssertEqual(BadgeTheme.allCases.first, .githubDarkDimmed)
        XCTAssertEqual(
            BadgeTheme.allCases.filter { $0.mode == .dark }.count,
            14
        )
        XCTAssertEqual(
            BadgeTheme.allCases.filter { $0.mode == .light }.count,
            10
        )
        XCTAssertEqual(
            Set(BadgeTheme.allCases.map(\.displayName)).count,
            BadgeTheme.allCases.count
        )
    }

    func testCustomThemesValidatePersistAndRestoreSelection() {
        let suite = "whisper_hotkey-custom-theme-\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertNil(
            CustomBadgeTheme(
                name: "Broken",
                mode: .dark,
                backgroundHex: "#12345",
                textHex: "#FFFFFF",
                accentHex: "#00AAFF"
            )
        )
        let theme = try! XCTUnwrap(
            CustomBadgeTheme(
                name: "  Terminal Lime  ",
                mode: .dark,
                backgroundHex: "101216",
                textHex: "#f7f7f7",
                accentHex: "#aaff00"
            )
        )
        XCTAssertEqual(theme.name, "Terminal Lime")
        XCTAssertEqual(theme.backgroundHex, "#101216")
        XCTAssertEqual(theme.textHex, "#F7F7F7")
        XCTAssertEqual(theme.accentHex, "#AAFF00")

        CustomBadgeTheme.persist([theme], defaults: defaults)
        XCTAssertEqual(CustomBadgeTheme.load(defaults: defaults), [theme])

        let selection = BadgeThemeSelection.custom(theme)
        selection.persist(defaults: defaults)
        XCTAssertEqual(
            BadgeThemeSelection.selected(defaults: defaults),
            selection
        )
    }
}
