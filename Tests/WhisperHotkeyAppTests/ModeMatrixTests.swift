import Foundation
import XCTest
@testable import WhisperHotkeyApp
@testable import WhisperHotkeyASR
import WhisperHotkeyCore
import WhisperHotkeySystem

final class ModeMatrixTests: XCTestCase {
    func testEveryProcessingModePreparesSelectedModelDuringCapture() async {
        for mode in ModelProcessingMode.allCases {
            let counter = PreparationCounter()
            let providers = RecognitionPipelineProviders(
                primary: { _, request in
                    RecognitionResult(
                        sessionID: request.sessionID,
                        generation: request.generation,
                        engine: .parakeetUnifiedCoreML,
                        text: "ready"
                    )
                },
                preparePrimary: { await counter.increment() }
            )
            let coordinator = RecognitionPipelineCoordinator(
                providers: providers,
                configuration: RecognitionPipelineConfiguration(
                    activationMode: .toggle,
                    processingMode: mode
                ),
                delivery: { _ in }
            )

            await coordinator.beginSession(
                generation: UInt64(mode.hashValue.magnitude + 1),
                activationMode: .toggle,
                processingMode: mode
            )

            let preparationCount = await counter.value()
            XCTAssertEqual(
                preparationCount,
                1,
                "\(mode) must hide model cold-start behind recording time."
            )
            await coordinator.cancel()
        }
    }

    @MainActor
    func testToggleFinalDeliveryTransitionsThroughInsertionAndClosesSession() {
        var machine = DictationStateMachine()
        _ = machine.handle(.hotkeyPressed(at: 1))
        _ = machine.handle(.captureStarted)
        _ = machine.handle(.hotkeyReleased(at: 2))
        XCTAssertEqual(machine.phase, .transcribing)

        let event = RecognitionPipelineDelivery(
            kind: .finalTranscript,
            text: "toggle result",
            sessionID: UUID(),
            generation: 42
        )
        let disposition = WhisperHotkeyApplicationDelegate
            .pipelineDeliveryDisposition(
                event,
                currentGeneration: 42,
                phase: machine.phase,
                isPauseMode: false,
                isTerminating: false
            )
        XCTAssertEqual(disposition, .finalTranscript("toggle result"))

        XCTAssertEqual(
            machine.handle(.transcriptReady),
            [.deliverTranscript]
        )
        XCTAssertEqual(machine.phase, .inserting)
        XCTAssertEqual(
            machine.handle(.deliveryFinished),
            [.showBadge(.hidden)]
        )
        XCTAssertEqual(machine.phase, .idle)

        XCTAssertEqual(
            WhisperHotkeyApplicationDelegate.pipelineDeliveryDisposition(
                event,
                currentGeneration: 43,
                phase: .transcribing,
                isPauseMode: false,
                isTerminating: false
            ),
            .ignore,
            "A stale callback must not paste or alter badge state."
        )
        XCTAssertEqual(
            WhisperHotkeyApplicationDelegate.pipelineDeliveryDisposition(
                event,
                currentGeneration: 42,
                phase: .listening,
                isPauseMode: false,
                isTerminating: false
            ),
            .ignore,
            "Only Pause Mode may deliver while capture is still active."
        )
    }

    func testAllNineActivationAndProcessingCombinationsDeliverOnce() async throws {
        let activations: [HotkeyActivationMode] = [.hold, .toggle, .pause]
        let processing: [ModelProcessingMode] = [
            .afterRecording,
            .modelReady,
            .decodeWhileSpeaking,
        ]

        for activation in activations {
            for mode in processing {
                let events = MatrixEvents()
                let providers = RecognitionPipelineProviders(
                    primary: { _, request in
                        let words = ["matrix", request.pass.rawValue].enumerated().map {
                            index, text in
                            RecognizedWord(
                                id: StableWordID(
                                    sessionID: request.sessionID,
                                    providerDecodeID: request.requestID,
                                    wordIndex: index
                                ),
                                text: text,
                                startSeconds: Double(index),
                                endSeconds: Double(index) + 0.5
                            )
                        }
                        return RecognitionResult(
                            sessionID: request.sessionID,
                            generation: request.generation,
                            engine: .whisperTurbo,
                            model: ModelIdentity(identifier: "matrix"),
                            text: words.map(\.text).joined(separator: " "),
                            words: words,
                            timing: RecognitionTiming(audioDurationSeconds: 2),
                            passMetadata: RecognitionPassMetadata(strategy: "beam")
                        )
                    }
                )
                let coordinator = RecognitionPipelineCoordinator(
                    providers: providers,
                    configuration: RecognitionPipelineConfiguration(
                        activationMode: activation,
                        processingMode: mode
                    ),
                    delivery: { event in await events.append(event) }
                )
                await coordinator.beginSession(
                    sessionID: UUID(),
                    generation: UInt64(activations.firstIndex(of: activation)! * 3
                        + processing.firstIndex(of: mode)! + 1),
                    activationMode: activation,
                    processingMode: mode
                )
                let audio = try makeAudioFile()
                let outcome = try await coordinator.finish(audio: audio)
                let received = await events.values()

                XCTAssertFalse(outcome.text.isEmpty, "(activation)/(mode)")
                XCTAssertEqual(received.count, 1, "(activation)/(mode)")
                XCTAssertEqual(received[0].kind, .finalTranscript, "(activation)/(mode)")
                XCTAssertEqual(outcome.deliveryCount, 1, "(activation)/(mode)")
            }
        }
    }

    func testPauseModeDeliversWholeSentencesImmediatelyAndNeverDeliversPartialTail() async throws {
        let events = MatrixEvents()
        let providers = RecognitionPipelineProviders(
            primary: { audio, request in
                let isTail = audio.url.lastPathComponent == "tail.wav"
                let values = isTail
                    ? ["tail", "sentence"]
                    : ["whole", "sentence"]
                let words = values.enumerated().map { index, text in
                    RecognizedWord(
                        id: StableWordID(
                            sessionID: request.sessionID,
                            providerDecodeID: request.requestID,
                            wordIndex: index
                        ),
                        text: text,
                        startSeconds: Double(index) + (isTail ? 2 : 0),
                        endSeconds: Double(index) + (isTail ? 2.5 : 0.5)
                    )
                }
                return RecognitionResult(
                    sessionID: request.sessionID,
                    generation: request.generation,
                    engine: .whisperTurbo,
                    model: ModelIdentity(identifier: "pause"),
                    text: values.joined(separator: " "),
                    words: words,
                    timing: RecognitionTiming(audioDurationSeconds: 2),
                    passMetadata: RecognitionPassMetadata(strategy: "beam")
                )
            }
        )
        let coordinator = RecognitionPipelineCoordinator(
            providers: providers,
            configuration: RecognitionPipelineConfiguration(
                activationMode: .pause,
                processingMode: .decodeWhileSpeaking
            ),
            delivery: { event in await events.append(event) }
        )
        let sessionID = UUID()
        await coordinator.beginSession(
            sessionID: sessionID,
            generation: 21,
            activationMode: .pause,
            processingMode: .decodeWhileSpeaking
        )

        let chunkWords = ["whole", "sentence"].enumerated().map { index, text in
            RecognizedWord(
                id: StableWordID(
                    sessionID: sessionID,
                    providerDecodeID: "chunk",
                    wordIndex: index
                ),
                text: text,
                startSeconds: Double(index),
                endSeconds: Double(index) + 0.5
            )
        }
        _ = await coordinator.appendStreamingResult(
            RecognitionResult(
                sessionID: sessionID,
                generation: 21,
                engine: .whisperTurbo,
                text: "whole sentence",
                words: chunkWords,
                completeness: .completeSentence
            )
        )
        let afterSentence = await events.values()
        XCTAssertEqual(afterSentence.map(\.kind), [.pauseSentence])
        XCTAssertEqual(afterSentence.map(\.text), ["whole sentence"])

        let partialWords = [
            RecognizedWord(
                id: StableWordID(
                    sessionID: sessionID,
                    providerDecodeID: "partial",
                    wordIndex: 0
                ),
                text: "revisable",
                startSeconds: 2,
                endSeconds: 2.4
            )
        ]
        _ = await coordinator.appendStreamingResult(
            RecognitionResult(
                sessionID: sessionID,
                generation: 21,
                engine: .whisperTurbo,
                text: "revisable",
                words: partialWords,
                completeness: .provisional
            )
        )
        let afterPartial = await events.values()
        XCTAssertEqual(afterPartial.map(\.kind), [.pauseSentence])
        XCTAssertEqual(afterPartial.map(\.text), ["whole sentence"])

        let outcome = try await coordinator.finish(
            audio: try makeAudioFile(),
            finalTailAudio: try makeAudioFile(name: "tail.wav")
        )
        let received = await events.values()
        XCTAssertEqual(outcome.deliveryCount, received.count)
        XCTAssertEqual(received.map(\.kind), [.pauseSentence, .finalTranscript])
        XCTAssertEqual(received.map(\.text), ["whole sentence", "tail sentence."])
        XCTAssertFalse(received.contains { $0.text == "revisable" })
    }

    private func makeAudioFile(name: String = "audio.wav") throws -> WhisperAudioFile {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper-hotkey-mode-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let url = directory.appendingPathComponent(name)
        try Data([0]).write(to: url)
        return WhisperAudioFile(url: url, directoryURL: directory)
    }
}

private actor MatrixEvents {
    private var events: [RecognitionPipelineDelivery] = []
    func append(_ event: RecognitionPipelineDelivery) { events.append(event) }
    func values() -> [RecognitionPipelineDelivery] { events }
}

private actor PreparationCounter {
    private var count = 0
    func increment() { count += 1 }
    func value() -> Int { count }
}
