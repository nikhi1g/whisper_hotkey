import Foundation
import XCTest
@testable import WhisperHotkeyApp
@testable import WhisperHotkeyASR
import WhisperHotkeyCore
import WhisperHotkeyShell

/// End-to-end proof that enabling post-processing replaces the inserted text:
/// a real audio file is recognized locally, the transcript is routed through
/// the same gate the delegate uses, rewritten by the real DeepSeek API, and
/// the state machine delivers the rewritten text — not the raw transcript.
///
/// Skipped unless `DEEPSEEK_LIVE_TEST=1`, `DEEPSEEK_API_KEY` and
/// `WHISPER_HOTKEY_PARAKEET_FIXTURE` (16 kHz mono PCM16 WAV) are exported, so
/// the default suite stays offline.
final class PostProcessingEndToEndTests: XCTestCase {
    private func liveKey() throws -> String {
        let environment = ProcessInfo.processInfo.environment
        guard environment["DEEPSEEK_LIVE_TEST"] == "1",
              let key = environment["DEEPSEEK_API_KEY"], !key.isEmpty
        else {
            throw XCTSkip("live DeepSeek test disabled")
        }
        return key
    }

    private func recognizeFixture() async throws -> String {
        guard let fixture = ProcessInfo.processInfo
            .environment["WHISPER_HOTKEY_PARAKEET_FIXTURE"]
        else {
            throw XCTSkip("set WHISPER_HOTKEY_PARAKEET_FIXTURE to run")
        }
        let directory = URL(
            fileURLWithPath: NSTemporaryDirectory(),
            isDirectory: true
        ).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let audioURL = directory.appendingPathComponent("fixture.wav")
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: fixture),
            to: audioURL
        )
        let audio = WhisperAudioFile(
            url: audioURL,
            directoryURL: directory,
            speechPresence: .present
        )
        let configuration = try WhisperRuntimeDiscovery.discover(
            model: .baseEnglish,
            engine: .parakeetCoreML,
            environment: [:]
        )
        let recognizer = WhisperRecognizer(configuration: configuration)
        return try await recognizer.transcribeResult(audio).text
    }

    /// Same path, but with the owner's custom profile driving the rewrite.
    func testCustomProfileRewritesDictatedAudioWithTheOwnersPrompt()
        async throws
    {
        let key = try liveKey()
        let transcript = try await recognizeFixture()
        let route = PostProcessingReviewFlow.routeFinalTranscript(
            transcript,
            postProcessingEnabled: true,
            apiKeyAvailable: true,
            profile: .custom,
            protectedTerms: [],
            uncertainSpans: [],
            internalDictionaryEntries: [],
            frontmostApp: "Terminal"
        )
        guard case .review(let request) = route else {
            return XCTFail("enabled post-processing must route to review")
        }
        let processor = DeepSeekTranscriptProcessor(
            apiKeyProvider: { key },
            configuration: DeepSeekConfiguration(
                model: "deepseek-v4-flash",
                thinkingEnabled: false,
                customProfilePrompt:
                    "Rewrite the dictation as a single ALL CAPS sentence."
            )
        )
        let preview = await PostProcessingReviewFlow.process(
            request: request,
            using: processor
        )
        XCTAssertFalse(preview.unavailable)
        let delivered = PostProcessingReviewFlow.acceptedText(for: preview)
        XCTAssertEqual(
            delivered,
            delivered.uppercased(),
            "the custom prompt must drive the pasted text: \(delivered)"
        )
    }

    func testDictatedAudioIsDeliveredAsTheEnhancedRewrite() async throws {
        let key = try liveKey()
        let transcript = try await recognizeFixture()
        XCTAssertFalse(
            transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )

        // 1. The gate the delegate runs on every final transcript.
        let route = PostProcessingReviewFlow.routeFinalTranscript(
            transcript,
            postProcessingEnabled: true,
            apiKeyAvailable: true,
            profile: .coding,
            protectedTerms: ["FastAPI"],
            uncertainSpans: [],
            internalDictionaryEntries: [],
            frontmostApp: "Terminal"
        )
        guard case .review(let request) = route else {
            return XCTFail("enabled post-processing must route to review")
        }

        // 2. The real processor, configured exactly as the delegate does.
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
        let preview = await PostProcessingReviewFlow.process(
            request: request,
            using: processor
        )
        XCTAssertFalse(preview.unavailable, "the live rewrite must succeed")

        // 3. The delivery the state machine performs for that preview.
        var machine = DictationStateMachine()
        machine.handle(.hotkeyPressed(at: 0))
        machine.handle(.captureStarted)
        machine.handle(.hotkeyReleased(at: 2))
        XCTAssertEqual(machine.phase, .transcribing)
        XCTAssertEqual(
            machine.handle(.processingRequested),
            [.requestProcessing, .showBadge(.enhancing)]
        )
        let delivered = PostProcessingReviewFlow.acceptedText(for: preview)
        XCTAssertEqual(machine.handle(.reviewAccepted), [.deliverTranscript])
        XCTAssertEqual(machine.phase, .inserting)

        XCTAssertNotEqual(delivered, transcript, "raw text must be replaced")
        XCTAssertEqual(delivered, preview.processed?.finalText)
        XCTAssertTrue(
            delivered.lowercased().contains("fastapi"),
            "identifier must survive: \(delivered)"
        )
        print("RAW: \(transcript)\nENHANCED: \(delivered)")
    }
}
