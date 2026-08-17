import Foundation
import XCTest
@testable import WhisperHotkeyCore

final class PostProcessingContractTests: XCTestCase {
    func testDocumentedLimitConstantsMatchTheContract() {
        XCTAssertEqual(PostProcessLimits.maxRawTextLength, 4_000)
        XCTAssertEqual(PostProcessLimits.maxFinalTextLength, 8_000)
        XCTAssertEqual(PostProcessLimits.maxAlternatives, 8)
        XCTAssertEqual(PostProcessLimits.maxUncertainSpans, 32)
        XCTAssertEqual(PostProcessLimits.maxProtectedTerms, 128)
        XCTAssertEqual(PostProcessLimits.maxGlossaryTerms, 64)
        XCTAssertEqual(PostProcessLimits.maxCorrections, 32)
    }

    func testValidateRequestRejectsOverLengthRawText() {
        let request = makeRequest(rawText: String(repeating: "a", count: 4_001))
        assertLimitExceeded(
            try PostProcessLimits.validateRequest(request),
            field: "request.raw_text",
            actual: 4_001,
            maximum: PostProcessLimits.maxRawTextLength
        )
    }

    func testValidateRequestAcceptsRawTextAtTheBound() throws {
        let request = makeRequest(rawText: String(repeating: "a", count: 4_000))
        XCTAssertNoThrow(try PostProcessLimits.validateRequest(request))
    }

    func testValidateRequestRejectsOverCountAlternatives() {
        let request = makeRequest(alternatives: Array(repeating: "alt", count: 9))
        assertLimitExceeded(
            try PostProcessLimits.validateRequest(request),
            field: "request.alternatives",
            actual: 9,
            maximum: PostProcessLimits.maxAlternatives
        )
    }

    func testValidateRequestRejectsOverLengthAlternative() {
        let request = makeRequest(alternatives: [String(repeating: "b", count: 201)])
        assertLimitExceeded(
            try PostProcessLimits.validateRequest(request),
            field: "request.alternatives[0]",
            actual: 201,
            maximum: 200
        )
    }

    func testValidateRequestRejectsOverCountUncertainSpans() {
        let request = makeRequest(uncertainSpans: Array(repeating: "span", count: 33))
        assertLimitExceeded(
            try PostProcessLimits.validateRequest(request),
            field: "request.uncertain_spans",
            actual: 33,
            maximum: PostProcessLimits.maxUncertainSpans
        )
    }

    func testValidateRequestRejectsOverCountProtectedTerms() {
        let request = makeRequest(protectedTerms: Array(repeating: "term", count: 129))
        assertLimitExceeded(
            try PostProcessLimits.validateRequest(request),
            field: "request.protected_terms",
            actual: 129,
            maximum: PostProcessLimits.maxProtectedTerms
        )
    }

    func testValidateRequestRejectsOverCountGlossaryTerms() {
        let request = makeRequest(
            context: PostProcessContext(glossary: Array(repeating: "word", count: 65))
        )
        assertLimitExceeded(
            try PostProcessLimits.validateRequest(request),
            field: "context.glossary",
            actual: 65,
            maximum: PostProcessLimits.maxGlossaryTerms
        )
    }

    func testValidateResultRejectsOverLengthFinalText() {
        let result = makeResult(finalText: String(repeating: "c", count: 8_001))
        assertLimitExceeded(
            try PostProcessLimits.validateResult(result),
            field: "result.final_text",
            actual: 8_001,
            maximum: PostProcessLimits.maxFinalTextLength
        )
    }

    func testValidateResultRejectsOverLengthIntent() {
        let result = makeResult(intent: String(repeating: "i", count: 401))
        assertLimitExceeded(
            try PostProcessLimits.validateResult(result),
            field: "result.intent",
            actual: 401,
            maximum: 400
        )
    }

    func testValidateResultRejectsOverCountCorrections() {
        let result = makeResult(explicitCorrections: Array(repeating: "fix", count: 33))
        assertLimitExceeded(
            try PostProcessLimits.validateResult(result),
            field: "result.explicit_corrections",
            actual: 33,
            maximum: PostProcessLimits.maxCorrections
        )
    }

    func testValidateResultRejectsOverLengthCorrection() {
        let result = makeResult(explicitCorrections: [String(repeating: "x", count: 161)])
        assertLimitExceeded(
            try PostProcessLimits.validateResult(result),
            field: "result.explicit_corrections[0]",
            actual: 161,
            maximum: 160
        )
    }

    func testValidateResultRejectsOverCountUnresolvedSpans() {
        let result = makeResult(unresolvedSpans: Array(repeating: "unclear", count: 33))
        assertLimitExceeded(
            try PostProcessLimits.validateResult(result),
            field: "result.unresolved_spans",
            actual: 33,
            maximum: 32
        )
    }

    func testValidRequestAndResultAtMaximumBoundsPass() throws {
        let request = makeRequest(
            rawText: String(repeating: "a", count: 4_000),
            alternatives: Array(repeating: String(repeating: "b", count: 200), count: 8),
            uncertainSpans: Array(repeating: String(repeating: "c", count: 80), count: 32),
            protectedTerms: Array(repeating: String(repeating: "d", count: 80), count: 128),
            context: PostProcessContext(glossary: Array(repeating: String(repeating: "e", count: 80), count: 64))
        )
        XCTAssertNoThrow(try PostProcessLimits.validateRequest(request))

        let result = makeResult(
            finalText: String(repeating: "f", count: 8_000),
            intent: String(repeating: "g", count: 400),
            unresolvedSpans: Array(repeating: String(repeating: "h", count: 160), count: 32),
            explicitCorrections: Array(repeating: String(repeating: "i", count: 160), count: 32)
        )
        XCTAssertNoThrow(try PostProcessLimits.validateResult(result))
    }

    func testEmptyRequestAndResultPass() throws {
        let request = makeRequest(rawText: "")
        XCTAssertNoThrow(try PostProcessLimits.validateRequest(request))
        let result = makeResult(finalText: "", intent: "")
        XCTAssertNoThrow(try PostProcessLimits.validateResult(result))
    }

    private func makeRequest(
        rawText: String = "hello",
        alternatives: [String] = [],
        uncertainSpans: [String] = [],
        protectedTerms: [String] = [],
        context: PostProcessContext = PostProcessContext()
    ) -> PostProcessRequest {
        PostProcessRequest(
            rawText: rawText,
            profile: .clarity,
            locale: "en-US",
            context: context,
            alternatives: alternatives,
            uncertainSpans: uncertainSpans,
            protectedTerms: protectedTerms
        )
    }

    private func makeResult(
        finalText: String = "hello",
        intent: String = "",
        unresolvedSpans: [String] = [],
        explicitCorrections: [String] = []
    ) -> PostProcessResult {
        PostProcessResult(
            finalText: finalText,
            intent: intent,
            unresolvedSpans: unresolvedSpans,
            explicitCorrections: explicitCorrections,
            meaningChangeRisk: .low
        )
    }

    private func assertLimitExceeded(
        _ expression: @autoclosure () throws -> Void,
        field: String,
        actual: Int,
        maximum: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            guard case PostProcessContractError.limitExceeded(
                let errorField,
                let errorActual,
                let errorMaximum
            ) = error else {
                XCTFail("expected limitExceeded, got \(error)", file: file, line: line)
                return
            }
            XCTAssertEqual(errorField, field, file: file, line: line)
            XCTAssertEqual(errorActual, actual, file: file, line: line)
            XCTAssertEqual(errorMaximum, maximum, file: file, line: line)
        }
    }
}

/// The user-authored fourth profile: its objective is the owner's prompt,
/// while the transducer constraints and JSON contract stay built in.
final class CustomSemanticProfileTests: XCTestCase {
    func testCustomProfileUsesTheOwnersPrompt() {
        let profile = SemanticProfileCatalog.profile(
            .custom,
            customObjective: "  Rewrite as a terse bullet list.  "
        )
        XCTAssertEqual(profile.id, .custom)
        XCTAssertEqual(profile.objective, "Rewrite as a terse bullet list.")
    }

    func testBlankCustomPromptFallsBackToTheDefaultObjective() {
        XCTAssertEqual(
            SemanticProfileCatalog.profile(.custom, customObjective: "   ")
                .objective,
            SemanticProfileCatalog.defaultCustomObjective
        )
        XCTAssertEqual(
            SemanticProfileCatalog.profile(.custom).objective,
            SemanticProfileCatalog.defaultCustomObjective
        )
    }

    func testBuiltInProfilesIgnoreTheCustomPrompt() {
        for id in SemanticProfileID.allCases where id != .custom {
            XCTAssertEqual(
                SemanticProfileCatalog.profile(id, customObjective: "ignored"),
                SemanticProfileCatalog.profile(id)
            )
        }
    }

    func testCustomPromptRoundTripsThroughPreferences() {
        let defaults = UserDefaults(
            suiteName: "custom-prompt-\(UUID().uuidString)"
        )!
        XCTAssertEqual(
            PostProcessingPreference.customPrompt(defaults: defaults),
            PostProcessingPreference.defaultCustomPrompt
        )
        PostProcessingPreference.setCustomPrompt(
            "Make it a changelog entry.",
            defaults: defaults
        )
        XCTAssertEqual(
            PostProcessingPreference.customPrompt(defaults: defaults),
            "Make it a changelog entry."
        )
        PostProcessingPreference.setCustomPrompt("  ", defaults: defaults)
        XCTAssertEqual(
            PostProcessingPreference.customPrompt(defaults: defaults),
            PostProcessingPreference.defaultCustomPrompt
        )
    }

    func testStoredCustomPromptIsBounded() {
        let defaults = UserDefaults(
            suiteName: "custom-prompt-\(UUID().uuidString)"
        )!
        PostProcessingPreference.setCustomPrompt(
            String(repeating: "x", count: 5_000),
            defaults: defaults
        )
        XCTAssertEqual(
            PostProcessingPreference.customPrompt(defaults: defaults).count,
            PostProcessingPreference.maximumCustomPromptLength
        )
    }
}

/// The owner may keep as many system prompts as they like and switch between
/// them; the selected one is what the custom profile sends.
final class CustomPromptLibraryTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "prompt-library-\(UUID().uuidString)")!
    }

    func testLibrarySeedsOnePromptAndSelectsIt() {
        let defaults = makeDefaults()
        XCTAssertEqual(CustomPromptLibrary.prompts(defaults: defaults).count, 1)
        XCTAssertEqual(CustomPromptLibrary.selectedIndex(defaults: defaults), 0)
        XCTAssertEqual(
            CustomPromptLibrary.selectedPrompt(defaults: defaults).prompt,
            SemanticProfileCatalog.defaultCustomObjective
        )
    }

    func testAddingSelectsTheNewPromptAndDrivesTheProfile() {
        let defaults = makeDefaults()
        CustomPromptLibrary.add(
            CustomPrompt(name: "Shouty", prompt: "ALL CAPS please."),
            defaults: defaults
        )
        XCTAssertEqual(CustomPromptLibrary.selectedIndex(defaults: defaults), 1)
        XCTAssertEqual(
            PostProcessingPreference.customPrompt(defaults: defaults),
            "ALL CAPS please."
        )
        XCTAssertEqual(
            SemanticProfileCatalog.profile(
                .custom,
                customObjective: PostProcessingPreference.customPrompt(
                    defaults: defaults
                )
            ).objective,
            "ALL CAPS please."
        )
    }

    func testEditingChangesOnlyTheSelectedPrompt() {
        let defaults = makeDefaults()
        CustomPromptLibrary.add(
            CustomPrompt(name: "Second", prompt: "Second prompt."),
            defaults: defaults
        )
        PostProcessingPreference.setCustomPrompt("Edited.", defaults: defaults)
        let library = CustomPromptLibrary.prompts(defaults: defaults)
        XCTAssertEqual(library.count, 2)
        XCTAssertEqual(library[0].prompt, PostProcessingPreference.defaultCustomPrompt)
        XCTAssertEqual(library[1].prompt, "Edited.")
        XCTAssertEqual(library[1].name, "Second")
    }

    func testRemovingKeepsTheSelectionInRangeAndNeverEmpties() {
        let defaults = makeDefaults()
        CustomPromptLibrary.add(
            CustomPrompt(name: "Second", prompt: "Second prompt."),
            defaults: defaults
        )
        CustomPromptLibrary.removeSelected(defaults: defaults)
        XCTAssertEqual(CustomPromptLibrary.prompts(defaults: defaults).count, 1)
        XCTAssertEqual(CustomPromptLibrary.selectedIndex(defaults: defaults), 0)

        CustomPromptLibrary.removeSelected(defaults: defaults)
        XCTAssertEqual(
            CustomPromptLibrary.prompts(defaults: defaults),
            [CustomPromptLibrary.defaultPrompt]
        )
    }

    func testLastRunSummaryIsRecordedForSettings() {
        let defaults = makeDefaults()
        XCTAssertNil(PostProcessingPreference.lastRun(defaults: defaults))
        PostProcessingPreference.recordLastRun(
            "enhanced in 2.1 s",
            defaults: defaults
        )
        XCTAssertTrue(
            PostProcessingPreference.lastRun(defaults: defaults)?
                .contains("enhanced in 2.1 s") ?? false
        )
    }
}
