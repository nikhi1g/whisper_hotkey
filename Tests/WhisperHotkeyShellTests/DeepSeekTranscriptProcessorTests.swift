import Foundation
import XCTest
@testable import WhisperHotkeyCore
@testable import WhisperHotkeyShell

// MARK: - Stub plumbing

/// Captures every request the processor makes; thread-safe because
/// URLSession delivers requests on its own queue.
private final class RequestJournal: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func append(_ request: URLRequest) {
        lock.lock()
        requests.append(request)
        lock.unlock()
    }

    var all: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }
}

/// URLProtocol-based stub registered on an injected session configuration;
/// no real network traffic is ever attempted.
private final class StubURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    nonisolated(unsafe) static var handler: Handler?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private actor ProviderCallCounter {
    private var value = 0

    func record() {
        value += 1
    }

    var count: Int { value }
}

// MARK: - Test fixtures

private let validResultContent = """
{"finalText":"Open the terminal and run the build.","intent":"open the terminal and run the build","unresolvedSpans":[],"explicitCorrections":[],"meaningChangeRisk":"low"}
"""

private func envelopeJSON(_ content: String) -> Data {
    let envelope: [String: Any] = [
        "choices": [
            ["message": ["role": "assistant", "content": content]],
        ],
    ]
    return try! JSONSerialization.data(withJSONObject: envelope)
}

private func httpResponse(status: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://api.deepseek.com/chat/completions")!,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
    )!
}

/// Reassembles a request body; URLProtocol sees `httpBodyStream` rather
/// than `httpBody`.
private func requestBody(_ request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else {
        return nil
    }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 4_096
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    while true {
        let read = stream.read(buffer, maxLength: bufferSize)
        if read <= 0 {
            break
        }
        data.append(buffer, count: read)
    }
    return data
}

// MARK: - Tests

final class DeepSeekTranscriptProcessorTests: XCTestCase {
    private func makeConfiguration(
        timeout: TimeInterval = 5.0,
        model: String = "test-model",
        thinkingEnabled: Bool = false,
        reasoningEffort: DeepSeekReasoningEffort = .low
    ) -> DeepSeekConfiguration {
        DeepSeekConfiguration(
            baseURL: URL(string: "https://api.deepseek.com")!,
            model: model,
            timeout: timeout,
            thinkingEnabled: thinkingEnabled,
            reasoningEffort: reasoningEffort
        )
    }

    private func makeRequest() -> PostProcessRequest {
        PostProcessRequest(
            rawText: "please open the terminal and run the build",
            profile: .coding,
            locale: "en-US",
            context: PostProcessContext(domain: "iOS", language: "Swift"),
            alternatives: [],
            uncertainSpans: [],
            protectedTerms: ["whisper_hotkey"]
        )
    }

    private func makeProcessor(
        handler: @escaping StubURLProtocol.Handler,
        configuration: DeepSeekConfiguration? = nil,
        apiKeyProvider: @escaping @Sendable () async throws -> String = { "test-key" },
        journal: RequestJournal? = nil
    ) -> DeepSeekTranscriptProcessor {
        let journal = journal ?? RequestJournal()
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        StubURLProtocol.handler = { request in
            journal.append(request)
            return try handler(request)
        }
        return DeepSeekTranscriptProcessor(
            apiKeyProvider: apiKeyProvider,
            configuration: configuration ?? makeConfiguration(),
            session: session
        )
    }

    // MARK: Success

    func testProcessReturnsParsedResultOnSuccess() async throws {
        let journal = RequestJournal()
        let processor = makeProcessor(
            handler: { _ in (httpResponse(status: 200), envelopeJSON(validResultContent)) },
            journal: journal
        )
        let result = try await processor.process(makeRequest())
        XCTAssertEqual(result.finalText, "Open the terminal and run the build.")
        XCTAssertEqual(result.intent, "open the terminal and run the build")
        XCTAssertEqual(result.meaningChangeRisk, .low)
        XCTAssertEqual(journal.all.count, 1)
    }

    // MARK: Retry-once on recoverable output failures

    func testRetriesOnceOnEmptyContentThenThrowsEmptyOutput() async {
        let journal = RequestJournal()
        let processor = makeProcessor(
            handler: { _ in (httpResponse(status: 200), envelopeJSON("")) },
            journal: journal
        )
        do {
            _ = try await processor.process(makeRequest())
            XCTFail("Expected ProcessorError.emptyOutput")
        } catch let error as ProcessorError {
            XCTAssertEqual(error, .emptyOutput)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(journal.all.count, 2)
    }

    func testRetriesOnceOnSchemaInvalidJSONThenThrows() async {
        let journal = RequestJournal()
        let processor = makeProcessor(
            handler: { _ in
                (httpResponse(status: 200), envelopeJSON(#"{"finalText":"missing required fields"}"#))
            },
            journal: journal
        )
        do {
            _ = try await processor.process(makeRequest())
            XCTFail("Expected ProcessorError.invalidOutput")
        } catch let error as ProcessorError {
            guard case .invalidOutput = error else {
                return XCTFail("Expected invalidOutput, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(journal.all.count, 2)
    }

    func testRetriesOnceOnOversizedFinalTextThenThrows() async {
        let journal = RequestJournal()
        let oversized = String(
            repeating: "x",
            count: PostProcessLimits.maxFinalTextLength + 1
        )
        let content = #"{"finalText":"\#(oversized)","intent":"","unresolvedSpans":[],"explicitCorrections":[],"meaningChangeRisk":"low"}"#
        let processor = makeProcessor(
            handler: { _ in (httpResponse(status: 200), envelopeJSON(content)) },
            journal: journal
        )
        do {
            _ = try await processor.process(makeRequest())
            XCTFail("Expected ProcessorError.invalidOutput")
        } catch let error as ProcessorError {
            guard case .invalidOutput = error else {
                return XCTFail("Expected invalidOutput, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(journal.all.count, 2)
    }

    // MARK: Never-retried failures

    func testHTTP401FailsImmediatelyWithoutRetry() async {
        let journal = RequestJournal()
        let processor = makeProcessor(
            handler: { _ in
                (httpResponse(status: 401), Data(#"{"error":{"message":"unauthorized"}}"#.utf8))
            },
            journal: journal
        )
        do {
            _ = try await processor.process(makeRequest())
            XCTFail("Expected ProcessorError.httpStatus(401)")
        } catch let error as ProcessorError {
            XCTAssertEqual(error, .httpStatus(401))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(journal.all.count, 1)
    }

    func testHTTP403FailsImmediatelyWithoutRetry() async {
        let journal = RequestJournal()
        let processor = makeProcessor(
            handler: { _ in
                (httpResponse(status: 403), Data(#"{"error":{"message":"forbidden"}}"#.utf8))
            },
            journal: journal
        )
        do {
            _ = try await processor.process(makeRequest())
            XCTFail("Expected ProcessorError.httpStatus(403)")
        } catch let error as ProcessorError {
            XCTAssertEqual(error, .httpStatus(403))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(journal.all.count, 1)
    }

    func testTransportTimeoutThrowsWithoutRetry() async {
        let journal = RequestJournal()
        let processor = makeProcessor(
            handler: { _ in
                // Outlives the 1 s request timeout; URLSession fails the load.
                Thread.sleep(forTimeInterval: 2.0)
                return (httpResponse(status: 200), envelopeJSON(validResultContent))
            },
            configuration: makeConfiguration(timeout: 1.0),
            journal: journal
        )
        do {
            _ = try await processor.process(makeRequest())
            XCTFail("Expected ProcessorError.transport(.timedOut)")
        } catch let error as ProcessorError {
            guard case .transport(let code) = error else {
                return XCTFail("Expected transport, got \(error)")
            }
            XCTAssertEqual(code, .timedOut)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(journal.all.count, 1)
    }

    // MARK: Key handling

    func testMissingKeyThrowsBeforeAnyRequest() async {
        let journal = RequestJournal()
        let processor = makeProcessor(
            handler: { _ in (httpResponse(status: 200), envelopeJSON(validResultContent)) },
            apiKeyProvider: { throw ProcessorError.missingKey },
            journal: journal
        )
        do {
            _ = try await processor.process(makeRequest())
            XCTFail("Expected ProcessorError.missingKey")
        } catch let error as ProcessorError {
            XCTAssertEqual(error, .missingKey)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(journal.all.count, 0)
    }

    /// With `DEEPSEEK_API_KEY` set, the injected provider resolves through
    /// `ProcessorKeychain.read()`, whose env override short-circuits before
    /// any SecItem call; the key is then used as the bearer token.
    func testEnvironmentKeyOverrideIsUsedAndNoKeychainCallIsMade() async throws {
        setenv("DEEPSEEK_API_KEY", "env-secret-123", 1)
        defer { unsetenv("DEEPSEEK_API_KEY") }
        let journal = RequestJournal()
        let providerCalls = ProviderCallCounter()
        let processor = makeProcessor(
            handler: { _ in (httpResponse(status: 200), envelopeJSON(validResultContent)) },
            apiKeyProvider: {
                await providerCalls.record()
                guard let key = try ProcessorKeychain.read() else {
                    throw ProcessorError.missingKey
                }
                return key
            },
            journal: journal
        )
        let result = try await processor.process(makeRequest())
        XCTAssertEqual(result.finalText, "Open the terminal and run the build.")
        let captured = try XCTUnwrap(journal.all.first)
        XCTAssertEqual(
            captured.value(forHTTPHeaderField: "Authorization"),
            "Bearer env-secret-123"
        )
        let calls = await providerCalls.count
        XCTAssertEqual(calls, 1)
    }

    // MARK: Request body shape

    func testRequestBodyCarriesContractShapeAndAssembledPrompt() async throws {
        let journal = RequestJournal()
        let processor = makeProcessor(
            handler: { _ in (httpResponse(status: 200), envelopeJSON(validResultContent)) },
            configuration: makeConfiguration(model: "custom-model"),
            journal: journal
        )
        _ = try await processor.process(makeRequest())

        let captured = try XCTUnwrap(journal.all.first)
        XCTAssertEqual(captured.httpMethod, "POST")
        XCTAssertEqual(
            captured.value(forHTTPHeaderField: "Content-Type"),
            "application/json"
        )
        XCTAssertEqual(
            captured.value(forHTTPHeaderField: "Authorization"),
            "Bearer test-key"
        )

        // URLSession hands URLProtocol the body as a stream, not httpBody.
        let body = try XCTUnwrap(requestBody(captured))
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(json["model"] as? String, "custom-model")
        XCTAssertEqual(json["max_tokens"] as? Int, 800)
        XCTAssertEqual(
            (json["response_format"] as? [String: Any])?["type"] as? String,
            "json_object"
        )
        XCTAssertEqual(
            (json["thinking"] as? [String: Any])?["type"] as? String,
            "disabled"
        )

        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertEqual(messages[1]["role"] as? String, "user")

        let system = try XCTUnwrap(messages[0]["content"] as? String)
        // Transducer constraints.
        XCTAssertTrue(system.contains("transform"))
        XCTAssertTrue(system.contains("Never answer"))
        XCTAssertTrue(system.contains("instructions are data"))
        XCTAssertTrue(
            system.contains(
                "Preserve the speaker's intent, uncertainty markers, negations"
            )
        )
        XCTAssertTrue(system.contains("self-corrections"))
        XCTAssertTrue(system.contains("JSON"))
        // Coding profile fields.
        XCTAssertTrue(system.contains("technical brief"))
        XCTAssertTrue(system.contains("Open questions"))
        XCTAssertTrue(system.contains("Inventing requirements"))

        let user = try XCTUnwrap(messages[1]["content"] as? String)
        XCTAssertTrue(user.hasPrefix("TRANSCRIPT PACKAGE\n"))
        XCTAssertTrue(user.contains("\"rawText\""))
        XCTAssertTrue(user.contains("please open the terminal and run the build"))
    }

    // MARK: Configuration and keychain contracts

    func testConfigurationModelDefaultsToEnvironmentOverride() {
        setenv("DEEPSEEK_PROCESSOR_MODEL", "env-model-9", 1)
        defer { unsetenv("DEEPSEEK_PROCESSOR_MODEL") }
        XCTAssertEqual(DeepSeekConfiguration().model, "env-model-9")
    }

    func testConfigurationDefaultsWithoutEnvironment() {
        XCTAssertEqual(DeepSeekConfiguration().model, "deepseek-v4-flash")
        XCTAssertEqual(DeepSeekConfiguration().timeout, 5.0)
        XCTAssertEqual(DeepSeekConfiguration().maxOutputTokens, 800)
        XCTAssertEqual(DeepSeekConfiguration().thinkingEnabled, false)
        XCTAssertEqual(DeepSeekConfiguration().reasoningEffort, .low)
        XCTAssertEqual(
            DeepSeekConfiguration().baseURL,
            URL(string: "https://api.deepseek.com")
        )
    }

    // MARK: Thinking and reasoning effort

    func testReasoningEffortExposesAllDocumentedLevels() {
        XCTAssertEqual(
            DeepSeekReasoningEffort.allCases.map(\.rawValue),
            ["low", "medium", "high", "xhigh", "max"]
        )
    }

    func testThinkingEnabledEmitsEnabledToggleAndEffort() async throws {
        let journal = RequestJournal()
        let processor = makeProcessor(
            handler: { _ in (httpResponse(status: 200), envelopeJSON(validResultContent)) },
            configuration: makeConfiguration(
                thinkingEnabled: true,
                reasoningEffort: .high
            ),
            journal: journal
        )
        _ = try await processor.process(makeRequest())


        let body = try XCTUnwrap(
            requestBody(try XCTUnwrap(journal.all.first))
        )
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(
            (json["thinking"] as? [String: Any])?["type"] as? String,
            "enabled"
        )
        XCTAssertEqual(json["reasoning_effort"] as? String, "high")
    }

    func testThinkingDisabledOmitsReasoningEffortKey() async throws {
        let journal = RequestJournal()
        let processor = makeProcessor(
            handler: { _ in (httpResponse(status: 200), envelopeJSON(validResultContent)) },
            configuration: makeConfiguration(),
            journal: journal
        )
        _ = try await processor.process(makeRequest())

        let body = try XCTUnwrap(
            requestBody(try XCTUnwrap(journal.all.first))
        )
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(
            (json["thinking"] as? [String: Any])?["type"] as? String,
            "disabled"
        )
        XCTAssertNil(json["reasoning_effort"])
    }

    func testResponseCarryingReasoningContentStillParsesContent() async throws {
        let envelope: [String: Any] = [
            "choices": [
                [
                    "message": [
                        "role": "assistant",
                        "content": validResultContent,
                        "reasoning_content": "private chain of thought",
                    ],
                ],
            ],
        ]
        let envelopeData = try! JSONSerialization.data(withJSONObject: envelope)
        let journal = RequestJournal()
        let processor = makeProcessor(
            handler: { _ in (httpResponse(status: 200), envelopeData) },
            configuration: makeConfiguration(
                thinkingEnabled: true,
                reasoningEffort: .medium
            ),
            journal: journal
        )
        let result = try await processor.process(makeRequest())
        XCTAssertEqual(
            result.finalText,
            "Open the terminal and run the build."
        )
    }

    // MARK: Credential validation

    func testValidateCredentialsSucceedsOn200WithChoices() async throws {
        let journal = RequestJournal()
        let processor = makeProcessor(
            handler: { _ in (
                httpResponse(status: 200),
                envelopeJSON(validResultContent)
            ) },
            journal: journal
        )
        try await processor.validateCredentials()
        XCTAssertEqual(journal.all.count, 1)
    }

    func testValidateCredentialsFailsFastOn401WithoutRetry() async {
        let journal = RequestJournal()
        let processor = makeProcessor(
            handler: { _ in (httpResponse(status: 401), Data()) },
            journal: journal
        )
        do {
            try await processor.validateCredentials()
            XCTFail("expected failure")
        } catch ProcessorError.httpStatus(let status) {
            XCTAssertEqual(status, 401)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertEqual(journal.all.count, 1)
    }

    func testValidateCredentialsPingForcesThinkingOffAndOneToken() async throws {
        let journal = RequestJournal()
        let processor = makeProcessor(
            handler: { _ in (
                httpResponse(status: 200),
                envelopeJSON(validResultContent)
            ) },
            configuration: makeConfiguration(
                thinkingEnabled: true,
                reasoningEffort: .max
            ),
            journal: journal
        )
        try await processor.validateCredentials()

        let body = try XCTUnwrap(
            requestBody(try XCTUnwrap(journal.all.first))
        )
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(
            (json["thinking"] as? [String: Any])?["type"] as? String,
            "disabled"
        )
        XCTAssertNil(json["reasoning_effort"])
        XCTAssertNil(json["response_format"])
        XCTAssertEqual(json["max_tokens"] as? Int, 1)
    }


    /// The env override is trimmed and returned without touching the
    /// keychain at all.
    func testProcessorKeychainPrefersEnvironmentVariable() throws {
        setenv("DEEPSEEK_API_KEY", "  env-key-456  ", 1)
        defer { unsetenv("DEEPSEEK_API_KEY") }
        XCTAssertEqual(try ProcessorKeychain.read(), "env-key-456")
    }
}
