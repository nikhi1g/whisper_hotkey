import Foundation
import XCTest
@testable import WhisperHotkeyCore
@testable import WhisperHotkeyShell

/// Live round trip against the real DeepSeek endpoint. Skipped unless
/// `DEEPSEEK_LIVE_TEST=1` and a key are exported, so the default suite stays
/// offline and hermetic like every other test in this package.
final class DeepSeekLiveProcessorTests: XCTestCase {
    private func liveKey() throws -> String {
        let environment = ProcessInfo.processInfo.environment
        guard environment["DEEPSEEK_LIVE_TEST"] == "1",
              let key = environment["DEEPSEEK_API_KEY"],
              !key.isEmpty
        else {
            throw XCTSkip("live DeepSeek test disabled")
        }
        return key
    }

    /// The coding profile must rewrite a messy dictation into clean text —
    /// the exact substitution the insertion path performs when
    /// post-processing is enabled.
    func testLiveCodingRewriteReplacesTranscript() async throws {
        let key = try liveKey()
        let effort = DeepSeekReasoningEffort.max
        let processor = DeepSeekTranscriptProcessor(
            apiKeyProvider: { key },
            configuration: DeepSeekConfiguration(
                model: "deepseek-v4-flash",
                timeout: DeepSeekConfiguration.timeout(
                    thinkingEnabled: true,
                    reasoningEffort: effort
                ),
                maxOutputTokens: DeepSeekConfiguration.maxOutputTokens(
                    thinkingEnabled: true
                ),
                thinkingEnabled: true,
                reasoningEffort: effort
            )
        )
        let request = PostProcessRequest(
            rawText: "use fast api no i mean fastapi to build the endpoint "
                + "um and make sure it doesnt cache",
            profile: .coding,
            locale: "en-US",
            context: PostProcessContext(frontmostApp: "Terminal"),
            alternatives: [],
            uncertainSpans: [],
            protectedTerms: ["FastAPI"]
        )

        let result = try await processor.process(request)

        XCTAssertFalse(result.finalText.isEmpty)
        XCTAssertNotEqual(result.finalText, request.rawText)
        XCTAssertTrue(
            result.finalText.lowercased().contains("fastapi"),
            "identifier must survive the rewrite: \(result.finalText)"
        )
        XCTAssertFalse(
            result.finalText.contains("um "),
            "disfluencies must be removed: \(result.finalText)"
        )
    }

    /// The custom profile must actually steer the live rewrite: the owner's
    /// prompt is the objective the model receives.
    func testLiveCustomPromptSteersTheRewrite() async throws {
        let key = try liveKey()
        let processor = DeepSeekTranscriptProcessor(
            apiKeyProvider: { key },
            configuration: DeepSeekConfiguration(
                model: "deepseek-v4-flash",
                timeout: DeepSeekConfiguration.timeout(
                    thinkingEnabled: false,
                    reasoningEffort: .low
                ),
                thinkingEnabled: false,
                customProfilePrompt:
                    "Rewrite the dictation as a single ALL CAPS sentence."
            )
        )
        let request = PostProcessRequest(
            rawText: "so uh lets ship the release tomorrow morning",
            profile: .custom,
            locale: "en-US",
            context: PostProcessContext(frontmostApp: "Terminal")
        )

        let result = try await processor.process(request)

        XCTAssertEqual(
            result.finalText,
            result.finalText.uppercased(),
            "the custom prompt must drive the rewrite: \(result.finalText)"
        )
    }

    /// A bad key must surface as an HTTP failure, which the review flow maps
    /// to the unavailable preview that inserts the raw transcript.
    func testLiveInvalidKeyFailsFast() async throws {
        _ = try liveKey()
        let processor = DeepSeekTranscriptProcessor(
            apiKeyProvider: { "sk-invalid-key-for-test" },
            configuration: DeepSeekConfiguration(model: "deepseek-v4-flash")
        )
        do {
            try await processor.validateCredentials()
            XCTFail("an invalid key must not validate")
        } catch let error as ProcessorError {
            guard case .httpStatus = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }
}
