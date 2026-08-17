import Foundation
import XCTest
@testable import WhisperHotkeyApp
import WhisperHotkeyCore

/// Flow-level behavior of the post-processing review wiring, driven through
/// `PostProcessingReviewFlow` with a stubbed `TranscriptProcessor`. No real
/// network and no real keychain: eligibility is a plain Bool parameter.
final class PostProcessingFlowTests: XCTestCase {
    // MARK: - Stub processor (implements the Core protocol)

    private enum StubBehavior {
        case respond(PostProcessResult)
        case throwError(any Error)
        case delayedReturn(PostProcessResult, nanoseconds: UInt64)
    }

    private actor StubTranscriptProcessor: TranscriptProcessor {
        private let behavior: StubBehavior
        private(set) var callCount = 0
        private(set) var lastRequest: PostProcessRequest?

        init(_ behavior: StubBehavior) {
            self.behavior = behavior
        }

        func process(
            _ request: PostProcessRequest
        ) async throws -> PostProcessResult {
            callCount += 1
            lastRequest = request
            switch behavior {
            case .respond(let result):
                return result
            case .throwError(let error):
                throw error
            case .delayedReturn(let result, let nanoseconds):
                try await Task.sleep(nanoseconds: nanoseconds)
                return result
            }
        }
    }

    // MARK: - Fixtures

    private static let processedResult = PostProcessResult(
        finalText: "Deploy the Kubernetes service now.",
        intent: "instruction",
        unresolvedSpans: [],
        explicitCorrections: [],
        meaningChangeRisk: .low
    )

    private static let sampleRequest = PostProcessRequest(
        rawText: "deploy the service",
        profile: .clarity,
        locale: "en-US",
        context: PostProcessContext(frontmostApp: "Terminal"),
        alternatives: [],
        uncertainSpans: ["service"],
        protectedTerms: ["Kubernetes"]
    )

    private func route(
        _ transcript: String,
        enabled: Bool = true,
        key: Bool = true
    ) -> PostProcessingReviewFlow.FinalTranscriptRoute {
        PostProcessingReviewFlow.routeFinalTranscript(
            transcript,
            postProcessingEnabled: enabled,
            apiKeyAvailable: key,
            profile: .clarity,
            protectedTerms: [],
            uncertainSpans: [],
            internalDictionaryEntries: ["Codex"],
            frontmostApp: "Xcode"
        )
    }

    // MARK: - Command interception (never reaches the processor)

    func testVoiceCommandsAreInterceptedBeforeAnyProcessing() async {
        let cases: [(String, VoiceCommand)] = [
            ("mode coding", .setProfile(.coding)),
            ("Mode Clarity", .setProfile(.clarity)),
            ("verbatim mode", .setProfile(.verbatim)),
            ("scratch that", .scratchLastSegment),
            ("send", .send),
            ("cancel", .cancel),
            ("show original", .showOriginal),
        ]
        for (transcript, expected) in cases {
            XCTAssertEqual(
                route(transcript),
                .voiceCommand(expected),
                transcript
            )
        }

        // Only a .review route can start processing; commands never do.
        let processor = StubTranscriptProcessor(.respond(Self.processedResult))
        for transcript in cases.map(\.0) {
            if case .review = route(transcript) {
                XCTFail("command \(transcript) must not reach the processor")
            }
        }
        let calls = await processor.callCount
        XCTAssertEqual(calls, 0)
    }

    func testCommandsAreNotInterceptedWhenFeatureIsDisabled() {
        // Disabled means byte-identical to today: command-looking text is
        // content and takes the direct insertion path.
        XCTAssertEqual(
            route("mode coding", enabled: false),
            .directInsert("mode coding")
        )
        XCTAssertEqual(
            route("scratch that", key: false),
            .directInsert("scratch that")
        )
    }

    // MARK: - Direct path

    func testDisabledToggleTakesDirectPath() {
        XCTAssertEqual(
            route("hello world", enabled: false),
            .directInsert("hello world")
        )
    }

    func testAbsentKeyTakesDirectPath() {
        XCTAssertEqual(route("hello world", key: false), .directInsert("hello world"))
    }

    func testEmptyTranscriptTakesDirectPath() {
        XCTAssertEqual(route("   "), .directInsert("   "))
    }

    // MARK: - Request construction

    func testReviewRouteBuildsRequestFromEvidence() {
        let routed = PostProcessingReviewFlow.routeFinalTranscript(
            "deploy the service",
            postProcessingEnabled: true,
            apiKeyAvailable: true,
            profile: .coding,
            protectedTerms: ["Kubernetes"],
            uncertainSpans: ["service"],
            internalDictionaryEntries: ["Codex"],
            frontmostApp: "Terminal"
        )
        guard case .review(let request) = routed else {
            return XCTFail("expected review route, got \(routed)")
        }
        XCTAssertEqual(request.rawText, "deploy the service")
        XCTAssertEqual(request.profile, .coding)
        XCTAssertEqual(request.locale, "en-US")
        XCTAssertEqual(request.protectedTerms, ["Kubernetes"])
        XCTAssertEqual(request.uncertainSpans, ["service"])
        XCTAssertEqual(request.context.frontmostApp, "Terminal")
    }

    func testReviewRequestFallsBackToInternalDictionaryEntries() {
        let routed = PostProcessingReviewFlow.routeFinalTranscript(
            "deploy the service",
            postProcessingEnabled: true,
            apiKeyAvailable: true,
            profile: .clarity,
            protectedTerms: [],
            uncertainSpans: [],
            internalDictionaryEntries: ["Codex", "projLab"],
            frontmostApp: nil
        )
        guard case .review(let request) = routed else {
            return XCTFail("expected review route, got \(routed)")
        }
        XCTAssertEqual(request.protectedTerms, ["Codex", "projLab"])
    }

    // MARK: - Review choices

    func testAcceptInsertsProcessedText() {
        let preview = PostProcessPreview(
            rawText: "deploy the service",
            processed: Self.processedResult,
            report: PreservationReport(issues: [], pass: true),
            profile: .clarity,
            unavailable: false
        )
        XCTAssertEqual(
            PostProcessingReviewFlow.acceptedText(for: preview),
            Self.processedResult.finalText
        )
    }

    func testAcceptOnUnavailablePreviewInsertsRawText() {
        let preview = PostProcessPreview(
            rawText: "deploy the service",
            processed: nil,
            report: PreservationReport(issues: [], pass: false),
            profile: .clarity,
            unavailable: true
        )
        XCTAssertEqual(
            PostProcessingReviewFlow.acceptedText(for: preview),
            "deploy the service"
        )
    }

    func testRestoreRawInsertsRawText() {
        let preview = PostProcessPreview(
            rawText: "deploy the service",
            processed: Self.processedResult,
            report: PreservationReport(issues: [], pass: true),
            profile: .clarity,
            unavailable: false
        )
        XCTAssertEqual(
            PostProcessingReviewFlow.restoredText(for: preview),
            "deploy the service"
        )
    }

    // MARK: - Processor success and failure

    func testProcessorSuccessBuildsPresentablePreview() async {
        let processor = StubTranscriptProcessor(.respond(Self.processedResult))
        let preview = await PostProcessingReviewFlow.process(
            request: Self.sampleRequest,
            using: processor
        )
        XCTAssertEqual(preview.processed, Self.processedResult)
        XCTAssertEqual(preview.rawText, Self.sampleRequest.rawText)
        XCTAssertEqual(preview.profile, .clarity)
        XCTAssertFalse(preview.unavailable)
        XCTAssertTrue(preview.report.pass)
    }

    func testProcessorThrowYieldsUnavailablePreview() async {
        let processor = StubTranscriptProcessor(
            .throwError(URLError(.timedOut))
        )
        let preview = await PostProcessingReviewFlow.process(
            request: Self.sampleRequest,
            using: processor
        )
        XCTAssertTrue(preview.unavailable)
        XCTAssertNil(preview.processed)
        XCTAssertEqual(preview.rawText, Self.sampleRequest.rawText)

        // Enter on an unavailable preview still inserts the raw transcript.
        XCTAssertEqual(
            PostProcessingReviewFlow.acceptedText(for: preview),
            Self.sampleRequest.rawText
        )
    }

    func testOverLimitResultFallsBackToUnavailablePreview() async {
        let oversized = PostProcessResult(
            finalText: String(repeating: "a", count: 8_001),
            intent: "",
            unresolvedSpans: [],
            explicitCorrections: [],
            meaningChangeRisk: .low
        )
        let processor = StubTranscriptProcessor(.respond(oversized))
        let preview = await PostProcessingReviewFlow.process(
            request: Self.sampleRequest,
            using: processor
        )
        XCTAssertTrue(preview.unavailable)
        XCTAssertNil(preview.processed)
    }

    // MARK: - Generation safety

    @MainActor
    func testStaleGenerationResultIsNeverPresented() async {
        var previews: [PostProcessPreview] = []
        var currentGeneration: UInt64 = 7
        let processor = StubTranscriptProcessor(
            .delayedReturn(Self.processedResult, nanoseconds: 40_000_000)
        )
        let session = PostProcessingReviewSession(
            processor: processor,
            isSessionCurrent: { generation in
                generation == currentGeneration
            },
            onPreview: { previews.append($0) }
        )

        session.start(Self.sampleRequest, generation: 7)
        // A cancel invalidates the generation while the request is in flight.
        currentGeneration = 8
        session.cancel()
        try? await Task.sleep(for: .milliseconds(120))

        XCTAssertTrue(
            previews.isEmpty,
            "a stale result must never be presented after cancellation"
        )
        let calls = await processor.callCount
        XCTAssertEqual(calls, 1, "the request ran once; only presentation is gated")
    }

    @MainActor
    func testCurrentGenerationPresentsPreview() async throws {
        var previews: [PostProcessPreview] = []
        let processor = StubTranscriptProcessor(
            .delayedReturn(Self.processedResult, nanoseconds: 20_000_000)
        )
        let session = PostProcessingReviewSession(
            processor: processor,
            isSessionCurrent: { $0 == 7 },
            onPreview: { previews.append($0) }
        )

        session.start(Self.sampleRequest, generation: 7)
        let deadline = Date().addingTimeInterval(1)
        while previews.isEmpty, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(previews.count, 1)
        XCTAssertEqual(previews.first?.processed, Self.processedResult)
        XCTAssertEqual(previews.first?.unavailable, false)
    }
}
