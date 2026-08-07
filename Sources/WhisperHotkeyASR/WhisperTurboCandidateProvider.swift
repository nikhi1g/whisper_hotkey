import Foundation
import WhisperHotkeyCore

public actor WhisperTurboCandidateProvider: RecognitionCandidateProvider {
    private let recognizer: WhisperRecognizer

    public nonisolated let capabilities: RecognitionCapabilities

    public init(
        configuration: WhisperRuntimeConfiguration? = nil
    ) {
        recognizer = WhisperRecognizer(configuration: configuration)
        capabilities = [
            .prompt,
            .beamSearch,
            .tokenConfidence,
            .tokenTimestamps,
            .segmentTimestamps,
            .fullContext,
            .windowedDecode,
        ]
    }

    public func primaryHypothesis(
        request: RecognitionRequest
    ) async throws -> RecognitionHypothesis {
        try await transcribe(
            request,
            pass: .primaryFullSession
        )
    }

    public func alternateHypothesis(
        request: AlternateRecognitionRequest
    ) async throws -> RecognitionHypothesis {
        try await transcribe(
            request.base,
            pass: request.pass
        )
    }

    private func transcribe(
        _ request: RecognitionRequest,
        pass: RecognitionPassKind
    ) async throws -> RecognitionHypothesis {
        let originalStrategy = request.strategy
        let strategy: WhisperDecodingStrategy
        switch originalStrategy {
        case .adaptive:
            strategy = .adaptive
        case .greedy:
            strategy = .greedy
        case .beam:
            strategy = .beam
        }
        let audio = WhisperAudioFile(
            url: request.audioURL,
            directoryURL: request.audioURL.deletingLastPathComponent(),
            fileManager: .default,
            speechPresence: .unknown
        )
        return try await recognizer.transcribeHypothesis(
            audio,
            prompt: request.prompt,
            pass: pass,
            strategy: strategy,
            beamSize: request.beamSize,
            protocolVersion: request.protocolVersion,
            requestID: request.requestID,
            sampleStart: request.window.startSample,
            sampleEnd: request.window.endSample,
            emitMetadata: request.emitTokenData || request.emitTimestamps,
            preserveAudio: true
        )
    }
}
