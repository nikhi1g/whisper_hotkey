import Foundation
import XCTest
@testable import WhisperHotkeyCore

final class WordAlignmentTests: XCTestCase {
    private let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    func testTimestampAwareAlignmentReturnsTypedOperationsAndScoreTerms() throws {
        let source = [
            makeWord("alpha", index: 0, start: 0, end: 0.4, posterior: 0.95),
            makeWord("beta", index: 1, start: 0.5, end: 0.9, posterior: 0.30),
        ]
        let candidate = [
            makeWord("alpha", index: 0, provider: "verifier", start: 0.02, end: 0.42, posterior: 0.96),
            makeWord("theta", index: 1, provider: "verifier", start: 0.51, end: 0.91, posterior: 0.92),
        ]

        let alignment = try WordAlignment.align(source: source, candidate: candidate)

        XCTAssertEqual(alignment.operations.count, 2)
        XCTAssertEqual(alignment.operations[0].kind, .match)
        XCTAssertEqual(alignment.operations[1].kind, .substitution)
        XCTAssertEqual(alignment.operations[1].sourceWordID, source[1].id)
        XCTAssertEqual(alignment.operations[1].candidateWordID, candidate[1].id)
        XCTAssertEqual(alignment.operations[1].timeOverlap ?? -1, 0.39 / 0.41, accuracy: 0.000_001)
        XCTAssertGreaterThan(alignment.operations[1].score.lexicalDistance, 0)
        XCTAssertLessThanOrEqual(alignment.operations[1].score.lexicalDistance, 1)
        XCTAssertNotNil(alignment.operations[1].score.confidencePenalty)
        XCTAssertGreaterThan(alignment.operations[1].score.total, 0)
        XCTAssertEqual(alignment.sourceWordIDs, source.map(\.id))
        XCTAssertEqual(alignment.candidateWordIDs, candidate.map(\.id))
    }

    func testMissingConfidenceIsRepresentedAsMissingInDecomposition() throws {
        let source = [makeWord("quiet", index: 0, start: 0, end: 0.4)]
        let candidate = [makeWord("quite", index: 0, provider: "verifier", start: 0, end: 0.4)]

        let alignment = try WordAlignment.align(source: source, candidate: candidate)

        XCTAssertEqual(alignment.operations[0].kind, .substitution)
        XCTAssertNil(alignment.operations[0].score.confidencePenalty)
    }

    func testLockedAnchorGetsAHighSubstitutionAndDeletionPenalty() throws {
        let source = [
            makeWord(
                "anchor",
                index: 0,
                start: 0,
                end: 0.4,
                posterior: 0.99,
                lockState: .locked
            ),
        ]
        let candidate = [
            makeWord("changed", index: 0, provider: "verifier", start: 0, end: 0.4, posterior: 0.99),
        ]

        let alignment = try WordAlignment.align(source: source, candidate: candidate)

        XCTAssertTrue(alignment.operations.contains { operation in
            operation.kind == .substitution || operation.kind == .deletion
        })
        XCTAssertTrue(alignment.operations.contains { operation in
            operation.score.anchorPenalty >= WordAlignmentConfiguration.default.lockedAnchorPenalty
        })
    }

    func testAlignmentRejectsSpansBeyondExplicitBounds() {
        let source = (0..<3).map { makeWord("word\($0)", index: $0, start: Double($0), end: Double($0) + 0.2) }
        let candidate = source
        let configuration = WordAlignmentConfiguration(
            maximumSourceWords: 2,
            maximumCandidateWords: 2,
            maximumCells: 4
        )

        XCTAssertThrowsError(
            try WordAlignment.align(
                source: source,
                candidate: candidate,
                configuration: configuration
            )
        ) { error in
            XCTAssertEqual(
                error as? WordAlignmentError,
                .sourceWordLimitExceeded(actual: 3, maximum: 2)
            )
        }
    }

    private func makeWord(
        _ text: String,
        index: Int,
        provider: String = "primary",
        start: Double? = nil,
        end: Double? = nil,
        posterior: Double? = nil,
        lockState: WordLockState = .unlocked
    ) -> RecognizedWord {
        RecognizedWord(
            id: StableWordID(
                sessionID: sessionID,
                providerDecodeID: provider,
                wordIndex: index
            ),
            text: text,
            startSeconds: start,
            endSeconds: end,
            rawEvidence: posterior.map {
                WordEvidence(posterior: $0, availability: .posterior)
            } ?? .unavailable,
            lockState: lockState
        )
    }
}
