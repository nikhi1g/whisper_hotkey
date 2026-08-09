import Foundation
import XCTest
@testable import WhisperHotkeyASR
import WhisperHotkeyCore

final class UncertainSpanPlannerTests: XCTestCase {
    private let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    func testMergesUncertainWordsPadsAndAuthorizesExactPrimaryIDs() {
        let words = [
            makeWord("alpha", index: 0, start: 0.10, end: 0.40),
            makeWord("bravo", index: 1, start: 0.60, end: 0.90),
            makeWord("charlie", index: 2, start: 1.20, end: 1.50),
        ]
        let configuration = UncertainSpanPlannerConfiguration(
            threshold: .uncalibrated(0.5),
            leftPaddingSeconds: 0.2,
            rightPaddingSeconds: 0.2,
            maximumVerifierAudioRatio: 1,
            maximumSpanCount: 4,
            adjustToWordBoundaries: false,
            adjustToVADBoundaries: false
        )

        let plan = UncertainSpanPlanner.plan(
            words: words,
            calibratedErrorProbabilities: [0.1, 0.9, 0.8],
            sessionDurationSeconds: 2,
            configuration: configuration
        )

        XCTAssertEqual(plan.spans.count, 1)
        let span = try! XCTUnwrap(plan.spans.first)
        XCTAssertGreaterThanOrEqual(span.startSeconds, 0)
        XCTAssertEqual(span.startSeconds, 0.40, accuracy: 0.000_001)
        XCTAssertEqual(span.endSeconds, 1.70, accuracy: 0.000_001)
        XCTAssertEqual(span.authorizedWordIDs, Set([words[1].id, words[2].id]))
        XCTAssertEqual(
            span.fusionConfiguration.authorizedWordIDs,
            span.authorizedWordIDs
        )
        XCTAssertEqual(
            span.fusionConfiguration.authorizedTimeRange,
            span.startSeconds...span.endSeconds
        )
    }

    func testDeletionGapCreatesBoundedInsertionAuthorization() {
        let words = [
            makeWord("we", index: 0, start: 0.10, end: 0.35),
            makeWord("leave", index: 1, start: 0.90, end: 1.20),
        ]
        let gap = DeletionGapEvidence(
            startSeconds: 0.40,
            endSeconds: 0.80,
            errorProbability: 0.95,
            leftWordID: words[0].id,
            rightWordID: words[1].id
        )
        let plan = UncertainSpanPlanner.plan(
            words: words,
            deletionGaps: [gap],
            sessionDurationSeconds: 2,
            configuration: configuration(maximumVerifierAudioRatio: 1)
        )

        let span = try! XCTUnwrap(plan.spans.first)
        XCTAssertEqual(span.trigger, .deletionGap)
        XCTAssertTrue(span.authorizedWordIDs.isEmpty)
        XCTAssertTrue(
            span.fusionConfiguration.authorizedTimeRange?.contains(0.6) == true
        )
        XCTAssertLessThanOrEqual(span.durationSeconds, 8)
        XCTAssertLessThanOrEqual(plan.totalVerifierAudioRatio, 1)
    }

    func testBudgetRanksRiskAndPreservesUnselectedMetadata() {
        let words = [
            makeWord("low", index: 0, start: 0.10, end: 0.30),
            makeWord("high", index: 1, start: 4.00, end: 4.20),
        ]
        let plan = UncertainSpanPlanner.plan(
            words: words,
            calibratedErrorProbabilities: [0.60, 0.99],
            sessionDurationSeconds: 8,
            configuration: UncertainSpanPlannerConfiguration(
                threshold: .uncalibrated(0.5),
                minimumRepairSpanDurationSeconds: 0.8,
                leftPaddingSeconds: 0,
                rightPaddingSeconds: 0,
                maximumVerifierAudioRatio: 0.1,
                maximumSpanCount: 2,
                adjustToWordBoundaries: false,
                adjustToVADBoundaries: false
            )
        )

        XCTAssertEqual(plan.spans.count, 1)
        XCTAssertEqual(plan.spans[0].authorizedWordIDs, Set([words[1].id]))
        XCTAssertEqual(plan.unselectedSpanRisks.count, 1)
        XCTAssertEqual(plan.unselectedSpanRisks[0].authorizedWordIDs, Set([words[0].id]))
        XCTAssertTrue(plan.issues.contains(.verifierAudioBudgetExceeded))
        XCTAssertEqual(
            plan.wordRisks.first(where: { $0.wordID == words[0].id })?.selected,
            false
        )
    }

    func testCatastrophicEvidenceOnlyRequestsBoundedSentenceRegion() {
        let words = [
            makeWord("one", index: 0, start: 0.1, end: 0.4),
            makeWord("two", index: 1, start: 10.0, end: 10.3),
        ]
        let plan = UncertainSpanPlanner.plan(
            words: words,
            catastrophicEvidence: CatastrophicEvidence(
                severeRepetition: true,
                sentenceRegion: 0...20
            ),
            sessionDurationSeconds: 60,
            configuration: UncertainSpanPlannerConfiguration(
                leftPaddingSeconds: 0,
                rightPaddingSeconds: 0,
                maximumVerifierAudioRatio: 1,
                maximumCatastrophicSpanDurationSeconds: 5
            )
        )

        XCTAssertEqual(plan.status, .catastrophicFallback)
        XCTAssertEqual(plan.spans.count, 1)
        let span = try! XCTUnwrap(plan.spans.first)
        XCTAssertEqual(span.trigger, .catastrophicFallback)
        XCTAssertLessThanOrEqual(span.durationSeconds, 5)
        XCTAssertLessThan(span.durationSeconds, 60)
        XCTAssertNotNil(plan.fallbackRequest)
        XCTAssertEqual(
            plan.fallbackRequest?.fusionConfiguration.authorizedTimeRange,
            span.authorizedTimeRange
        )
    }

    func testInvalidTimingAndProbabilityFailClosedWithoutCrash() {
        let words = [
            RecognizedWord(
                id: StableWordID(
                    sessionID: sessionID,
                    providerDecodeID: "primary",
                    wordIndex: 0
                ),
                text: "bad"
            ),
        ]
        let invalidTiming = UncertainSpanPlanner.plan(
            words: words,
            calibratedErrorProbabilities: [0.9],
            sessionDurationSeconds: 2
        )
        XCTAssertTrue(invalidTiming.isFailClosed)
        XCTAssertEqual(invalidTiming.failure, .missingWordTiming)
        XCTAssertTrue(invalidTiming.spans.isEmpty)

        let valid = [makeWord("ok", index: 0, start: 0.1, end: 0.4)]
        let invalidProbability = UncertainSpanPlanner.plan(
            words: valid,
            calibratedErrorProbabilities: [.infinity],
            sessionDurationSeconds: 2
        )
        XCTAssertTrue(invalidProbability.isFailClosed)
        XCTAssertEqual(invalidProbability.failure, .invalidWordProbability)
    }

    func testPlannerRejectsConfigurationBoundsAndInvalidVADRangeSafely() {
        let words = [makeWord("bounded", index: 0, start: 0.1, end: 0.4)]
        let hardMaximum = UncertainSpanPlannerConfiguration
            .hardMaximumSpanDurationSeconds

        let overNormalMaximum = UncertainSpanPlannerConfiguration(
            maximumRepairSpanDurationSeconds: hardMaximum + 1
        )
        let normalPlan = UncertainSpanPlanner.plan(
            words: words,
            sessionDurationSeconds: 2,
            configuration: overNormalMaximum
        )
        XCTAssertTrue(normalPlan.isFailClosed)
        XCTAssertEqual(normalPlan.failure, .invalidConfiguration)

        let overCatastrophicMaximum = UncertainSpanPlannerConfiguration(
            maximumCatastrophicSpanDurationSeconds: hardMaximum + 1
        )
        let catastrophicPlan = UncertainSpanPlanner.plan(
            words: words,
            sessionDurationSeconds: 2,
            configuration: overCatastrophicMaximum
        )
        XCTAssertTrue(catastrophicPlan.isFailClosed)
        XCTAssertEqual(catastrophicPlan.failure, .invalidConfiguration)

        let minimumExceedsMaximum = UncertainSpanPlannerConfiguration(
            minimumRepairSpanDurationSeconds: 3,
            maximumRepairSpanDurationSeconds: 2
        )
        let minimumPlan = UncertainSpanPlanner.plan(
            words: words,
            sessionDurationSeconds: 2,
            configuration: minimumExceedsMaximum
        )
        XCTAssertTrue(minimumPlan.isFailClosed)
        XCTAssertEqual(minimumPlan.failure, .invalidConfiguration)

        let malformedVAD = UncertainSpanVADRegion(
            startSeconds: 2,
            endSeconds: 1
        )
        XCTAssertNil(malformedVAD.range)
    }

    func testVADAndContextCapsRemainBounded() {
        let words = (0..<4).map { index in
            makeWord(
                String(repeating: "x", count: 30),
                index: index,
                start: Double(index) * 0.4 + 0.1,
                end: Double(index) * 0.4 + 0.3
            )
        }
        let plan = UncertainSpanPlanner.plan(
            words: words,
            calibratedErrorProbabilities: [0.9, 0.9, 0.9, 0.9],
            sessionDurationSeconds: 3,
            vadRegions: [
                UncertainSpanVADRegion(startSeconds: 0, endSeconds: 2.5),
            ],
            configuration: UncertainSpanPlannerConfiguration(
                threshold: .uncalibrated(0.5),
                leftPaddingSeconds: 0,
                rightPaddingSeconds: 0,
                maximumVerifierAudioRatio: 1,
                maximumSpanCount: 2,
                maximumWordsPerSpan: 2,
                maximumContextCharacters: 10,
                adjustToWordBoundaries: false,
                adjustToVADBoundaries: true
            )
        )

        XCTAssertFalse(plan.spans.isEmpty)
        XCTAssertTrue(plan.spans.allSatisfy { $0.authorizedWordIDs.count <= 2 })
        XCTAssertTrue(plan.spans.allSatisfy { $0.contextText.count <= 10 })
        XCTAssertTrue(plan.spans.allSatisfy { $0.durationSeconds <= 8 })
        XCTAssertLessThanOrEqual(plan.totalVerifierAudioRatio, 1)
    }

    private func configuration(
        maximumVerifierAudioRatio: Double
    ) -> UncertainSpanPlannerConfiguration {
        UncertainSpanPlannerConfiguration(
            maximumVerifierAudioRatio: maximumVerifierAudioRatio,
            adjustToWordBoundaries: false,
            adjustToVADBoundaries: false
        )
    }

    private func makeWord(
        _ text: String,
        index: Int,
        start: Double,
        end: Double
    ) -> RecognizedWord {
        RecognizedWord(
            id: StableWordID(
                sessionID: sessionID,
                providerDecodeID: "primary",
                wordIndex: index
            ),
            text: text,
            startSeconds: start,
            endSeconds: end
        )
    }
}
