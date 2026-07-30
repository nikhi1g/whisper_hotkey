import XCTest
@testable import WhisperHotkeyCore

final class BackgroundPredecodeTests: XCTestCase {
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

    func testAccumulatorNormalizesAndResetsChunks() {
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
}
