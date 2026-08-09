import Foundation
import XCTest
@testable import WhisperHotkeyCore

final class RecognitionResultTests: XCTestCase {
    func testHypothesisAdapterPreservesTextAndCreatesDeterministicWordIDs() {
        let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let decodeID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let hypothesis = RecognitionHypothesis(
            id: decodeID,
            engine: .whisperTurbo,
            pass: .primaryFullSession,
            window: RecognitionWindow(startSample: 0, endSample: 32_000),
            text: "Hello, world",
            words: [
                TimedWord(text: "Hello", startSeconds: 0.1, endSeconds: 0.4, confidence: 0.93),
                TimedWord(text: "world", startSeconds: 0.5, endSeconds: 0.9, confidence: 0.88),
            ],
            segments: [
                TimedSegment(
                    startSeconds: 0,
                    endSeconds: 1,
                    text: "Hello, world"
                ),
            ],
            averageLogProbability: -0.12,
            noSpeechProbability: 0.01,
            weakTokenFraction: 0.05,
            modelID: "turbo-q5",
            engineVersion: "test"
        )

        let first = hypothesis.asRecognitionResult(sessionID: sessionID)
        let second = hypothesis.asRecognitionResult(sessionID: sessionID)

        XCTAssertEqual(first.renderedText, hypothesis.text)
        XCTAssertEqual(first.words, second.words)
        XCTAssertEqual(
            first.words.map(\.id),
            [
                StableWordID(
                    sessionID: sessionID,
                    providerDecodeID: decodeID.uuidString,
                    wordIndex: 0
                ),
                StableWordID(
                    sessionID: sessionID,
                    providerDecodeID: decodeID.uuidString,
                    wordIndex: 1
                ),
            ]
        )
        XCTAssertEqual(first.segments.first?.wordIDs, first.words.map(\.id))
        XCTAssertEqual(first.utteranceEvidence.noSpeechProbability, 0.01)
        XCTAssertEqual(first.model.identifier, "turbo-q5")
    }

    func testProtocolV2RoundTripsRichResultAndUsesSnakeCase() throws {
        let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let wordID = StableWordID(
            sessionID: sessionID,
            providerDecodeID: "decode-1",
            wordIndex: 0
        )
        let word = RecognizedWord(
            id: wordID,
            text: "hello",
            startSeconds: 0,
            endSeconds: 0.4,
            rawEvidence: WordEvidence(
                tokenIDs: [42],
                tokenLogProbabilities: [-0.2],
                posterior: 0.9,
                availability: [.tokenIDs, .tokenLogProbabilities, .posterior]
            ),
            calibratedErrorProbability: 0.1,
            lockState: .locked,
            provenance: .primary(providerDecodeID: "decode-1", wordIndex: 0)
        )
        let result = RecognitionResult(
            sessionID: sessionID,
            generation: 7,
            engine: .whisperTurbo,
            model: ModelIdentity(
                identifier: "turbo",
                version: "1",
                quantization: "q5",
                computeUnits: "metal"
            ),
            pass: .primaryFullSession,
            text: "hello",
            words: [word],
            segments: [
                RecognizedSegment(
                    text: "hello",
                    startSeconds: 0,
                    endSeconds: 0.4,
                    wordIDs: [wordID]
                ),
            ],
            alternatives: [RecognitionAlternative(text: "hello", score: -0.2, rank: 0)],
            utteranceEvidence: UtteranceEvidence(
                averageLogProbability: -0.2,
                noSpeechProbability: 0.01
            ),
            timing: RecognitionTiming(
                audioDurationSeconds: 0.4,
                decodeDurationSeconds: 0.02
            ),
            completeness: .finalSession,
            passMetadata: RecognitionPassMetadata(
                strategy: "beam",
                beamSize: 5,
                protocolVersion: 2,
                requestID: "request-1"
            )
        )
        let envelope = RecognitionProtocolV2Envelope(
            event: .result,
            requestID: "request-1",
            result: result
        )

        let line = try RecognitionProtocolV2.encodeLine(envelope)
        XCTAssertTrue(line.contains("\"protocol_version\":2"))
        XCTAssertTrue(line.contains("\"session_id\""))
        XCTAssertEqual(try RecognitionProtocolV2.decode(line: line), envelope)
    }

    func testPartialResultWithoutOptionalEvidenceIsAccepted() throws {
        let line = """
        {"protocol_version":2,"event":"result","result":{"session_id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","generation":0,"engine":"whisperTurbo","text":"hello"}}
        """

        let envelope = try RecognitionProtocolV2.decode(line: line)
        XCTAssertEqual(envelope.result?.renderedText, "hello")
        XCTAssertEqual(envelope.result?.model, .unknown)
        XCTAssertTrue(envelope.result?.words.isEmpty == true)
        XCTAssertEqual(envelope.result?.completeness, .finalSession)
    }

    func testUnsupportedVersionAndOversizedLineFailBeforeDecoding() {
        XCTAssertThrowsError(
            try RecognitionProtocolV2.decode(
                line: "{\"protocol_version\":99,\"event\":\"ready\"}"
            )
        ) { error in
            XCTAssertEqual(
                error as? RecognitionContractError,
                .unsupportedProtocolVersion(99)
            )
        }

        let limits = RecognitionDecodingLimits(maxLineBytes: 16)
        XCTAssertThrowsError(
            try RecognitionProtocolV2.decode(
                data: Data(repeating: 0x20, count: 17),
                limits: limits
            )
        ) { error in
            XCTAssertEqual(
                error as? RecognitionContractError,
                .lineTooLarge(actualBytes: 17, maximumBytes: 16)
            )
        }
    }

    func testOversizedNestedWordArrayIsRejectedByBoundedDecoder() throws {
        let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let words = (0..<2).map { index in
            RecognizedWord(
                id: StableWordID(
                    sessionID: sessionID,
                    providerDecodeID: "decode-1",
                    wordIndex: index
                ),
                text: "word\(index)"
            )
        }
        let result = RecognitionResult(
            sessionID: sessionID,
            engine: .whisperTurbo,
            text: "word0 word1",
            words: words
        )
        let line = try RecognitionProtocolV2.encodeLine(
            RecognitionProtocolV2Envelope(event: .result, result: result)
        )
        let limits = RecognitionDecodingLimits(maxWords: 1)

        XCTAssertThrowsError(
            try RecognitionProtocolV2.decode(line: line, limits: limits)
        ) { error in
            XCTAssertEqual(
                error as? RecognitionContractError,
                .limitExceeded(field: "words", actual: 2, maximum: 1)
            )
        }
    }

    func testMalformedWordTimingIsRejected() {
        let line = """
        {"protocol_version":2,"event":"result","result":{"session_id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","generation":0,"engine":"whisperTurbo","text":"hello","words":[{"id":{"session_id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","provider_decode_id":"decode-1","word_index":0},"text":"hello","start_seconds":2,"end_seconds":1}]}}
        """

        XCTAssertThrowsError(try RecognitionProtocolV2.decode(line: line)) { error in
            guard case .malformed(let message) = error as? RecognitionContractError else {
                return XCTFail("expected malformed contract error, got \(error)")
            }
            XCTAssertTrue(message.contains("timing"))
        }
    }
}
