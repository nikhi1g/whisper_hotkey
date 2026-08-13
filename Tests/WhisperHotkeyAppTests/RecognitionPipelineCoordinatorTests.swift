import Foundation
import XCTest
@testable import WhisperHotkeyApp
@testable import WhisperHotkeyASR
import WhisperHotkeyCore
import WhisperHotkeySystem

final class RecognitionPipelineCoordinatorTests: XCTestCase {
    private let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    func testDefaultDeadlinesUseSafeFullSessionBudgets() {
        let defaults = RecognitionPipelineConfiguration()
        XCTAssertEqual(defaults.primaryDeadline, 120)
        XCTAssertEqual(defaults.finalTailDeadline, 30)

        let bounded = RecognitionPipelineConfiguration(
            primaryDeadline: 240,
            finalTailDeadline: 240
        )
        XCTAssertEqual(bounded.primaryDeadline, 120)
        XCTAssertEqual(bounded.finalTailDeadline, 120)
    }

    func testDeferredFinalDeliveryIsExactlyOnce() async throws {
        let events = EventBox()
        let providers = RecognitionPipelineProviders(
            primary: { _, request in
                Self.result(
                    text: "hello world",
                    words: Self.words(
                        ["hello", "world"],
                        sessionID: request.sessionID,
                        generation: request.generation,
                        decodeID: request.requestID
                    ),
                    sessionID: request.sessionID,
                    generation: request.generation
                )
            }
        )
        let coordinator = RecognitionPipelineCoordinator(
            providers: providers,
            delivery: { event in await events.append(event) }
        )
        await coordinator.beginSession(
            sessionID: sessionID,
            generation: 7,
            activationMode: .hold,
            processingMode: .afterRecording
        )
        let audio = try makeAudioFile()
        let outcome = try await coordinator.finish(audio: audio)
        await coordinator.cancel()

        let received = await events.values()
        XCTAssertEqual(received.map(\.text), ["Hello world."])
        XCTAssertEqual(received.map(\.kind), [.finalTranscript])
        XCTAssertEqual(outcome.deliveryCount, 1)
        let deliveredCount = await coordinator.deliveredEventCount
        XCTAssertEqual(deliveredCount, 1)
    }

    func testProviderNoSpeechMapsToNoSpeechDetected() async throws {
        let providers = RecognitionPipelineProviders(
            primary: { _, _ in
                throw WhisperASRError.noSpeech
            }
        )
        let coordinator = RecognitionPipelineCoordinator(providers: providers)
        await coordinator.beginSession(
            sessionID: sessionID,
            generation: 8,
            activationMode: .toggle,
            processingMode: .afterRecording
        )
        let audio = try makeAudioFile()

        do {
            _ = try await coordinator.finish(audio: audio)
            XCTFail("Expected no-speech failure.")
        } catch let error as RecognitionPipelineError {
            XCTAssertEqual(error, .noSpeechDetected)
        } catch {
            XCTFail("Expected RecognitionPipelineError, got \(error).")
        }
    }

    func testCancellationInvalidatesStaleGenerationAndCleansAudioAfterUnwind() async throws {
        let events = EventBox()
        let providers = RecognitionPipelineProviders(
            primary: { _, request in
                try await Task.sleep(for: .seconds(10))
                return Self.result(
                    text: "stale",
                    words: Self.words(
                        ["stale"],
                        sessionID: request.sessionID,
                        generation: request.generation,
                        decodeID: request.requestID
                    ),
                    sessionID: request.sessionID,
                    generation: request.generation
                )
            }
        )
        let coordinator = RecognitionPipelineCoordinator(
            providers: providers,
            configuration: RecognitionPipelineConfiguration(
                primaryDeadline: 10
            ),
            delivery: { event in await events.append(event) }
        )
        await coordinator.beginSession(
            sessionID: sessionID,
            generation: 11,
            activationMode: .toggle,
            processingMode: .afterRecording
        )
        let audio = try makeAudioFile()
        let directory = audio.url.deletingLastPathComponent()
        let finishTask = Task {
            try await coordinator.finish(audio: audio)
        }
        try await Task.sleep(for: .milliseconds(40))
        await coordinator.cancel()
        _ = try? await finishTask.value

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        let received = await events.values()
        XCTAssertTrue(received.isEmpty)
        let isActive = await coordinator.isActive
        XCTAssertFalse(isActive)
    }

    func testExpectedGenerationRejectsStaleChunkAndDeletesAudio() async throws {
        let callBox = CounterBox()
        let providers = RecognitionPipelineProviders(
            primary: { _, request in
                await callBox.increment()
                return Self.result(
                    text: "unexpected",
                    words: Self.words(
                        ["unexpected"],
                        sessionID: request.sessionID,
                        generation: request.generation,
                        decodeID: request.requestID
                    ),
                    sessionID: request.sessionID,
                    generation: request.generation
                )
            },
            streaming: { _, request in
                await callBox.increment()
                return Self.result(
                    text: "unexpected",
                    words: Self.words(
                        ["unexpected"],
                        sessionID: request.sessionID,
                        generation: request.generation,
                        decodeID: request.requestID
                    ),
                    sessionID: request.sessionID,
                    generation: request.generation
                )
            }
        )
        let coordinator = RecognitionPipelineCoordinator(providers: providers)
        await coordinator.beginSession(
            sessionID: sessionID,
            generation: 12,
            activationMode: .hold,
            processingMode: .decodeWhileSpeaking
        )
        let audio = try makeAudioFile()
        let directory = audio.url.deletingLastPathComponent()
        await coordinator.submitStreamingAudio(
            audio,
            expectedGeneration: 11
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        let pendingCount = await coordinator.pendingChunkCountForTesting
        let calls = await callBox.value()
        XCTAssertEqual(pendingCount, 0)
        XCTAssertEqual(calls, 0)
        await coordinator.cancel()
    }

    func testRejectedAndDuplicateFinishCallsDeleteUnownedAudio() async throws {
        let providers = RecognitionPipelineProviders(
            primary: { _, request in
                Self.result(
                    text: "finish",
                    words: Self.words(
                        ["finish"],
                        sessionID: request.sessionID,
                        generation: request.generation,
                        decodeID: request.requestID
                    ),
                    sessionID: request.sessionID,
                    generation: request.generation
                )
            }
        )
        let coordinator = RecognitionPipelineCoordinator(providers: providers)

        let inactiveAudio = try makeAudioFile(name: "inactive.wav")
        let inactiveTail = try makeAudioFile(name: "inactive-tail.wav")
        let inactiveDirectory = inactiveAudio.url.deletingLastPathComponent()
        let inactiveTailDirectory = inactiveTail.url.deletingLastPathComponent()
        do {
            _ = try await coordinator.finish(
                audio: inactiveAudio,
                finalTailAudio: inactiveTail
            )
            XCTFail("inactive finish should be rejected")
        } catch RecognitionPipelineError.staleGeneration {
            // Expected.
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: inactiveDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: inactiveTailDirectory.path))

        await coordinator.beginSession(
            sessionID: sessionID,
            generation: 14,
            activationMode: .hold,
            processingMode: .afterRecording
        )
        _ = try await coordinator.finish(audio: try makeAudioFile())

        let duplicateAudio = try makeAudioFile(name: "duplicate.wav")
        let duplicateTail = try makeAudioFile(name: "duplicate-tail.wav")
        let duplicateDirectory = duplicateAudio.url.deletingLastPathComponent()
        let duplicateTailDirectory = duplicateTail.url.deletingLastPathComponent()
        do {
            _ = try await coordinator.finish(
                audio: duplicateAudio,
                finalTailAudio: duplicateTail
            )
            XCTFail("duplicate finish should be rejected")
        } catch RecognitionPipelineError.staleGeneration {
            // Expected.
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: duplicateDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: duplicateTailDirectory.path))
    }

    func testFinalTailDeadlineFallsBackToFullRecording() async throws {
        let events = EventBox()
        let providers = RecognitionPipelineProviders(
            primary: { audio, request in
                if request.pass == .primaryFullSession,
                   audio.url.lastPathComponent == "tail.wav"
                {
                    try await Task.sleep(for: .seconds(10))
                }
                return Self.result(
                    text: "full recording",
                    words: Self.words(
                        ["full", "recording"],
                        sessionID: request.sessionID,
                        generation: request.generation,
                        decodeID: request.requestID
                    ),
                    sessionID: request.sessionID,
                    generation: request.generation
                )
            }
        )
        let coordinator = RecognitionPipelineCoordinator(
            providers: providers,
            configuration: RecognitionPipelineConfiguration(
                activationMode: .hold,
                processingMode: .decodeWhileSpeaking,
                primaryDeadline: 0.5,
                finalTailDeadline: 0.03
            ),
            delivery: { event in await events.append(event) }
        )
        await coordinator.beginSession(
            sessionID: sessionID,
            generation: 13,
            activationMode: .hold,
            processingMode: .decodeWhileSpeaking
        )
        let audio = try makeAudioFile(name: "full.wav")
        let tail = try makeAudioFile(name: "tail.wav")
        let outcome = try await coordinator.finish(
            audio: audio,
            finalTailAudio: tail
        )

        XCTAssertEqual(outcome.source, .fullSessionFallback)
        XCTAssertTrue(outcome.fallbackUsed)
        let received = await events.values()
        XCTAssertEqual(received.map(\.text), ["Full recording."])
    }

    func testFormatterFailureUsesCanonicalPrimaryAndVerifierFailureCannotDeliverAgain() async throws {
        let events = EventBox()
        let callBox = CounterBox()
        let providers = RecognitionPipelineProviders(
            primary: { _, request in
                Self.result(
                    text: "primary words",
                    words: Self.words(
                        ["primary", "words"],
                        sessionID: request.sessionID,
                        generation: request.generation,
                        decodeID: request.requestID
                    ),
                    sessionID: request.sessionID,
                    generation: request.generation
                )
            },
            verifier: { _, _ in
                await callBox.increment()
                throw TestError.failed
            },
            formatter: { _ in throw TestError.failed }
        )
        let coordinator = RecognitionPipelineCoordinator(
            providers: providers,
            delivery: { event in await events.append(event) }
        )
        await coordinator.beginSession(
            sessionID: sessionID,
            generation: 15,
            activationMode: .hold,
            processingMode: .afterRecording
        )
        let outcome = try await coordinator.finish(audio: try makeAudioFile())

        XCTAssertEqual(outcome.text, "primary words")
        XCTAssertFalse(outcome.formatterAccepted)
        XCTAssertEqual(outcome.repairAvailability, .disabled)
        let verifierCalls = await callBox.value()
        let received = await events.values()
        XCTAssertEqual(verifierCalls, 0)
        XCTAssertEqual(received.count, 1)
    }

    func testUncalibratedRepairIsExplicitlyDisabledAndPrimaryWins() async throws {
        let events = EventBox()
        let callBox = CounterBox()
        let providers = RecognitionPipelineProviders(
            primary: { _, request in
                Self.result(
                    text: "safe primary",
                    words: Self.words(
                        ["safe", "primary"],
                        sessionID: request.sessionID,
                        generation: request.generation,
                        decodeID: request.requestID,
                        posterior: 0.01
                    ),
                    sessionID: request.sessionID,
                    generation: request.generation
                )
            },
            verifier: { _, _ in
                await callBox.increment()
                throw TestError.failed
            }
        )
        let coordinator = RecognitionPipelineCoordinator(
            providers: providers,
            configuration: RecognitionPipelineConfiguration(
                repairPolicy: RecognitionPipelineRepairPolicy(
                    verifierEnabled: true
                )
            ),
            delivery: { event in await events.append(event) }
        )
        await coordinator.beginSession(
            sessionID: sessionID,
            generation: 17,
            activationMode: .hold,
            processingMode: .afterRecording
        )
        let outcome = try await coordinator.finish(audio: try makeAudioFile())

        XCTAssertEqual(outcome.repairAvailability, .missingCalibrationEvidence)
        XCTAssertFalse(outcome.usedVerifier)
        let verifierCalls = await callBox.value()
        XCTAssertEqual(verifierCalls, 0)
        XCTAssertEqual(outcome.text, "Safe primary.")
    }

    func testAuthorizedFusionRejectsCandidateOutsidePlannerSpan() async throws {
        let events = EventBox()
        let callBox = CounterBox()
        let baseProviders = RecognitionPipelineProviders(
            primary: { _, request in
                let result = Self.result(
                    text: "alpha beta",
                    words: Self.words(
                        ["alpha", "beta"],
                        sessionID: request.sessionID,
                        generation: request.generation,
                        decodeID: "primary",
                        posterior: 0.01
                    ),
                    sessionID: request.sessionID,
                    generation: request.generation,
                    strategy: "beam"
                )
                return result
            },
            verifier: { _, request in
                await callBox.increment()
                let outside = RecognizedWord(
                    id: StableWordID(
                        sessionID: request.sessionID,
                        providerDecodeID: "outside",
                        wordIndex: 0
                    ),
                    text: "unsafe",
                    startSeconds: 9,
                    endSeconds: 10
                )
                return Self.result(
                    text: "unsafe",
                    words: [outside],
                    sessionID: request.sessionID,
                    generation: request.generation,
                    strategy: "beam"
                )
            }
        )
        let primary = Self.result(
            text: "alpha beta",
            words: Self.words(
                ["alpha", "beta"],
                sessionID: sessionID,
                generation: 19,
                decodeID: "primary",
                posterior: 0.01
            ),
            sessionID: sessionID,
            generation: 19,
            strategy: "beam"
        )
        let key = ConfidenceCalibrationKey(result: primary)
        let examples = [
            ConfidenceCalibrationExample(key: key, rawErrorProbability: 0.01, isError: false),
            ConfidenceCalibrationExample(key: key, rawErrorProbability: 0.9, isError: true),
        ]
        let calibrator = try ConfidenceCalibrator.fitIsotonic(
            examples: examples,
            key: key,
            version: "promoted-test"
        )
        let threshold = ConfidenceThreshold.calibrated(
            0,
            artifactID: "artifact-test",
            calibrator: calibrator
        )
        let planner = UncertainSpanPlannerConfiguration(
            threshold: threshold,
            minimumRepairSpanDurationSeconds: 0.1,
            maximumRepairSpanDurationSeconds: 2,
            maximumVerifierAudioRatio: 1,
            maximumSpanCount: 2
        )
        let coordinator = RecognitionPipelineCoordinator(
            providers: baseProviders,
            configuration: RecognitionPipelineConfiguration(
                repairPolicy: RecognitionPipelineRepairPolicy(
                    calibration: RecognitionCalibrationEvidence(
                        artifactID: "artifact-test",
                        calibrator: calibrator,
                        threshold: threshold,
                        isPromoted: true
                    ),
                    plannerConfiguration: planner,
                    verifierEnabled: true
                )
            ),
            delivery: { event in await events.append(event) }
        )
        await coordinator.beginSession(
            sessionID: sessionID,
            generation: 19,
            activationMode: .hold,
            processingMode: .afterRecording
        )
        let outcome = try await coordinator.finish(audio: try makeAudioFile())

        XCTAssertEqual(outcome.repairAvailability, .enabled)
        let verifierCalls = await callBox.value()
        XCTAssertEqual(verifierCalls, 1)
        XCTAssertEqual(outcome.words.map(\.text), ["alpha", "beta"])
        let received = await events.values()
        XCTAssertEqual(received.count, 1)
    }

    func testAcceptedRepairRerunsFormattingWhenConcurrentResultHasStaleLexicalContent() async throws {
        let events = EventBox()
        let callBox = CounterBox()
        let verifierID = StableWordID(
            sessionID: sessionID,
            providerDecodeID: "verifier",
            wordIndex: 1
        )
        let primaryWords = Self.words(
            ["alpha", "beta"],
            sessionID: sessionID,
            generation: 20,
            decodeID: "primary",
            posterior: 0.01
        )
        let baseProviders = RecognitionPipelineProviders(
            primary: { _, request in
                Self.result(
                    text: "alpha beta",
                    words: Self.words(
                        ["alpha", "beta"],
                        sessionID: request.sessionID,
                        generation: request.generation,
                        decodeID: "primary",
                        posterior: 0.01
                    ),
                    sessionID: request.sessionID,
                    generation: request.generation,
                    strategy: "beam"
                )
            },
            verifier: { _, request in
                await callBox.increment()
                let candidateWords = [
                    RecognizedWord(
                        id: StableWordID(
                            sessionID: request.sessionID,
                            providerDecodeID: "verifier",
                            wordIndex: 0
                        ),
                        text: "alpha",
                        startSeconds: 0,
                        endSeconds: 0.8,
                        rawEvidence: WordEvidence(
                            posterior: 0.99,
                            availability: .posterior
                        )
                    ),
                    RecognizedWord(
                        id: verifierID,
                        text: "omega",
                        startSeconds: 0.4,
                        endSeconds: 0.9,
                        rawEvidence: WordEvidence(
                            posterior: 0.99,
                            availability: .posterior
                        )
                    ),
                    RecognizedWord(
                        id: StableWordID(
                            sessionID: request.sessionID,
                            providerDecodeID: "verifier",
                            wordIndex: 2
                        ),
                        text: "beta",
                        startSeconds: 1,
                        endSeconds: 1.8,
                        rawEvidence: WordEvidence(
                            posterior: 0.99,
                            availability: .posterior
                        )
                    ),
                ]
                return Self.result(
                    text: "alpha omega beta",
                    words: candidateWords,
                    sessionID: request.sessionID,
                    generation: request.generation,
                    strategy: "beam"
                )
            },
            formatter: { primary in
                // Simulate the formatter finishing first with an output that
                // happens to reuse the repaired IDs but still contains stale
                // primary lexical content. ID-only acceptance would select
                // this result and erase the accepted repair.
                let staleWords = [
                    primaryWords[0],
                    RecognizedWord(
                        id: verifierID,
                        text: "stale",
                        startSeconds: 0.4,
                        endSeconds: 0.9
                    ),
                    primaryWords[1],
                ]
                let stale = Self.result(
                    text: "alpha stale beta",
                    words: staleWords,
                    sessionID: primary.sessionID,
                    generation: primary.generation
                )
                return LexicallyInvariantFormatter().format(stale)
            }
        )
        let key = ConfidenceCalibrationKey(result: Self.result(
            text: "alpha beta",
            words: primaryWords,
            sessionID: sessionID,
            generation: 20,
            strategy: "beam"
        ))
        let calibrator = try ConfidenceCalibrator.fitIsotonic(
            examples: [
                ConfidenceCalibrationExample(
                    key: key,
                    rawErrorProbability: 0.01,
                    isError: false
                ),
                ConfidenceCalibrationExample(
                    key: key,
                    rawErrorProbability: 0.9,
                    isError: true
                ),
            ],
            key: key,
            version: "promoted-formatting-test"
        )
        let threshold = ConfidenceThreshold.calibrated(
            0,
            artifactID: "formatting-artifact",
            calibrator: calibrator
        )
        let planner = UncertainSpanPlannerConfiguration(
            threshold: threshold,
            minimumRepairSpanDurationSeconds: 0.1,
            maximumRepairSpanDurationSeconds: 2,
            maximumVerifierAudioRatio: 1,
            maximumSpanCount: 2
        )
        let coordinator = RecognitionPipelineCoordinator(
            providers: baseProviders,
            configuration: RecognitionPipelineConfiguration(
                repairPolicy: RecognitionPipelineRepairPolicy(
                    calibration: RecognitionCalibrationEvidence(
                        artifactID: "formatting-artifact",
                        calibrator: calibrator,
                        threshold: threshold,
                        isPromoted: true
                    ),
                    plannerConfiguration: planner,
                    verifierEnabled: true
                )
            ),
            delivery: { event in await events.append(event) }
        )
        await coordinator.beginSession(
            sessionID: sessionID,
            generation: 20,
            activationMode: .hold,
            processingMode: .afterRecording
        )

        let outcome = try await coordinator.finish(audio: try makeAudioFile())

        let verifierCalls = await callBox.value()
        XCTAssertEqual(verifierCalls, 1)
        XCTAssertTrue(outcome.usedVerifier)
        XCTAssertTrue(outcome.formatterAccepted)
        XCTAssertEqual(outcome.words.map(\.text), ["alpha", "omega", "beta"])
        XCTAssertTrue(outcome.text.localizedCaseInsensitiveContains("omega"))
        XCTAssertFalse(outcome.text.localizedCaseInsensitiveContains("stale"))
    }

    private func makeAudioFile(
        name: String = "audio.wav",
        speechPresence: WhisperSpeechPresence = .unknown
    ) throws -> WhisperAudioFile {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper-hotkey-coordinator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let url = directory.appendingPathComponent(name)
        try Data([0]).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
        return WhisperAudioFile(
            url: url,
            directoryURL: directory,
            speechPresence: speechPresence
        )
    }

    private static func words(
        _ values: [String],
        sessionID: UUID,
        generation: UInt64,
        decodeID: String,
        posterior: Double? = nil
    ) -> [RecognizedWord] {
        values.enumerated().map { index, value in
            RecognizedWord(
                id: StableWordID(
                    sessionID: sessionID,
                    providerDecodeID: decodeID,
                    wordIndex: index
                ),
                text: value,
                startSeconds: Double(index),
                endSeconds: Double(index) + 0.8,
                rawEvidence: posterior.map {
                    WordEvidence(posterior: $0, availability: .posterior)
                } ?? .unavailable
            )
        }
    }

    private static func result(
        text: String,
        words: [RecognizedWord],
        sessionID: UUID,
        generation: UInt64,
        strategy: String? = nil
    ) -> RecognitionResult {
        RecognitionResult(
            sessionID: sessionID,
            generation: generation,
            engine: .whisperTurbo,
            model: ModelIdentity(identifier: "test-model"),
            text: text,
            words: words,
            timing: RecognitionTiming(
                audioDurationSeconds: max(1, words.last?.endSeconds ?? 1)
            ),
            passMetadata: RecognitionPassMetadata(strategy: strategy)
        )
    }
}

private actor EventBox {
    private var events: [RecognitionPipelineDelivery] = []

    func append(_ event: RecognitionPipelineDelivery) {
        events.append(event)
    }

    func values() -> [RecognitionPipelineDelivery] { events }
}

private actor CounterBox {
    private var count = 0

    func increment() { count += 1 }
    func value() -> Int { count }
}

private enum TestError: Error {
    case failed
}
