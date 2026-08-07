import Foundation

public enum RecognitionEngineID: String, Codable, Sendable, CaseIterable {
    case whisperTurbo
    case parakeetTDTCoreML
    case parakeetUnifiedCoreML
    case parakeetCppTDT
}

public enum RecognitionPassKind: String, Codable, Sendable {
    case provisional
    case primaryFullSession
    case alternateWindow
    case uncertaintyRetry
    case secondaryVerifier
}

public struct RecognitionWindow: Codable, Hashable, Sendable {
    public let startSample: Int64
    public let endSample: Int64
    public let sampleRate: Int

    public init(startSample: Int64, endSample: Int64, sampleRate: Int = 16_000) {
        precondition(sampleRate > 0)
        precondition(startSample >= 0)
        precondition(endSample >= startSample)
        self.startSample = startSample
        self.endSample = endSample
        self.sampleRate = sampleRate
    }

    public var startSeconds: Double { Double(startSample) / Double(sampleRate) }
    public var endSeconds: Double { Double(endSample) / Double(sampleRate) }
    public var durationSeconds: Double { max(0, endSeconds - startSeconds) }
}

public struct TimedWord: Codable, Hashable, Sendable {
    public let text: String
    public let startSeconds: Double?
    public let endSeconds: Double?
    public let confidence: Double?

    public init(
        text: String,
        startSeconds: Double? = nil,
        endSeconds: Double? = nil,
        confidence: Double? = nil
    ) {
        self.text = text
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.confidence = confidence
    }
}

public struct TimedSegment: Codable, Hashable, Sendable {
    public let startSeconds: Double
    public let endSeconds: Double
    public let text: String
    public let words: [TimedWord]

    public init(
        startSeconds: Double,
        endSeconds: Double,
        text: String,
        words: [TimedWord] = []
    ) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.text = text
        self.words = words
    }
}

public struct RecognitionHypothesis: Codable, Hashable, Sendable {
    public let id: UUID
    public let engine: RecognitionEngineID
    public let pass: RecognitionPassKind
    public let window: RecognitionWindow
    public let text: String
    public let words: [TimedWord]
    public let segments: [TimedSegment]
    public let sequenceScore: Double?
    public let averageLogProbability: Double?
    public let noSpeechProbability: Double?
    public let repetitionDetected: Bool
    public let weakTokenFraction: Double?
    public let adaptiveFallback: Bool
    public let modelID: String?
    public let engineVersion: String?
    public let metadata: [String: String]
    public let latencyMilliseconds: Double?

    public init(
        id: UUID = UUID(),
        engine: RecognitionEngineID,
        pass: RecognitionPassKind,
        window: RecognitionWindow,
        text: String,
        words: [TimedWord] = [],
        segments: [TimedSegment] = [],
        sequenceScore: Double? = nil,
        averageLogProbability: Double? = nil,
        noSpeechProbability: Double? = nil,
        weakTokenFraction: Double? = nil,
        repetitionDetected: Bool = false,
        adaptiveFallback: Bool = false,
        modelID: String? = nil,
        engineVersion: String? = nil,
        metadata: [String: String] = [:],
        latencyMilliseconds: Double? = nil
    ) {
        self.id = id
        self.engine = engine
        self.pass = pass
        self.window = window
        self.text = text
        self.words = words
        self.segments = segments
        self.sequenceScore = sequenceScore
        self.averageLogProbability = averageLogProbability
        self.noSpeechProbability = noSpeechProbability
        self.weakTokenFraction = weakTokenFraction
        self.repetitionDetected = repetitionDetected
        self.adaptiveFallback = adaptiveFallback
        self.modelID = modelID
        self.engineVersion = engineVersion
        self.metadata = metadata
        self.latencyMilliseconds = latencyMilliseconds
    }

    public var normalizedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct RecognitionEvidence: Codable, Hashable, Sendable {
    public let baseline: RecognitionHypothesis
    public let candidates: [RecognitionHypothesis]

    public init(
        baseline: RecognitionHypothesis,
        candidates: [RecognitionHypothesis]
    ) {
        self.baseline = baseline
        self.candidates = candidates
    }
}

public struct TranscriptDecisionTrace: Codable, Hashable, Sendable {
    public let selectedHypothesisID: UUID
    public let candidateCount: Int
    public let rejectionReasons: [String]

    public init(
        selectedHypothesisID: UUID,
        candidateCount: Int,
        rejectionReasons: [String] = []
    ) {
        self.selectedHypothesisID = selectedHypothesisID
        self.candidateCount = candidateCount
        self.rejectionReasons = rejectionReasons
    }
}

public struct UncertainSpan: Codable, Hashable, Sendable {
    public let startSample: Int64
    public let endSample: Int64
    public let sampleRate: Int
    public let score: Double

    public init(
        startSample: Int64,
        endSample: Int64,
        sampleRate: Int = 16_000,
        score: Double
    ) {
        precondition(sampleRate > 0)
        precondition(startSample >= 0)
        precondition(endSample >= startSample)
        precondition(score.isFinite)
        self.startSample = startSample
        self.endSample = endSample
        self.sampleRate = sampleRate
        self.score = score
    }

    public var startSeconds: Double { Double(startSample) / Double(sampleRate) }
    public var endSeconds: Double { Double(endSample) / Double(sampleRate) }
}

public struct RecognitionCapabilities: OptionSet, Sendable, Codable {
    public let rawValue: UInt32

    public static let prompt = Self(rawValue: 1 << 0)
    public static let beamSearch = Self(rawValue: 1 << 1)
    public static let tokenConfidence = Self(rawValue: 1 << 2)
    public static let tokenTimestamps = Self(rawValue: 1 << 3)
    public static let segmentTimestamps = Self(rawValue: 1 << 4)
    public static let fullContext = Self(rawValue: 1 << 5)
    public static let windowedDecode = Self(rawValue: 1 << 6)

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}
