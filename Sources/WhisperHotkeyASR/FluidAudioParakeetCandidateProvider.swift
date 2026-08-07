import Foundation
import WhisperHotkeyCore

public actor FluidAudioParakeetCandidateProvider: RecognitionCandidateProvider {
    private let runtime: ParakeetRuntime
    public let variant: ParakeetVariant
    public nonisolated let capabilities: RecognitionCapabilities

    public init(variant: ParakeetVariant) {
        self.variant = variant
        self.runtime = ParakeetRuntime(variant: variant)
        capabilities = [
            .fullContext,
            .segmentTimestamps
        ]
    }

    public func primaryHypothesis(
        request: RecognitionRequest
    ) async throws -> RecognitionHypothesis {
        try await transcribe(request, pass: .primaryFullSession)
    }

    public func alternateHypothesis(
        request: AlternateRecognitionRequest
    ) async throws -> RecognitionHypothesis {
        try await transcribe(request.base, pass: request.pass)
    }

    private func transcribe(
        _ request: RecognitionRequest,
        pass: RecognitionPassKind
    ) async throws -> RecognitionHypothesis {
        let text = try await runtime.transcribe(audioURL: request.audioURL)
        return RecognitionHypothesis(
            engine: variant.candidateEngineID,
            pass: pass,
            window: request.window,
            text: text,
            segments: [],
            sequenceScore: nil,
            averageLogProbability: nil,
            noSpeechProbability: nil,
            repetitionDetected: false,
            modelID: variant.rawValue,
            engineVersion: "FluidAudio"
        )
    }
}
