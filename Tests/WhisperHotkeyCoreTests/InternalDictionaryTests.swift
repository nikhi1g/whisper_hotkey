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
