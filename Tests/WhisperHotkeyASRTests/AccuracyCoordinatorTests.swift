import Foundation
import XCTest
@testable import WhisperHotkeyASR
import WhisperHotkeyCore

final class AccuracyCoordinatorTests: XCTestCase {
    func testAdaptiveUncertainResultTriggersSecondaryVerifierPass() async throws {
        let primary = makeHypothesis(
            text: "uncertain greeting",
            averageLogProbability: -2.0,
            noSpeechProbability: 0.2
        )
        let secondary = makeHypothesis(
            text: "certain greeting",
            averageLogProbability: -0.2,
            noSpeechProbability: 0.01
        )
        let provider = FakeCandidateProvider(
            primary: primary,
            alternate: secondary
        )
        let decision = try await AccuracyCoordinator(
            primaryProvider: provider,
            secondaryProvider: provider
        ).finalize(
            request: RecognitionRequest(
                requestID: "adaptive-test",
                audioURL: URL(fileURLWithPath: "/private/utterance.wav"),
                window: .init(startSample: 0, endSample: 10),
                strategy: .adaptive,
                protocolVersion: 2
            )
        )

        let primaryInvocations = await provider.primaryInvocationCount()
        let alternateInvocations = await provider.alternateInvocationCount()
        let alternateRequestPayload = await provider.lastAlternateRequest()
        let alternateRequest = try XCTUnwrap(alternateRequestPayload)
        let alternatePass = await provider.lastAlternatePass()
        XCTAssertEqual(primaryInvocations, 1)
        XCTAssertEqual(alternateInvocations, 1)
        XCTAssertEqual(decision.alternatives.count, 2)
        XCTAssertEqual(alternateRequest.strategy, .beam)
        XCTAssertEqual(alternatePass, .secondaryVerifier)
        XCTAssertEqual(alternateRequest.requestID, "adaptive-test")
        XCTAssertEqual(alternateRequest.protocolVersion, 2)
        XCTAssertEqual(decision.trace.rejectionReasons.count, 1)
        XCTAssertTrue(decision.trace.rejectionReasons.contains {
            $0.contains("averageLogProbability")
        })
    }

    func testAdaptiveHelperFallbackResultSkipsSecondaryRetry() async throws {
        let primary = makeHypothesis(
            text: "already retried",
            adaptiveFallback: true,
            averageLogProbability: -2.0,
            noSpeechProbability: 0.2,
            repetitionDetected: true
        )
        let provider = FakeCandidateProvider(
            primary: primary,
            alternate: makeHypothesis(text: "should never run")
        )

        let decision = try await AccuracyCoordinator(
            primaryProvider: provider,
            secondaryProvider: provider
        ).finalize(
            request: RecognitionRequest(
                requestID: "adaptive-fallback",
                audioURL: URL(fileURLWithPath: "/private/utterance.wav"),
                window: .init(startSample: 0, endSample: 10),
                strategy: .adaptive,
                protocolVersion: 2
            )
        )

        let primaryInvocations = await provider.primaryInvocationCount()
        let alternateInvocations = await provider.alternateInvocationCount()
        XCTAssertEqual(primaryInvocations, 1)
        XCTAssertEqual(alternateInvocations, 0)
        XCTAssertEqual(decision.alternatives.count, 1)
        XCTAssertEqual(decision.selected.text, primary.text)
        XCTAssertEqual(decision.trace.rejectionReasons, [
            "adaptive fallback was already performed"
        ])
    }

    func testBeamProfileNeverInvokesSecondaryVerifier() async throws {
        let primary = makeHypothesis(
            text: "uncertain but no retry",
            averageLogProbability: -2.0,
            noSpeechProbability: 0.8
        )
        let provider = FakeCandidateProvider(
            primary: primary,
            alternate: makeHypothesis(text: "beam fallback")
        )

        let decision = try await AccuracyCoordinator(
            primaryProvider: provider,
            secondaryProvider: provider
        ).finalize(
            request: RecognitionRequest(
                requestID: "beam-only",
                audioURL: URL(fileURLWithPath: "/private/utterance.wav"),
                window: .init(startSample: 0, endSample: 10),
                strategy: .beam,
                protocolVersion: 2
            )
        )

        let primaryInvocations = await provider.primaryInvocationCount()
        let alternateInvocations = await provider.alternateInvocationCount()
        XCTAssertEqual(primaryInvocations, 1)
        XCTAssertEqual(alternateInvocations, 0)
        XCTAssertEqual(decision.alternatives.count, 1)
        XCTAssertEqual(decision.trace.rejectionReasons.count, 2)
        XCTAssertTrue(decision.trace.rejectionReasons.contains {
            $0.contains("averageLogProbability")
        })
        XCTAssertTrue(decision.trace.rejectionReasons.contains {
            $0.contains("noSpeechProbability")
        })
    }

    func testUncertaintyDetectorFlagsLowConfidenceMetadata() {
        let low = makeHypothesis(
            text: "uncertain",
            averageLogProbability: -2.1,
            noSpeechProbability: 0.99,
            repetitionDetected: true
        )
        let assessment = UncertaintyDetector.assess(
            hypothesis: low,
            policy: AccuracyPolicy()
        )

        XCTAssertTrue(assessment.isUncertain)
        XCTAssertEqual(assessment.reasons.count, 3)
        XCTAssertGreaterThan(assessment.score, 0.99)
    }

    func testUncertaintyDetectorFlagsWeakTokenFraction() {
        let low = makeHypothesis(
            text: "uncertain weak tokens",
            averageLogProbability: -0.1,
            noSpeechProbability: 0.01,
            weakTokenFraction: 0.11,
            repetitionDetected: false
        )
        XCTAssertNotNil(low.weakTokenFraction)
        let assessment = UncertaintyDetector.assess(
            hypothesis: low,
            policy: AccuracyPolicy()
        )

        XCTAssertTrue(assessment.isUncertain)
        XCTAssertEqual(assessment.reasons.count, 1)
        XCTAssertTrue(
            assessment.reasons.contains { $0.contains("weakTokenFraction") },
            "reasons=\(assessment.reasons)"
        )
        XCTAssertEqual(assessment.score, 1.0)
    }

    func testUncertaintyDetectorAcceptsClearResult() {
        let clear = makeHypothesis(
            text: "clear",
            averageLogProbability: -0.1,
            noSpeechProbability: 0.01,
            repetitionDetected: false
        )
        let assessment = UncertaintyDetector.assess(
            hypothesis: clear,
            policy: AccuracyPolicy()
        )

        XCTAssertFalse(assessment.isUncertain)
        XCTAssertTrue(assessment.reasons.isEmpty)
        XCTAssertEqual(assessment.score, 0.0)
    }

    func testUncertaintyDetectorPenalizesMissingMetadataWhenConfigured() {
        let ambiguous = makeHypothesis(
            text: "missing metadata",
            adaptiveFallback: false,
            averageLogProbability: nil,
            noSpeechProbability: nil,
            repetitionDetected: false
        )
        let policy = AccuracyPolicy(missingMetadataPenalty: 0.4)
        let assessment = UncertaintyDetector.assess(
            hypothesis: ambiguous,
            policy: policy
        )

        XCTAssertTrue(assessment.isUncertain)
        XCTAssertGreaterThanOrEqual(assessment.score, 0.4)
    }

    private func makeHypothesis(
        text: String,
        adaptiveFallback: Bool = false,
        averageLogProbability: Double? = nil,
        noSpeechProbability: Double? = nil,
        weakTokenFraction: Double? = nil,
        repetitionDetected: Bool = false
    ) -> RecognitionHypothesis {
        let window = RecognitionWindow(
            startSample: 0,
            endSample: 10,
            sampleRate: 16_000
        )
        return RecognitionHypothesis(
            engine: .whisperTurbo,
            pass: .primaryFullSession,
            window: window,
            text: text,
            averageLogProbability: averageLogProbability,
            noSpeechProbability: noSpeechProbability,
            weakTokenFraction: weakTokenFraction,
            repetitionDetected: repetitionDetected,
            adaptiveFallback: adaptiveFallback,
            metadata: ["test": "value"]
        )
    }
}

private actor FakeCandidateProvider: RecognitionCandidateProvider {
    nonisolated let capabilities: RecognitionCapabilities = [
        .prompt,
        .beamSearch,
    ]
    private var primaryCalls: Int = 0
    private var alternateCalls: Int = 0
    private var alternateRequestPayload: RecognitionRequest?
    private var alternatePassPayload: RecognitionPassKind?

    private let primaryResult: RecognitionHypothesis
    private let alternateResult: RecognitionHypothesis

    init(
        primary: RecognitionHypothesis,
        alternate: RecognitionHypothesis
    ) {
        primaryResult = primary
        alternateResult = alternate
    }

    func primaryHypothesis(
        request: RecognitionRequest
    ) async throws -> RecognitionHypothesis {
        primaryCalls += 1
        return primaryResult
    }

    func alternateHypothesis(
        request: AlternateRecognitionRequest
    ) async throws -> RecognitionHypothesis {
        alternateCalls += 1
        alternateRequestPayload = request.base
        alternatePassPayload = request.pass
        return alternateResult
    }

    func primaryInvocationCount() -> Int { primaryCalls }
    func alternateInvocationCount() -> Int { alternateCalls }
    func lastAlternateRequest() -> RecognitionRequest? {
        alternateRequestPayload
    }
    func lastAlternatePass() -> RecognitionPassKind {
        alternatePassPayload ?? .secondaryVerifier
    }
}
