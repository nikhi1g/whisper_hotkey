import Foundation
import XCTest
@testable import WhisperHotkeyCore

final class LexicallyInvariantFormatterTests: XCTestCase {
    private let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    private func words(_ text: String) -> [RecognizedWord] {
        text.split(separator: " ").enumerated().map { index, token in
            RecognizedWord(
                id: StableWordID(
                    sessionID: sessionID,
                    providerDecodeID: "format-test",
                    wordIndex: index
                ),
                text: String(token)
            )
        }
    }

    private func evidence(
        _ words: [RecognizedWord],
        _ pairs: [(Int, LexicalFormattingEvidence)]
    ) -> [StableWordID: LexicalFormattingEvidence] {
        Dictionary(uniqueKeysWithValues: pairs.map { (words[$0.0].id, $0.1) })
    }

    func testThinkingPauseDoesNotBecomePeriodInIncompleteClause() {
        let inputWords = words("I wanted to ask if we should go")
        let formatter = LexicallyInvariantFormatter()
        let result = formatter.format(
            words: inputWords,
            evidence: evidence(
                inputWords,
                [
                    (
                        3,
                        LexicalFormattingEvidence(
                            pauseAfterSeconds: 1.2,
                            semanticCompleteness: 0.30
                        )
                    ),
                ]
            )
        )

        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.formattedText, "I wanted to ask if we should go.")
        XCTAssertFalse(result.formattedText.contains("ask."))
        XCTAssertFalse(result.formattedText.contains("ask,"))
    }

    func testQuestionGetsQuestionMarkAndInitialCapitalization() {
        let inputWords = words("are you ready")
        let result = LexicallyInvariantFormatter().format(words: inputWords)

        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.formattedText, "Are you ready?")
        XCTAssertEqual(result.words.last?.punctuation, .question)
        XCTAssertTrue(
            LexicalInvariantGuard.areLexicallyInvariant(
                originalWords: inputWords,
                formattedWords: result.words
            )
        )
    }

    func testProperNamesAndAcronymsUseCaseLabelsWithoutLexicalReplacement() {
        let inputWords = words("alice works at NASA")
        let result = LexicallyInvariantFormatter().format(
            words: inputWords,
            evidence: evidence(
                inputWords,
                [
                    (0, LexicalFormattingEvidence(isProperNoun: true)),
                    (3, LexicalFormattingEvidence(isAcronym: true)),
                ]
            )
        )

        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.formattedText, "Alice works at NASA.")
        XCTAssertEqual(result.words[0].lexicalText, "Alice")
        XCTAssertEqual(result.words[3].lexicalText, "NASA")
        XCTAssertTrue(
            LexicalInvariantGuard.areLexicallyInvariant(
                originalWords: inputWords,
                formattedWords: result.words
            )
        )
    }

    func testLowSemanticCompletenessKeepsFragmentUnterminated() {
        let inputWords = words("draft notes")
        let result = LexicallyInvariantFormatter().format(
            words: inputWords,
            evidence: evidence(
                inputWords,
                [(1, LexicalFormattingEvidence(semanticCompleteness: 0.15))]
            )
        )

        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.formattedText, "Draft notes")
        XCTAssertEqual(result.words.last?.punctuation, LexicalFormattingPunctuation.none)
    }

    func testFinalCompleteStopIsAppliedOnlyAtFinalSession() {
        let inputWords = words("please send report")
        let complete = LexicallyInvariantFormatter().format(
            words: inputWords,
            completeness: .finalSession
        )
        let provisional = LexicallyInvariantFormatter().format(
            words: inputWords,
            completeness: .provisional
        )

        XCTAssertEqual(complete.formattedText, "Please send report.")
        XCTAssertEqual(provisional.formattedText, "Please send report")
    }

    func testMalformedLabelsFailClosedToUnformattedWords() {
        let inputWords = words("hello world")
        let formatter = LexicallyInvariantFormatter()
        let duplicate = LexicalFormattingLabel(wordID: inputWords[0].id, casing: .upper)
        let result = formatter.apply(
            [duplicate, duplicate],
            to: LexicalFormattingInput(words: inputWords)
        )

        XCTAssertFalse(result.accepted)
        XCTAssertTrue(result.didFailClosed)
        XCTAssertEqual(result.failure, .duplicateLabel(inputWords[0].id))
        XCTAssertEqual(result.formattedText, "hello world")
    }

    func testConflictingBoundaryAndNonFiniteConfidenceFailClosed() {
        let inputWords = words("hello world")
        let input = LexicalFormattingInput(words: inputWords)
        let formatter = LexicallyInvariantFormatter()
        let conflicting = [
            LexicalFormattingLabel(
                wordID: inputWords[0].id,
                punctuation: .period,
                boundary: .none
            ),
            LexicalFormattingLabel(wordID: inputWords[1].id, confidence: .nan),
        ]

        let result = formatter.apply(conflicting, to: input)
        XCTAssertFalse(result.accepted)
        XCTAssertEqual(result.failure, .inconsistentBoundary(inputWords[0].id))
        XCTAssertEqual(result.formattedText, "hello world")
    }

    func testPropertyStyleLabelsNeverMutateOrderedLexicalTokens() {
        let inputWords = words("alpha beta NASA gamma")
        let punctuation: [LexicalFormattingPunctuation] = [
            .none, .comma, .period, .question, .exclamation, .colon, .semicolon,
        ]
        let casing: [LexicalFormattingCase] = [
            .preserve, .sentenceInitial, .title, .lower, .upper,
        ]

        for offset in 0..<100 {
            let labels = inputWords.enumerated().map { index, word in
                LexicalFormattingLabel(
                    wordID: word.id,
                    punctuation: punctuation[(index + offset) % punctuation.count],
                    casing: casing[(index * 3 + offset) % casing.count]
                )
            }
            let result = LexicallyInvariantFormatter().apply(
                labels,
                to: LexicalFormattingInput(words: inputWords)
            )
            XCTAssertTrue(result.accepted, "offset \(offset) unexpectedly failed")
            XCTAssertTrue(
                LexicalInvariantGuard.areLexicallyInvariant(
                    originalWords: inputWords,
                    formattedWords: result.words
                )
            )
            XCTAssertTrue(
                LexicalInvariantGuard.areLexicallyInvariant(
                    original: inputWords.map(\.text).joined(separator: " "),
                    formatted: result.formattedText
                )
            )
        }
    }

    func testTruncatedInputDoesNotReceiveSentenceBoundary() {
        let inputWords = words("we should")
        let result = LexicallyInvariantFormatter().format(
            words: inputWords,
            evidence: evidence(
                inputWords,
                [(1, LexicalFormattingEvidence(isTruncated: true))]
            ),
            completeness: .truncated
        )

        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.formattedText, "We should")
        XCTAssertFalse(result.words.contains { $0.punctuation.isSentenceBoundary })
    }
}
