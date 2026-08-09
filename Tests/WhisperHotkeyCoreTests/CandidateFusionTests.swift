import Foundation
import XCTest
@testable import WhisperHotkeyCore

final class CandidateFusionTests: XCTestCase {
    private let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    func testPairwiseRepairChangesOnlyAuthorizedWordAndRetainsProvenance() {
        let source = [
            makeWord("teh", index: 0, start: 0, end: 0.4, posterior: 0.20),
            makeWord("note", index: 1, start: 0.5, end: 0.9, posterior: 0.95),
        ]
        let candidate = [
            makeWord("the", index: 0, provider: "verifier", start: 0, end: 0.4, posterior: 0.95),
            makeWord("note", index: 1, provider: "verifier", start: 0.5, end: 0.9, posterior: 0.95),
        ]

        let result = CandidateFusion.pairwise(
            primary: source,
            candidates: [FusionCandidate(words: candidate)]
        )

        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.reason, .accepted)
        XCTAssertEqual(result.words.map(\.text), ["the", "note"])
        XCTAssertEqual(result.words[1].id, source[1].id)
        XCTAssertEqual(result.words[0].id, candidate[0].id)
        XCTAssertEqual(result.words[0].provenance.kind, .replacement)
        XCTAssertEqual(result.words[0].provenance.sourceWordIDs, [source[0].id])
        XCTAssertEqual(result.wordsChanged, 1)
    }

    func testProtectedTermsAndLockedWordsRefuseReplacement() {
        let dictionarySource = [makeWord("Acme", index: 0, start: 0, end: 0.4, posterior: 0.10)]
        let dictionaryCandidate = [makeWord("Acm", index: 0, provider: "verifier", start: 0, end: 0.4, posterior: 0.99)]
        let dictionaryResult = CandidateFusion.pairwise(
            primary: dictionarySource,
            candidates: [FusionCandidate(words: dictionaryCandidate)],
            configuration: CandidateFusionConfiguration(protectedDictionaryTerms: ["Acme"])
        )
        XCTAssertFalse(dictionaryResult.accepted)
        XCTAssertEqual(dictionaryResult.reason, .protectedDictionaryTerm)

        let lockedSource = [makeWord("teh", index: 0, start: 0, end: 0.4, posterior: 0.10, lockState: .locked)]
        let lockedCandidate = [makeWord("the", index: 0, provider: "verifier", start: 0, end: 0.4, posterior: 0.99)]
        let lockedResult = CandidateFusion.pairwise(
            primary: lockedSource,
            candidates: [FusionCandidate(words: lockedCandidate)]
        )
        XCTAssertFalse(lockedResult.accepted)
        XCTAssertEqual(lockedResult.reason, .lockedAnchor)
        XCTAssertEqual(lockedResult.words, lockedSource)
    }

    func testNumbersIdentifiersNegationAndDestructiveCommandsRefuseReplacement() {
        let cases: [(String, String, CandidateFusionReason)] = [
            ("42", "43", .numberChange),
            ("ABC123", "ABC124", .identifierChange),
            ("NASA", "NADA", .identifierChange),
            ("not", "now", .negationChange),
            ("delete", "keep", .destructiveCommandChange),
        ]

        for (offset, item) in cases.enumerated() {
            let source = [makeWord(item.0, index: offset, start: 0, end: 0.4, posterior: 0.10)]
            let candidate = [makeWord(item.1, index: offset, provider: "verifier", start: 0, end: 0.4, posterior: 0.99)]
            let result = CandidateFusion.pairwise(
                primary: source,
                candidates: [FusionCandidate(words: candidate)]
            )
            XCTAssertFalse(result.accepted, item.0)
            XCTAssertEqual(result.reason, item.2, item.0)
        }
    }

    func testLowTimeOverlapAndMissingEvidenceFailClosed() {
        let source = [makeWord("teh", index: 0, start: 0, end: 0.4, posterior: 0.10)]
        let lowOverlapCandidate = [makeWord("the", index: 0, provider: "verifier", start: 0.3, end: 0.7, posterior: 0.99)]
        let lowOverlap = CandidateFusion.pairwise(
            primary: source,
            candidates: [FusionCandidate(words: lowOverlapCandidate)]
        )
        XCTAssertFalse(lowOverlap.accepted)
        XCTAssertEqual(lowOverlap.reason, .lowTimeOverlap)

        let noEvidenceSource = [makeWord("teh", index: 0, start: 0, end: 0.4)]
        let noEvidenceCandidate = [makeWord("the", index: 0, provider: "verifier", start: 0, end: 0.4)]
        let noEvidence = CandidateFusion.pairwise(
            primary: noEvidenceSource,
            candidates: [FusionCandidate(words: noEvidenceCandidate)]
        )
        XCTAssertFalse(noEvidence.accepted)
        XCTAssertEqual(noEvidence.reason, .insufficientEvidence)
    }

    func testAuthorizedWordIDsAndTimeRangeContainRepairs() {
        let source = [
            makeWord("teh", index: 0, start: 0, end: 0.4, posterior: 0.10),
            makeWord("note", index: 1, start: 1, end: 1.4, posterior: 0.95),
        ]
        let candidate = [
            makeWord("the", index: 0, provider: "verifier", start: 0, end: 0.4, posterior: 0.99),
            makeWord("note", index: 1, provider: "verifier", start: 1, end: 1.4, posterior: 0.95),
        ]
        let outsideID = CandidateFusion.pairwise(
            primary: source,
            candidates: [FusionCandidate(words: candidate)],
            configuration: CandidateFusionConfiguration(authorizedWordIDs: [source[1].id])
        )
        XCTAssertFalse(outsideID.accepted)
        XCTAssertEqual(outsideID.reason, .outsideAuthorizedSpan)

        let outsideTime = CandidateFusion.pairwise(
            primary: source,
            candidates: [FusionCandidate(words: candidate)],
            configuration: CandidateFusionConfiguration(
                authorizedTimeRange: 1...1.4
            )
        )
        XCTAssertFalse(outsideTime.accepted)
        XCTAssertEqual(outsideTime.reason, .outsideAuthorizedSpan)
    }

    func testWeightedROVERAndMBRRemainBoundedAndUseTypedWords() {
        let source = [makeWord("teh", index: 0, start: 0, end: 0.4, posterior: 0.10)]
        let first = [makeWord("the", index: 0, provider: "verifier-a", start: 0, end: 0.4, posterior: 0.96)]
        let second = [makeWord("the", index: 0, provider: "verifier-b", start: 0, end: 0.4, posterior: 0.94)]

        let rover = CandidateFusion.weightedROVER(
            primary: source,
            candidates: [
                FusionCandidate(words: first),
                FusionCandidate(words: second),
            ],
            configuration: CandidateFusionConfiguration(strategy: .weightedROVER)
        )
        XCTAssertTrue(rover.accepted)
        XCTAssertEqual(rover.words.first?.text, "the")
        XCTAssertEqual(rover.words.first?.provenance.kind, .replacement)

        let medoid = CandidateFusion.mbrMedoid(
            primary: source,
            candidates: [
                FusionCandidate(words: first, posterior: 0.85),
                FusionCandidate(words: second, posterior: 0.15),
            ],
            configuration: CandidateFusionConfiguration(strategy: .mbrMedoid)
        )
        XCTAssertTrue(medoid.accepted)
        XCTAssertEqual(medoid.words.first?.text, "the")
        XCTAssertLessThanOrEqual(medoid.alignment?.operations.count ?? .max, 2)
    }

    func testCandidateAndWordBoundsFailClosed() {
        let source = [makeWord("teh", index: 0, start: 0, end: 0.4, posterior: 0.10)]
        let candidate = FusionCandidate(
            words: [makeWord("the", index: 0, provider: "verifier", start: 0, end: 0.4, posterior: 0.99)]
        )
        let candidates = Array(repeating: candidate, count: CandidateFusionConfiguration.hardMaximumCandidates + 1)
        let result = CandidateFusion.pairwise(primary: source, candidates: candidates)
        XCTAssertFalse(result.accepted)
        XCTAssertEqual(result.reason, .candidateLimitExceeded)
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
