import Foundation
import WhisperHotkeyCore

public enum RecognitionDecodeStrategy: String, Sendable, Codable {
    case beam
    case greedy
    case adaptive
}

public struct RecognitionRequest: Sendable {
    public let requestID: String
    public let audioURL: URL
    public let prompt: String?
    public let window: RecognitionWindow
    public let strategy: RecognitionDecodeStrategy
    public let beamSize: Int
    public let emitTokenData: Bool
    public let emitTimestamps: Bool
    public let protocolVersion: Int

    public init(
        requestID: String = UUID().uuidString,
        audioURL: URL,
        prompt: String? = nil,
        window: RecognitionWindow,
        strategy: RecognitionDecodeStrategy = .beam,
        beamSize: Int = 5,
        emitTokenData: Bool = false,
        emitTimestamps: Bool = false,
        protocolVersion: Int = 1
    ) {
        self.requestID = requestID
        self.audioURL = audioURL
        self.prompt = prompt
        self.window = window
        self.strategy = strategy
        self.beamSize = beamSize
        self.emitTokenData = emitTokenData
        self.emitTimestamps = emitTimestamps
        self.protocolVersion = protocolVersion
    }
}

public struct AlternateRecognitionRequest: Sendable {
    public let base: RecognitionRequest
    public let pass: RecognitionPassKind

    public init(base: RecognitionRequest, pass: RecognitionPassKind) {
        self.base = base
        self.pass = pass
    }
}

public enum RecognitionCandidateProviderError: LocalizedError, Equatable {
    case unsupportedPass

    public var errorDescription: String? {
        switch self {
        case .unsupportedPass:
            "Requested pass is not supported by this provider."
        }
    }
}

public protocol RecognitionCandidateProvider: Sendable {
    var capabilities: RecognitionCapabilities { get }

    func primaryHypothesis(request: RecognitionRequest) async throws
        -> RecognitionHypothesis

    func alternateHypothesis(
        request: AlternateRecognitionRequest
    ) async throws -> RecognitionHypothesis
}
