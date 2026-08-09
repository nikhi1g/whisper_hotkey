import Foundation
import XCTest
@testable import WhisperHotkeyCore

final class BackgroundPredecodeTests: XCTestCase {
    private let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    func testRotationRequiresSpeechAndMinimumDuration() {
        XCTAssertFalse(
            BackgroundPredecodePolicy.shouldRotate(
                segmentDuration:
                    BackgroundPredecodePolicy.maximumSegmentDuration,
                containsSpeech: false,
                trailingSilence:
                    BackgroundPredecodePolicy.preferredBoundarySilence
            )
        )
        XCTAssertFalse(
            BackgroundPredecodePolicy.shouldRotate(
                segmentDuration:
                    BackgroundPredecodePolicy.minimumSegmentDuration - 0.01,
                containsSpeech: true,
                trailingSilence:
                    BackgroundPredecodePolicy.preferredBoundarySilence
            )
        )
    }

    func testRotationPrefersPauseButHasBoundedHardLimit() {
        XCTAssertTrue(
            BackgroundPredecodePolicy.shouldRotate(
                segmentDuration:
                    BackgroundPredecodePolicy.minimumSegmentDuration,
                containsSpeech: true,
                trailingSilence:
                    BackgroundPredecodePolicy.preferredBoundarySilence
            )
        )
        XCTAssertTrue(
            BackgroundPredecodePolicy.shouldRotate(
                segmentDuration:
                    BackgroundPredecodePolicy.maximumSegmentDuration,
                containsSpeech: true,
                trailingSilence: 0
            )
        )
    }

    func testLegacyAccumulatorNormalizesAndResetsChunks() {
        var accumulator = PredecodedTranscriptAccumulator()
        accumulator.append("  First phrase. \n")
        accumulator.append("")
        accumulator.append("Second phrase.")

        XCTAssertEqual(
            accumulator.transcript,
            "First phrase. Second phrase."
        )
        XCTAssertEqual(accumulator.chunks.count, 2)

        accumulator.reset()
        XCTAssertTrue(accumulator.chunks.isEmpty)
        XCTAssertEqual(accumulator.transcript, "")
    }

    func testTimedOverlapDropsDuplicateBoundaryWords() {
        var accumulator = PredecodedTranscriptAccumulator(
            mode: .deferred,
            sessionID: sessionID,
            generation: 7
        )

        _ = accumulator.append(
            timedWords: [
                TimedWord(text: "alpha", startSeconds: 0, endSeconds: 0.8),
                TimedWord(text: "beta", startSeconds: 0.8, endSeconds: 1.6),
            ],
            sessionID: sessionID,
            generation: 7,
            decodeID: "window-1"
        )
        let update = accumulator.append(
            timedWords: [
                TimedWord(text: "beta", startSeconds: 0.8, endSeconds: 1.6),
                TimedWord(text: "gamma", startSeconds: 1.6, endSeconds: 2.4),
            ],
            sessionID: sessionID,
            generation: 7,
            decodeID: "window-2"
        )

        XCTAssertEqual(update.transcript, "alpha beta gamma")
        XCTAssertEqual(update.revisableTail.map(\.text), ["alpha", "beta", "gamma"])
        XCTAssertEqual(Set(update.revisableTail.map(\.id)).count, 3)
    }

    func testTimedOverlapRevisesAWordInsteadOfKeepingTheDroppedWord() {
        var accumulator = PredecodedTranscriptAccumulator(
            mode: .deferred,
            sessionID: sessionID,
            generation: 1
        )

        _ = accumulator.append(
            timedWords: [
                TimedWord(text: "hello", startSeconds: 0, endSeconds: 0.6),
                TimedWord(text: "world", startSeconds: 0.6, endSeconds: 1.3),
            ],
            sessionID: sessionID,
            generation: 1,
            decodeID: "first"
        )
        let update = accumulator.append(
            timedWords: [
                TimedWord(text: "hello", startSeconds: 0, endSeconds: 0.6),
                TimedWord(text: "there", startSeconds: 0.6, endSeconds: 1.3),
            ],
            sessionID: sessionID,
            generation: 1,
            decodeID: "revision"
        )

        XCTAssertEqual(update.transcript, "hello there")
        XCTAssertFalse(update.transcript.contains("world"))
    }

    func testStablePrefixLeavesOnlyARevisableTail() {
        var accumulator = PredecodedTranscriptAccumulator(
            mode: .decodeWhileSpeaking,
            sessionID: sessionID,
            generation: 4
        )
        let first = [
            TimedWord(text: "one", startSeconds: 0, endSeconds: 0.5),
            TimedWord(text: "two", startSeconds: 0.5, endSeconds: 1),
            TimedWord(text: "three", startSeconds: 1, endSeconds: 1.5),
        ]
        _ = accumulator.append(
            timedWords: first,
            sessionID: sessionID,
            generation: 4,
            decodeID: "stable-1"
        )
        let update = accumulator.append(
            timedWords: first + [
                TimedWord(text: "four", startSeconds: 1.5, endSeconds: 2),
            ],
            sessionID: sessionID,
            generation: 4,
            decodeID: "stable-2"
        )

        XCTAssertEqual(update.stablePrefix.map(\.text), ["one", "two", "three"])
        XCTAssertEqual(update.revisableTail.map(\.text), ["four"])
        XCTAssertEqual(update.transcript, "one two three four")
        XCTAssertEqual(update.formattingBoundary, .stablePrefix)
        XCTAssertEqual(update.pasteReadiness, .notReady)
    }

    func testTruncatedTailRequiresFallbackAndFallbackReplacesIt() {
        var accumulator = PredecodedTranscriptAccumulator(
            mode: .decodeWhileSpeaking,
            sessionID: sessionID,
            generation: 11
        )
        _ = accumulator.append(
            timedWords: [
                TimedWord(text: "a", startSeconds: 0, endSeconds: 0.5),
                TimedWord(text: "trunc", startSeconds: 0.5, endSeconds: 1),
            ],
            sessionID: sessionID,
            generation: 11,
            completeness: .truncated,
            decodeID: "tail"
        )
        XCTAssertEqual(accumulator.semanticEndpoint, .truncated)

        let fallback = result(
            text: "a complete sentence",
            words: [
                word("a", start: 0, end: 0.5, decodeID: "fallback", index: 0),
                word("complete", start: 0.5, end: 1, decodeID: "fallback", index: 1),
                word("sentence", start: 1, end: 1.6, decodeID: "fallback", index: 2),
            ],
            generation: 11,
            completeness: .finalSession,
            requestID: "fallback"
        )
        let final = accumulator.finalize(fallback: fallback)

        XCTAssertEqual(final.source, .fallback)
        XCTAssertTrue(final.fallbackUsed)
        XCTAssertEqual(final.transcript, "a complete sentence")
        XCTAssertTrue(final.revisableTail.isEmpty)
        XCTAssertEqual(final.pasteReadiness, .finalReady)
    }

    func testFinalTailWinsOverTheAccumulatedTail() {
        var accumulator = PredecodedTranscriptAccumulator(
            mode: .deferred,
            sessionID: sessionID,
            generation: 2
        )
        _ = accumulator.append(
            timedWords: [
                TimedWord(text: "partial", startSeconds: 0, endSeconds: 0.5),
            ],
            sessionID: sessionID,
            generation: 2,
            decodeID: "background"
        )
        let finalTail = result(
            text: "partial final",
            words: [
                word("partial", start: 0, end: 0.5, decodeID: "final", index: 0),
                word("final", start: 0.5, end: 1, decodeID: "final", index: 1),
            ],
            generation: 2,
            completeness: .finalSession,
            requestID: "final"
        )
        let final = accumulator.finalize(finalTail: finalTail)

        XCTAssertEqual(final.source, .finalTail)
        XCTAssertTrue(final.finalTailAccepted)
        XCTAssertFalse(final.fallbackUsed)
        XCTAssertEqual(final.transcript, "partial final")
        XCTAssertEqual(final.pasteReadiness, .finalReady)
    }

    func testCancellationAndResetRejectStaleResults() {
        var accumulator = PredecodedTranscriptAccumulator(
            mode: .deferred,
            sessionID: sessionID,
            generation: 3
        )
        let old = result(
            text: "old",
            words: [word("old", start: 0, end: 0.5, decodeID: "old", index: 0)],
            generation: 3,
            completeness: .provisional,
            requestID: "old"
        )
        _ = accumulator.append(old)
        accumulator.cancel()
        let cancelled = accumulator.append(old)
        XCTAssertTrue(cancelled.ignored)
        XCTAssertTrue(cancelled.cancelled)
        XCTAssertEqual(cancelled.transcript, "")
        XCTAssertEqual(cancelled.pasteReadiness, .cancelled)

        accumulator.reset()
        let staleAfterReset = accumulator.append(old)
        XCTAssertTrue(staleAfterReset.ignored)
        XCTAssertEqual(staleAfterReset.transcript, "")

        let fresh = result(
            text: "fresh",
            words: [word("fresh", start: 0, end: 0.5, decodeID: "fresh", index: 0)],
            generation: 20,
            completeness: .provisional,
            requestID: "fresh"
        )
        let accepted = accumulator.append(fresh)
        XCTAssertTrue(accepted.accepted)
        XCTAssertEqual(accepted.transcript, "fresh")
    }

    func testOutOfOrderWindowsAreSortedByTiming() {
        var accumulator = PredecodedTranscriptAccumulator(
            mode: .deferred,
            sessionID: sessionID,
            generation: 8
        )
        _ = accumulator.append(
            timedWords: [
                TimedWord(text: "third", startSeconds: 2, endSeconds: 2.5),
                TimedWord(text: "fourth", startSeconds: 2.5, endSeconds: 3),
            ],
            sessionID: sessionID,
            generation: 8,
            decodeID: "later"
        )
        let update = accumulator.append(
            timedWords: [
                TimedWord(text: "first", startSeconds: 0, endSeconds: 0.5),
                TimedWord(text: "second", startSeconds: 0.5, endSeconds: 1),
            ],
            sessionID: sessionID,
            generation: 8,
            decodeID: "earlier"
        )

        XCTAssertEqual(update.transcript, "first second third fourth")
        XCTAssertEqual(update.revisableTail.map(\.text), ["first", "second", "third", "fourth"])
    }

    func testTailAndCandidateQueuesRemainBounded() {
        var accumulator = PredecodedTranscriptAccumulator(
            mode: .deferred,
            sessionID: sessionID,
            generation: 9,
            maximumTailWords: 4
        )
        for index in 0..<40 {
            _ = accumulator.append(
                timedWords: [
                    TimedWord(
                        text: "word\(index)",
                        startSeconds: Double(index),
                        endSeconds: Double(index) + 0.5
                    ),
                ],
                sessionID: sessionID,
                generation: 9,
                decodeID: "window-\(index)"
            )
        }

        XCTAssertLessThanOrEqual(accumulator.activeTailWordCount, 4)
        XCTAssertTrue(accumulator.isMemoryBounded)
        XCTAssertTrue(accumulator.fallbackRequired)
    }

    func testPauseModeCommitsWholeSentenceCandidatesWithoutPasting() {
        var accumulator = PredecodedTranscriptAccumulator(
            mode: .pauseMode,
            sessionID: sessionID,
            generation: 10
        )
        let update = accumulator.append(
            timedWords: [
                TimedWord(text: "whole", startSeconds: 0, endSeconds: 0.5),
                TimedWord(text: "sentence", startSeconds: 0.5, endSeconds: 1.2),
            ],
            text: "whole sentence",
            sessionID: sessionID,
            generation: 10,
            completeness: .completeSentence,
            decodeID: "sentence-1"
        )

        XCTAssertEqual(update.sentenceCandidates.count, 1)
        XCTAssertEqual(update.sentenceCandidates[0].text, "whole sentence")
        XCTAssertEqual(update.sentenceCandidates[0].pasteReadiness, .sentenceCandidate)
        XCTAssertEqual(update.stablePrefix.map(\.text), ["whole", "sentence"])
        XCTAssertTrue(update.revisableTail.isEmpty)
        XCTAssertEqual(update.pasteReadiness, .sentenceCandidate)
        XCTAssertFalse(update.pasteReadiness == .finalReady)

        let drained = accumulator.takePauseModeSentenceCandidates()
        XCTAssertEqual(drained, update.sentenceCandidates)
        XCTAssertTrue(accumulator.pendingSentenceCandidates.isEmpty)
    }

    func testDeferredModeSeparatesDecodeAndPasteReadiness() {
        var accumulator = PredecodedTranscriptAccumulator(
            mode: .deferred,
            sessionID: sessionID,
            generation: 12
        )
        let update = accumulator.append(
            timedWords: [
                TimedWord(text: "pause", startSeconds: 0, endSeconds: 0.5),
            ],
            sessionID: sessionID,
            generation: 12,
            completeness: .completeSentence,
            decodeID: "pause-only"
        )

        XCTAssertEqual(update.decodeBoundary, .completeSentence)
        XCTAssertEqual(update.semanticEndpoint, .accepted)
        XCTAssertEqual(update.formattingBoundary, .revisableTail)
        XCTAssertEqual(update.pasteReadiness, .notReady)
        XCTAssertTrue(update.sentenceCandidates.isEmpty)

        let final = accumulator.finalize()
        XCTAssertEqual(final.source, .accumulated)
        XCTAssertEqual(final.pasteReadiness, .finalReady)
        XCTAssertEqual(final.transcript, "pause")
    }

    private func word(
        _ text: String,
        start: Double,
        end: Double,
        decodeID: String,
        index: Int
    ) -> RecognizedWord {
        RecognizedWord(
            id: StableWordID(
                sessionID: sessionID,
                providerDecodeID: decodeID,
                wordIndex: index
            ),
            text: text,
            startSeconds: start,
            endSeconds: end
        )
    }

    private func result(
        text: String,
        words: [RecognizedWord],
        generation: UInt64,
        completeness: DecodeCompleteness,
        requestID: String
    ) -> RecognitionResult {
        RecognitionResult(
            sessionID: sessionID,
            generation: generation,
            engine: .whisperTurbo,
            pass: .provisional,
            text: text,
            words: words,
            completeness: completeness,
            passMetadata: RecognitionPassMetadata(requestID: requestID)
        )
    }
}
