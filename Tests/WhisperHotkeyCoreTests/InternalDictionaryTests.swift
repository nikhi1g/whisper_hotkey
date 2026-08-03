import Foundation
import XCTest
@testable import WhisperHotkeyCore

final class InternalDictionaryTests: XCTestCase {
    func testNormalizesAndDeduplicatesEntriesWithoutChangingDisplayCase() {
        let dictionary = InternalDictionary(
            entries: [
                " Codex ",
                "",
                "codex",
                "Claude Code",
                "Café",
                "CAFE",
            ]
        )

        XCTAssertEqual(
            dictionary.entries,
            ["Codex", "Claude Code", "Café"]
        )
        XCTAssertEqual(dictionary.prompt, "Codex, Claude Code, Café")
    }

    func testBoundsSavedEntriesAndRecognitionPrompt() {
        let oversized = String(
            repeating: "A",
            count: InternalDictionary.maximumEntryCharacters + 20
        )
        let entries = [oversized]
            + (0..<(InternalDictionary.maximumEntries + 20)).map {
                "term\($0)-" + String(repeating: "x", count: 20)
            }
        let dictionary = InternalDictionary(entries: entries)

        XCTAssertLessThanOrEqual(
            dictionary.entries.count,
            InternalDictionary.maximumEntries
        )
        XCTAssertEqual(
            dictionary.entries.first?.count,
            InternalDictionary.maximumEntryCharacters
        )
        XCTAssertEqual(
            dictionary.prompt,
            dictionary.entries.joined(separator: ", ")
        )
        XCTAssertLessThanOrEqual(
            dictionary.prompt?.count ?? 0,
            InternalDictionary.maximumPromptCharacters
        )
    }

    func testPersistsStringArrayAndLoadsNormalizedValue() {
        let suiteName = "InternalDictionaryTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        InternalDictionary(entries: ["Codex", "Claude Code"]).persist(
            defaults: defaults
        )

        XCTAssertEqual(
            InternalDictionary.selected(defaults: defaults),
            InternalDictionary(entries: ["Codex", "Claude Code"])
        )
    }

    func testExistingDictionarySurvivesNewBinaryBootstrap() {
        let suiteName = "InternalDictionaryUpdateTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        InternalDictionary(entries: ["AGENTS.md", "projLab"]).persist(
            defaults: defaults
        )
        var replacementWasApplied = false

        FirstRunPreferenceBootstrap.applyIfNeeded(
            defaults: defaults,
            bundleIdentifier: suiteName,
            version: 2
        ) {
            replacementWasApplied = true
            InternalDictionary(entries: ["replacement"]).persist(
                defaults: defaults
            )
        }

        XCTAssertFalse(replacementWasApplied)
        XCTAssertEqual(
            InternalDictionary.selected(defaults: defaults).entries,
            ["AGENTS.md", "projLab"]
        )
    }

    func testAddsAndRemovesEntriesByNormalizedIdentity() {
        let dictionary = InternalDictionary(entries: ["Codex", "Café"])

        XCTAssertEqual(
            dictionary.adding(["Claude Code", "codex"]).entries,
            ["Codex", "Café", "Claude Code"]
        )
        XCTAssertEqual(
            dictionary.removing("CAFE").entries,
            ["Codex"]
        )
    }

    func testDraftParserHandlesDictatedListsAndPreservesPhrases() {
        let result = InternalDictionaryDraftParser.parse(
            "Add Codex, \"Claude, Code\", and research and development.",
            existingEntries: []
        )

        XCTAssertEqual(
            result.candidates,
            ["Codex", "Claude, Code", "research and development"]
        )
        XCTAssertTrue(result.duplicates.isEmpty)
        XCTAssertTrue(result.rejected.isEmpty)
    }

    func testDraftParserReportsDuplicatesAndInvalidCandidates() {
        let oversized = String(
            repeating: "x",
            count: InternalDictionary.maximumEntryCharacters + 1
        )
        let result = InternalDictionaryDraftParser.parse(
            "codex; \(oversized)",
            existingEntries: ["Codex"]
        )

        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.duplicates, ["codex"])
        XCTAssertEqual(
            result.rejected,
            [
                InternalDictionaryDraftRejection(
                    value: oversized,
                    reason: .tooLong
                )
            ]
        )
    }

    func testDraftParserReportsPromptCapacityWithoutMutatingExisting() {
        let existing = (0..<8).map {
            "term-\($0)-" + String(repeating: "x", count: 30)
        }
        let saved = InternalDictionary(entries: existing)
        let result = InternalDictionaryDraftParser.parse(
            "one more long candidate",
            existingEntries: saved.entries
        )

        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.rejected.first?.reason, .capacity)
        XCTAssertEqual(InternalDictionary(entries: existing), saved)
    }

    func testCombinesVocabularyWithPauseContextOnlyWhenPresent() {
        XCTAssertEqual(
            RecognitionPrompt.combined(
                dictionaryPrompt: "Codex, Claude Code",
                contextPrompt: "The previous phrase,"
            ),
            "Codex, Claude Code. The previous phrase,"
        )
        XCTAssertEqual(
            RecognitionPrompt.combined(
                dictionaryPrompt: " Codex ",
                contextPrompt: nil
            ),
            "Codex"
        )
        XCTAssertNil(
            RecognitionPrompt.combined(
                dictionaryPrompt: " ",
                contextPrompt: nil
            )
        )
    }
}
