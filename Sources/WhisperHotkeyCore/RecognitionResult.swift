import Foundation

/// A deterministic identity for a word emitted by one provider decode.
///
/// The identity is independent of rendered text.  A replacement word keeps a
/// provenance edge to the word it replaces instead of silently reusing its
/// identifier.
public struct StableWordID: Codable, Hashable, Sendable, CustomStringConvertible {
    public let sessionID: UUID
    public let providerDecodeID: String
    public let wordIndex: Int

    public init(
        sessionID: UUID,
        providerDecodeID: String,
        wordIndex: Int
    ) {
        precondition(!providerDecodeID.isEmpty)
        precondition(wordIndex >= 0)
        self.sessionID = sessionID
        self.providerDecodeID = providerDecodeID
        self.wordIndex = wordIndex
    }

    /// A stable, human-readable key for in-memory maps and traces.
    /// Codable identity remains the three structured fields above.
    public var rawValue: String {
        "\(sessionID.uuidString.lowercased())/\(providerDecodeID)/\(wordIndex)"
    }

    public var description: String { rawValue }

    private enum CodingKeys: String, CodingKey {
        case sessionID = "sessionId"
        case providerDecodeID = "providerDecodeId"
        case wordIndex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sessionID = try container.decode(UUID.self, forKey: .sessionID)
        let providerDecodeID = try RecognitionCoding.decodeString(
            from: container,
            forKey: .providerDecodeID,
            field: "word.id.provider_decode_id",
            limits: decoder.recognitionDecodingLimits
        )
        let wordIndex = try container.decode(Int.self, forKey: .wordIndex)
        guard !providerDecodeID.isEmpty, wordIndex >= 0 else {
            throw RecognitionContractError.malformed("invalid stable word ID")
        }
        self.init(
            sessionID: sessionID,
            providerDecodeID: providerDecodeID,
            wordIndex: wordIndex
        )
    }
}

public enum DecodeCompleteness: String, Codable, Hashable, Sendable {
    case provisional
    case stablePrefix
    case completeSentence
    case finalSession
    case truncated
    case failed
}

public enum WordLockState: String, Codable, Hashable, Sendable {
    case unlocked
    case locked
    case protected
}

public enum WordProvenanceKind: String, Codable, Hashable, Sendable {
    case primary
    case alternate
    case replacement
    case fused
    case migrated
}

/// The source edge retained when a provider word is replaced or fused.
public struct WordProvenance: Codable, Hashable, Sendable {
    public let kind: WordProvenanceKind
    public let sourceWordIDs: [StableWordID]
    public let providerDecodeID: String?
    public let providerWordIndex: Int?
    public let reason: String?

    public init(
        kind: WordProvenanceKind,
        sourceWordIDs: [StableWordID] = [],
        providerDecodeID: String? = nil,
        providerWordIndex: Int? = nil,
        reason: String? = nil
    ) {
        precondition(providerWordIndex == nil || providerWordIndex! >= 0)
        self.kind = kind
        self.sourceWordIDs = sourceWordIDs
        self.providerDecodeID = providerDecodeID
        self.providerWordIndex = providerWordIndex
        self.reason = reason
    }

    public static func primary(
        providerDecodeID: String,
        wordIndex: Int
    ) -> Self {
        Self(
            kind: .primary,
            providerDecodeID: providerDecodeID,
            providerWordIndex: wordIndex
        )
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case sourceWordIDs = "sourceWordIds"
        case providerDecodeID = "providerDecodeId"
        case providerWordIndex = "providerWordIndex"
        case reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let limits = decoder.recognitionDecodingLimits
        let sourceWordIDs = try RecognitionCoding.decodeArray(
            StableWordID.self,
            from: container,
            forKey: .sourceWordIDs,
            field: "word.provenance.source_word_ids",
            maximum: limits.maxProvenanceIDs,
            limits: limits
        )
        let providerDecodeID = try RecognitionCoding.decodeOptionalString(
            from: container,
            forKey: .providerDecodeID,
            field: "word.provenance.provider_decode_id",
            limits: limits
        )
        let providerWordIndex = try container.decodeIfPresent(
            Int.self,
            forKey: .providerWordIndex
        )
        guard providerWordIndex == nil || providerWordIndex! >= 0 else {
            throw RecognitionContractError.malformed("negative provider word index")
        }
        let reason = try RecognitionCoding.decodeOptionalString(
            from: container,
            forKey: .reason,
            field: "word.provenance.reason",
            limits: limits
        )
        self.init(
            kind: try container.decode(WordProvenanceKind.self, forKey: .kind),
            sourceWordIDs: sourceWordIDs,
            providerDecodeID: providerDecodeID,
            providerWordIndex: providerWordIndex,
            reason: reason
        )
    }
}

/// Provenance for an alternative or a result-level fusion operation.
public struct RecognitionProvenance: Codable, Hashable, Sendable {
    public let sourceWordIDs: [StableWordID]
    public let sourceAlternativeIDs: [UUID]
    public let reason: String?

    public init(
        sourceWordIDs: [StableWordID] = [],
        sourceAlternativeIDs: [UUID] = [],
        reason: String? = nil
    ) {
        self.sourceWordIDs = sourceWordIDs
        self.sourceAlternativeIDs = sourceAlternativeIDs
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey {
        case sourceWordIDs = "sourceWordIds"
        case sourceAlternativeIDs = "sourceAlternativeIds"
        case reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let limits = decoder.recognitionDecodingLimits
        self.init(
            sourceWordIDs: try RecognitionCoding.decodeArray(
                StableWordID.self,
                from: container,
                forKey: .sourceWordIDs,
                field: "provenance.source_word_ids",
                maximum: limits.maxProvenanceIDs,
                limits: limits
            ),
            sourceAlternativeIDs: try RecognitionCoding.decodeArray(
                UUID.self,
                from: container,
                forKey: .sourceAlternativeIDs,
                field: "provenance.source_alternative_ids",
                maximum: limits.maxProvenanceIDs,
                limits: limits
            ),
            reason: try RecognitionCoding.decodeOptionalString(
                from: container,
                forKey: .reason,
                field: "provenance.reason",
                limits: limits
            )
        )
    }
}

public struct ModelIdentity: Codable, Hashable, Sendable {
    public let identifier: String
    public let version: String?
    public let revision: String?
    public let quantization: String?
    public let computeUnits: String?

    public init(
        identifier: String,
        version: String? = nil,
        revision: String? = nil,
        quantization: String? = nil,
        computeUnits: String? = nil
    ) {
        precondition(!identifier.isEmpty)
        self.identifier = identifier
        self.version = version
        self.revision = revision
        self.quantization = quantization
        self.computeUnits = computeUnits
    }

    public static let unknown = Self(identifier: "unknown")

    /// Compatibility spelling used by adapters that still expose `modelID`.
    public var modelID: String { identifier }

    private enum CodingKeys: String, CodingKey {
        case identifier
        case version
        case revision
        case quantization
        case computeUnits
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let limits = decoder.recognitionDecodingLimits
        let identifier = try RecognitionCoding.decodeString(
            from: container,
            forKey: .identifier,
            field: "model.identifier",
            limits: limits
        )
        guard !identifier.isEmpty else {
            throw RecognitionContractError.malformed("empty model identifier")
        }
        self.init(
            identifier: identifier,
            version: try RecognitionCoding.decodeOptionalString(
                from: container,
                forKey: .version,
                field: "model.version",
                limits: limits
            ),
            revision: try RecognitionCoding.decodeOptionalString(
                from: container,
                forKey: .revision,
                field: "model.revision",
                limits: limits
            ),
            quantization: try RecognitionCoding.decodeOptionalString(
                from: container,
                forKey: .quantization,
                field: "model.quantization",
                limits: limits
            ),
            computeUnits: try RecognitionCoding.decodeOptionalString(
                from: container,
                forKey: .computeUnits,
                field: "model.compute_units",
                limits: limits
            )
        )
    }
}

public struct WordEvidenceAvailability: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let tokenIDs = Self(rawValue: 1 << 0)
    public static let tokenLogProbabilities = Self(rawValue: 1 << 1)
    public static let posterior = Self(rawValue: 1 << 2)
    public static let entropy = Self(rawValue: 1 << 3)
    public static let beamScore = Self(rawValue: 1 << 4)
    public static let beamRank = Self(rawValue: 1 << 5)
    public static let timing = Self(rawValue: 1 << 6)
}

/// Raw provider evidence. Missing values remain missing; adapters must not
/// synthesize confidence from fields the provider did not expose.
public struct WordEvidence: Codable, Hashable, Sendable {
    public let tokenIDs: [Int]
    public let tokenLogProbabilities: [Double]
    public let posterior: Double?
    public let entropy: Double?
    public let beamScore: Double?
    public let beamRank: Int?
    public let availability: WordEvidenceAvailability

    public init(
        tokenIDs: [Int] = [],
        tokenLogProbabilities: [Double] = [],
        posterior: Double? = nil,
        entropy: Double? = nil,
        beamScore: Double? = nil,
        beamRank: Int? = nil,
        availability: WordEvidenceAvailability = []
    ) {
        precondition(beamRank == nil || beamRank! >= 0)
        self.tokenIDs = tokenIDs
        self.tokenLogProbabilities = tokenLogProbabilities
        self.posterior = posterior
        self.entropy = entropy
        self.beamScore = beamScore
        self.beamRank = beamRank
        self.availability = availability
    }

    public static let unavailable = Self()

    private enum CodingKeys: String, CodingKey {
        case tokenIDs = "tokenIds"
        case tokenLogProbabilities
        case posterior
        case entropy
        case beamScore
        case beamRank
        case availability
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let limits = decoder.recognitionDecodingLimits
        let tokenIDs = try RecognitionCoding.decodeArray(
            Int.self,
            from: container,
            forKey: .tokenIDs,
            field: "word.evidence.token_ids",
            maximum: limits.maxTokensPerWord,
            limits: limits
        )
        let tokenLogProbabilities = try RecognitionCoding.decodeArray(
            Double.self,
            from: container,
            forKey: .tokenLogProbabilities,
            field: "word.evidence.token_log_probabilities",
            maximum: limits.maxTokenLogProbabilitiesPerWord,
            limits: limits
        )
        let posterior = try container.decodeIfPresent(Double.self, forKey: .posterior)
        let entropy = try container.decodeIfPresent(Double.self, forKey: .entropy)
        let beamScore = try container.decodeIfPresent(Double.self, forKey: .beamScore)
        let beamRank = try container.decodeIfPresent(Int.self, forKey: .beamRank)
        guard beamRank == nil || beamRank! >= 0 else {
            throw RecognitionContractError.malformed("negative word beam rank")
        }
        let value = Self(
            tokenIDs: tokenIDs,
            tokenLogProbabilities: tokenLogProbabilities,
            posterior: posterior,
            entropy: entropy,
            beamScore: beamScore,
            beamRank: beamRank,
            availability: try container.decodeIfPresent(
                WordEvidenceAvailability.self,
                forKey: .availability
            ) ?? []
        )
        try RecognitionCoding.validateWordEvidence(value, limits: limits)
        self = value
    }
}

public struct UtteranceEvidence: Codable, Hashable, Sendable {
    public let sequenceScore: Double?
    public let averageLogProbability: Double?
    public let noSpeechProbability: Double?
    public let maximumNoSpeechProbability: Double?
    public let weakTokenFraction: Double?
    public let repetitionDetected: Bool
    public let truncated: Bool
    public let temperature: Double?
    public let fallbackTemperatures: [Double]

    public init(
        sequenceScore: Double? = nil,
        averageLogProbability: Double? = nil,
        noSpeechProbability: Double? = nil,
        maximumNoSpeechProbability: Double? = nil,
        weakTokenFraction: Double? = nil,
        repetitionDetected: Bool = false,
        truncated: Bool = false,
        temperature: Double? = nil,
        fallbackTemperatures: [Double] = []
    ) {
        self.sequenceScore = sequenceScore
        self.averageLogProbability = averageLogProbability
        self.noSpeechProbability = noSpeechProbability
        self.maximumNoSpeechProbability = maximumNoSpeechProbability
        self.weakTokenFraction = weakTokenFraction
        self.repetitionDetected = repetitionDetected
        self.truncated = truncated
        self.temperature = temperature
        self.fallbackTemperatures = fallbackTemperatures
    }

    public static let unavailable = Self()

    private enum CodingKeys: String, CodingKey {
        case sequenceScore
        case averageLogProbability
        case noSpeechProbability
        case maximumNoSpeechProbability
        case weakTokenFraction
        case repetitionDetected
        case truncated
        case temperature
        case fallbackTemperatures
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let limits = decoder.recognitionDecodingLimits
        let fallbackTemperatures = try RecognitionCoding.decodeArray(
            Double.self,
            from: container,
            forKey: .fallbackTemperatures,
            field: "evidence.fallback_temperatures",
            maximum: limits.maxFallbackTemperatures,
            limits: limits
        )
        let value = Self(
            sequenceScore: try container.decodeIfPresent(Double.self, forKey: .sequenceScore),
            averageLogProbability: try container.decodeIfPresent(
                Double.self,
                forKey: .averageLogProbability
            ),
            noSpeechProbability: try container.decodeIfPresent(
                Double.self,
                forKey: .noSpeechProbability
            ),
            maximumNoSpeechProbability: try container.decodeIfPresent(
                Double.self,
                forKey: .maximumNoSpeechProbability
            ),
            weakTokenFraction: try container.decodeIfPresent(
                Double.self,
                forKey: .weakTokenFraction
            ),
            repetitionDetected: try container.decodeIfPresent(
                Bool.self,
                forKey: .repetitionDetected
            ) ?? false,
            truncated: try container.decodeIfPresent(Bool.self, forKey: .truncated) ?? false,
            temperature: try container.decodeIfPresent(Double.self, forKey: .temperature),
            fallbackTemperatures: fallbackTemperatures
        )
        try RecognitionCoding.validateUtteranceEvidence(value)
        self = value
    }
}

public struct RecognitionTiming: Codable, Hashable, Sendable {
    public let audioDurationSeconds: Double?
    public let decodeDurationSeconds: Double?
    public let firstWordStartSeconds: Double?
    public let lastWordEndSeconds: Double?

    public init(
        audioDurationSeconds: Double? = nil,
        decodeDurationSeconds: Double? = nil,
        firstWordStartSeconds: Double? = nil,
        lastWordEndSeconds: Double? = nil
    ) {
        self.audioDurationSeconds = audioDurationSeconds
        self.decodeDurationSeconds = decodeDurationSeconds
        self.firstWordStartSeconds = firstWordStartSeconds
        self.lastWordEndSeconds = lastWordEndSeconds
    }

    public static let unavailable = Self()

    public var audioDuration: Duration? {
        audioDurationSeconds.map(Duration.seconds)
    }

    public var decodeDuration: Duration? {
        decodeDurationSeconds.map(Duration.seconds)
    }

    private enum CodingKeys: String, CodingKey {
        case audioDurationSeconds
        case decodeDurationSeconds
        case firstWordStartSeconds
        case lastWordEndSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = Self(
            audioDurationSeconds: try container.decodeIfPresent(
                Double.self,
                forKey: .audioDurationSeconds
            ),
            decodeDurationSeconds: try container.decodeIfPresent(
                Double.self,
                forKey: .decodeDurationSeconds
            ),
            firstWordStartSeconds: try container.decodeIfPresent(
                Double.self,
                forKey: .firstWordStartSeconds
            ),
            lastWordEndSeconds: try container.decodeIfPresent(
                Double.self,
                forKey: .lastWordEndSeconds
            )
        )
        try RecognitionCoding.validateTiming(value)
        self = value
    }
}

public struct RecognizedWord: Codable, Hashable, Sendable, Identifiable {
    public let id: StableWordID
    public var text: String
    public let startSeconds: Double?
    public let endSeconds: Double?
    public let tokenRange: Range<Int>?
    public let rawEvidence: WordEvidence
    public var calibratedErrorProbability: Double?
    public var lockState: WordLockState
    public var provenance: WordProvenance

    public init(
        id: StableWordID,
        text: String,
        startSeconds: Double? = nil,
        endSeconds: Double? = nil,
        startTime: Duration? = nil,
        endTime: Duration? = nil,
        tokenRange: Range<Int>? = nil,
        rawEvidence: WordEvidence = .unavailable,
        calibratedErrorProbability: Double? = nil,
        lockState: WordLockState = .unlocked,
        provenance: WordProvenance? = nil
    ) {
        let resolvedStart = startSeconds ?? startTime.map(Self.seconds(from:))
        let resolvedEnd = endSeconds ?? endTime.map(Self.seconds(from:))
        Self.preconditionTiming(start: resolvedStart, end: resolvedEnd)
        precondition(tokenRange == nil || tokenRange!.lowerBound >= 0)
        self.id = id
        self.text = text
        self.startSeconds = resolvedStart
        self.endSeconds = resolvedEnd
        self.tokenRange = tokenRange
        self.rawEvidence = rawEvidence
        self.calibratedErrorProbability = calibratedErrorProbability
        self.lockState = lockState
        self.provenance = provenance ?? .primary(
            providerDecodeID: id.providerDecodeID,
            wordIndex: id.wordIndex
        )
    }

    public var startTime: Duration? {
        startSeconds.map(Duration.seconds)
    }

    public var endTime: Duration? {
        endSeconds.map(Duration.seconds)
    }

    public var durationSeconds: Double? {
        guard let startSeconds, let endSeconds else { return nil }
        return endSeconds - startSeconds
    }

    private static func seconds(from duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }

    private static func preconditionTiming(start: Double?, end: Double?) {
        if let start {
            precondition(start.isFinite && start >= 0)
        }
        if let end {
            precondition(end.isFinite && end >= 0)
        }
        if let start, let end {
            precondition(end >= start)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case startSeconds
        case endSeconds
        case tokenRange
        case rawEvidence
        case calibratedErrorProbability
        case lockState
        case provenance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let limits = decoder.recognitionDecodingLimits
        let startSeconds = try container.decodeIfPresent(Double.self, forKey: .startSeconds)
        let endSeconds = try container.decodeIfPresent(Double.self, forKey: .endSeconds)
        try RecognitionCoding.validateWordTiming(start: startSeconds, end: endSeconds)
        let tokenRange = try container.decodeIfPresent(Range<Int>.self, forKey: .tokenRange)
        if let tokenRange {
            guard tokenRange.lowerBound >= 0,
                  tokenRange.upperBound >= tokenRange.lowerBound,
                  tokenRange.count <= limits.maxTokensPerWord
            else {
                if tokenRange.count > limits.maxTokensPerWord {
                    throw RecognitionContractError.limitExceeded(
                        field: "word.token_range",
                        actual: tokenRange.count,
                        maximum: limits.maxTokensPerWord
                    )
                }
                throw RecognitionContractError.malformed("invalid word token range")
            }
        }
        let text = try RecognitionCoding.decodeString(
            from: container,
            forKey: .text,
            field: "word.text",
            limits: limits
        )
        let value = Self(
            id: try container.decode(StableWordID.self, forKey: .id),
            text: text,
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            tokenRange: tokenRange,
            rawEvidence: try container.decodeIfPresent(
                WordEvidence.self,
                forKey: .rawEvidence
            ) ?? .unavailable,
            calibratedErrorProbability: try container.decodeIfPresent(
                Double.self,
                forKey: .calibratedErrorProbability
            ),
            lockState: try container.decodeIfPresent(
                WordLockState.self,
                forKey: .lockState
            ) ?? .unlocked,
            provenance: try container.decodeIfPresent(
                WordProvenance.self,
                forKey: .provenance
            )
        )
        try RecognitionCoding.validateWord(value, limits: limits)
        self = value
    }
}

public struct RecognizedSegment: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var text: String
    public let startSeconds: Double
    public let endSeconds: Double
    public let wordIDs: [StableWordID]
    public let tokenRange: Range<Int>?
    public let evidence: UtteranceEvidence
    public let provenance: RecognitionProvenance

    public init(
        id: UUID = UUID(),
        text: String,
        startSeconds: Double,
        endSeconds: Double,
        startTime: Duration? = nil,
        endTime: Duration? = nil,
        wordIDs: [StableWordID] = [],
        tokenRange: Range<Int>? = nil,
        evidence: UtteranceEvidence = .unavailable,
        provenance: RecognitionProvenance = RecognitionProvenance()
    ) {
        let resolvedStart = startTime.map(Self.seconds(from:)) ?? startSeconds
        let resolvedEnd = endTime.map(Self.seconds(from:)) ?? endSeconds
        precondition(resolvedStart.isFinite && resolvedStart >= 0)
        precondition(resolvedEnd.isFinite && resolvedEnd >= resolvedStart)
        precondition(tokenRange == nil || tokenRange!.lowerBound >= 0)
        self.id = id
        self.text = text
        self.startSeconds = resolvedStart
        self.endSeconds = resolvedEnd
        self.wordIDs = wordIDs
        self.tokenRange = tokenRange
        self.evidence = evidence
        self.provenance = provenance
    }

    public var startTime: Duration { .seconds(startSeconds) }
    public var endTime: Duration { .seconds(endSeconds) }
    public var durationSeconds: Double { endSeconds - startSeconds }

    private static func seconds(from duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case startSeconds
        case endSeconds
        case wordIDs = "wordIds"
        case tokenRange
        case evidence
        case provenance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let limits = decoder.recognitionDecodingLimits
        let startSeconds = try container.decode(Double.self, forKey: .startSeconds)
        let endSeconds = try container.decode(Double.self, forKey: .endSeconds)
        try RecognitionCoding.validateWordTiming(start: startSeconds, end: endSeconds)
        let tokenRange = try container.decodeIfPresent(Range<Int>.self, forKey: .tokenRange)
        if let tokenRange {
            guard tokenRange.lowerBound >= 0,
                  tokenRange.upperBound >= tokenRange.lowerBound,
                  tokenRange.count <= limits.maxTokensPerWord
            else {
                if tokenRange.count > limits.maxTokensPerWord {
                    throw RecognitionContractError.limitExceeded(
                        field: "segment.token_range",
                        actual: tokenRange.count,
                        maximum: limits.maxTokensPerWord
                    )
                }
                throw RecognitionContractError.malformed("invalid segment token range")
            }
        }
        let value = Self(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            text: try RecognitionCoding.decodeString(
                from: container,
                forKey: .text,
                field: "segment.text",
                limits: limits
            ),
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            wordIDs: try RecognitionCoding.decodeArray(
                StableWordID.self,
                from: container,
                forKey: .wordIDs,
                field: "segment.word_ids",
                maximum: limits.maxProvenanceIDs,
                limits: limits
            ),
            tokenRange: tokenRange,
            evidence: try container.decodeIfPresent(
                UtteranceEvidence.self,
                forKey: .evidence
            ) ?? .unavailable,
            provenance: try container.decodeIfPresent(
                RecognitionProvenance.self,
                forKey: .provenance
            ) ?? RecognitionProvenance()
        )
        try RecognitionCoding.validateSegment(value, limits: limits)
        self = value
    }
}

public struct RecognitionAlternative: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let text: String
    public let words: [RecognizedWord]
    public let segments: [RecognizedSegment]
    public let score: Double?
    public let rank: Int?
    public let engine: RecognitionEngineID?
    public let model: ModelIdentity?
    public let pass: RecognitionPassKind?
    public let provenance: RecognitionProvenance

    public init(
        id: UUID = UUID(),
        text: String,
        words: [RecognizedWord] = [],
        segments: [RecognizedSegment] = [],
        score: Double? = nil,
        rank: Int? = nil,
        engine: RecognitionEngineID? = nil,
        model: ModelIdentity? = nil,
        pass: RecognitionPassKind? = nil,
        provenance: RecognitionProvenance = RecognitionProvenance()
    ) {
        precondition(rank == nil || rank! >= 0)
        self.id = id
        self.text = text
        self.words = words
        self.segments = segments
        self.score = score
        self.rank = rank
        self.engine = engine
        self.model = model
        self.pass = pass
        self.provenance = provenance
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case words
        case segments
        case score
        case rank
        case engine
        case model
        case pass
        case provenance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let limits = decoder.recognitionDecodingLimits
        let rank = try container.decodeIfPresent(Int.self, forKey: .rank)
        guard rank == nil || rank! >= 0 else {
            throw RecognitionContractError.malformed("negative alternative rank")
        }
        let value = Self(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            text: try RecognitionCoding.decodeString(
                from: container,
                forKey: .text,
                field: "alternative.text",
                limits: limits
            ),
            words: try RecognitionCoding.decodeArray(
                RecognizedWord.self,
                from: container,
                forKey: .words,
                field: "alternative.words",
                maximum: limits.maxWords,
                limits: limits
            ),
            segments: try RecognitionCoding.decodeArray(
                RecognizedSegment.self,
                from: container,
                forKey: .segments,
                field: "alternative.segments",
                maximum: limits.maxSegments,
                limits: limits
            ),
            score: try container.decodeIfPresent(Double.self, forKey: .score),
            rank: rank,
            engine: try container.decodeIfPresent(
                RecognitionEngineID.self,
                forKey: .engine
            ),
            model: try container.decodeIfPresent(ModelIdentity.self, forKey: .model),
            pass: try container.decodeIfPresent(RecognitionPassKind.self, forKey: .pass),
            provenance: try container.decodeIfPresent(
                RecognitionProvenance.self,
                forKey: .provenance
            ) ?? RecognitionProvenance()
        )
        try RecognitionCoding.validateAlternative(value, limits: limits)
        self = value
    }
}

public struct RecognitionPassMetadata: Codable, Hashable, Sendable {
    public let strategy: String?
    public let beamSize: Int?
    public let temperature: Double?
    public let usedPrompt: Bool
    public let promptCharacterCount: Int?
    public let protocolVersion: Int
    public let requestID: String?
    public let adaptiveFallback: Bool

    public init(
        strategy: String? = nil,
        beamSize: Int? = nil,
        temperature: Double? = nil,
        usedPrompt: Bool = false,
        promptCharacterCount: Int? = nil,
        protocolVersion: Int = 2,
        requestID: String? = nil,
        adaptiveFallback: Bool = false
    ) {
        precondition(beamSize == nil || beamSize! >= 0)
        precondition(promptCharacterCount == nil || promptCharacterCount! >= 0)
        self.strategy = strategy
        self.beamSize = beamSize
        self.temperature = temperature
        self.usedPrompt = usedPrompt
        self.promptCharacterCount = promptCharacterCount
        self.protocolVersion = protocolVersion
        self.requestID = requestID
        self.adaptiveFallback = adaptiveFallback
    }

    private enum CodingKeys: String, CodingKey {
        case strategy
        case beamSize
        case temperature
        case usedPrompt
        case promptCharacterCount
        case protocolVersion
        case requestID = "requestId"
        case adaptiveFallback
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let limits = decoder.recognitionDecodingLimits
        let beamSize = try container.decodeIfPresent(Int.self, forKey: .beamSize)
        let promptCharacterCount = try container.decodeIfPresent(
            Int.self,
            forKey: .promptCharacterCount
        )
        guard beamSize == nil || beamSize! >= 0 else {
            throw RecognitionContractError.malformed("negative beam size")
        }
        guard promptCharacterCount == nil || promptCharacterCount! >= 0 else {
            throw RecognitionContractError.malformed("negative prompt character count")
        }
        let value = Self(
            strategy: try RecognitionCoding.decodeOptionalString(
                from: container,
                forKey: .strategy,
                field: "pass_metadata.strategy",
                limits: limits
            ),
            beamSize: beamSize,
            temperature: try container.decodeIfPresent(Double.self, forKey: .temperature),
            usedPrompt: try container.decodeIfPresent(Bool.self, forKey: .usedPrompt) ?? false,
            promptCharacterCount: promptCharacterCount,
            protocolVersion: try container.decodeIfPresent(
                Int.self,
                forKey: .protocolVersion
            ) ?? 2,
            requestID: try RecognitionCoding.decodeOptionalString(
                from: container,
                forKey: .requestID,
                field: "pass_metadata.request_id",
                limits: limits
            ),
            adaptiveFallback: try container.decodeIfPresent(
                Bool.self,
                forKey: .adaptiveFallback
            ) ?? false
        )
        try RecognitionCoding.validatePassMetadata(value, limits: limits)
        self = value
    }
}

/// Provider-neutral recognition output.  `text` is retained as the outermost
/// migration projection while words and evidence become the canonical state.
public struct RecognitionResult: Codable, Hashable, Sendable {
    public let sessionID: UUID
    public let generation: UInt64
    public let engine: RecognitionEngineID
    public let model: ModelIdentity
    public let pass: RecognitionPassKind
    public let text: String
    public let words: [RecognizedWord]
    public let segments: [RecognizedSegment]
    public let alternatives: [RecognitionAlternative]
    public let utteranceEvidence: UtteranceEvidence
    public let timing: RecognitionTiming
    public let completeness: DecodeCompleteness
    public let passMetadata: RecognitionPassMetadata

    public init(
        sessionID: UUID,
        generation: UInt64 = 0,
        engine: RecognitionEngineID,
        model: ModelIdentity = .unknown,
        pass: RecognitionPassKind = .primaryFullSession,
        text: String,
        words: [RecognizedWord] = [],
        segments: [RecognizedSegment] = [],
        alternatives: [RecognitionAlternative] = [],
        utteranceEvidence: UtteranceEvidence = .unavailable,
        timing: RecognitionTiming = .unavailable,
        completeness: DecodeCompleteness = .finalSession,
        passMetadata: RecognitionPassMetadata = RecognitionPassMetadata()
    ) {
        self.sessionID = sessionID
        self.generation = generation
        self.engine = engine
        self.model = model
        self.pass = pass
        self.text = text
        self.words = words
        self.segments = segments
        self.alternatives = alternatives
        self.utteranceEvidence = utteranceEvidence
        self.timing = timing
        self.completeness = completeness
        self.passMetadata = passMetadata
    }

    /// Compatibility projection consumed by existing rendered-text call sites.
    public var renderedText: String { text }

    public var normalizedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Builds a canonical result from the hypothesis-only API without
    /// changing its text behavior.  IDs are deterministic for the supplied
    /// session and hypothesis decode ID.
    public init(
        hypothesis: RecognitionHypothesis,
        sessionID: UUID,
        generation: UInt64 = 0,
        completeness: DecodeCompleteness = .finalSession
    ) {
        let providerDecodeID = hypothesis.id.uuidString
        let words = hypothesis.words.enumerated().map { index, word in
            RecognizedWord(
                id: StableWordID(
                    sessionID: sessionID,
                    providerDecodeID: providerDecodeID,
                    wordIndex: index
                ),
                text: word.text,
                startSeconds: word.startSeconds,
                endSeconds: word.endSeconds,
                rawEvidence: word.confidence.map {
                    WordEvidence(
                        posterior: $0,
                        availability: .posterior
                    )
                } ?? .unavailable,
                provenance: .primary(
                    providerDecodeID: providerDecodeID,
                    wordIndex: index
                )
            )
        }
        let segments = hypothesis.segments.map { segment in
            RecognizedSegment(
                text: segment.text,
                startSeconds: segment.startSeconds,
                endSeconds: segment.endSeconds,
                wordIDs: words.compactMap { word in
                    guard let start = word.startSeconds,
                          let end = word.endSeconds,
                          start >= segment.startSeconds,
                          end <= segment.endSeconds
                    else { return nil }
                    return word.id
                }
            )
        }
        self.init(
            sessionID: sessionID,
            generation: generation,
            engine: hypothesis.engine,
            model: ModelIdentity(
                identifier: hypothesis.modelID ?? "unknown",
                version: hypothesis.engineVersion
            ),
            pass: hypothesis.pass,
            text: hypothesis.text,
            words: words,
            segments: segments,
            utteranceEvidence: UtteranceEvidence(
                sequenceScore: hypothesis.sequenceScore,
                averageLogProbability: hypothesis.averageLogProbability,
                noSpeechProbability: hypothesis.noSpeechProbability,
                weakTokenFraction: hypothesis.weakTokenFraction,
                repetitionDetected: hypothesis.repetitionDetected
            ),
            timing: RecognitionTiming(
                audioDurationSeconds: hypothesis.window.durationSeconds,
                decodeDurationSeconds: hypothesis.latencyMilliseconds.map { $0 / 1_000 }
            ),
            completeness: completeness,
            passMetadata: RecognitionPassMetadata(
                protocolVersion: Int(hypothesis.metadata["protocolVersion"] ?? "2") ?? 2,
                requestID: hypothesis.metadata["requestID"].flatMap {
                    $0.isEmpty ? nil : $0
                },
                adaptiveFallback: hypothesis.adaptiveFallback
            )
        )
    }

    public init(
        hypothesis: RecognitionHypothesis,
        generation: UInt64 = 0,
        completeness: DecodeCompleteness = .finalSession
    ) {
        self.init(
            hypothesis: hypothesis,
            sessionID: UUID(),
            generation: generation,
            completeness: completeness
        )
    }

    public func asHypothesis() -> RecognitionHypothesis {
        RecognitionHypothesis(
            id: words.first.flatMap { UUID(uuidString: $0.id.providerDecodeID) } ?? UUID(),
            engine: engine,
            pass: pass,
            window: RecognitionWindow(
                startSample: 0,
                endSample: Int64((timing.audioDurationSeconds ?? 0) * 16_000)
            ),
            text: text,
            words: words.map {
                TimedWord(
                    text: $0.text,
                    startSeconds: $0.startSeconds,
                    endSeconds: $0.endSeconds,
                    confidence: $0.rawEvidence.posterior
                )
            },
            segments: segments.map {
                TimedSegment(
                    startSeconds: $0.startSeconds,
                    endSeconds: $0.endSeconds,
                    text: $0.text
                )
            },
            averageLogProbability: utteranceEvidence.averageLogProbability,
            noSpeechProbability: utteranceEvidence.noSpeechProbability,
            weakTokenFraction: utteranceEvidence.weakTokenFraction,
            repetitionDetected: utteranceEvidence.repetitionDetected,
            adaptiveFallback: passMetadata.adaptiveFallback,
            modelID: model.identifier,
            engineVersion: model.version,
            metadata: [
                "protocolVersion": String(passMetadata.protocolVersion),
                "requestID": passMetadata.requestID ?? ""
            ],
            latencyMilliseconds: timing.decodeDurationSeconds.map { $0 * 1_000 }
        )
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID = "sessionId"
        case generation
        case engine
        case model
        case pass
        case text
        case words
        case segments
        case alternatives
        case utteranceEvidence
        case timing
        case completeness
        case passMetadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let limits = decoder.recognitionDecodingLimits
        self.init(
            sessionID: try container.decode(UUID.self, forKey: .sessionID),
            generation: try container.decodeIfPresent(UInt64.self, forKey: .generation) ?? 0,
            engine: try container.decode(RecognitionEngineID.self, forKey: .engine),
            model: try container.decodeIfPresent(ModelIdentity.self, forKey: .model) ?? .unknown,
            pass: try container.decodeIfPresent(RecognitionPassKind.self, forKey: .pass)
                ?? .primaryFullSession,
            text: try RecognitionCoding.decodeString(
                from: container,
                forKey: .text,
                field: "text",
                limits: limits
            ),
            words: try RecognitionCoding.decodeArray(
                RecognizedWord.self,
                from: container,
                forKey: .words,
                field: "words",
                maximum: limits.maxWords,
                limits: limits
            ),
            segments: try RecognitionCoding.decodeArray(
                RecognizedSegment.self,
                from: container,
                forKey: .segments,
                field: "segments",
                maximum: limits.maxSegments,
                limits: limits
            ),
            alternatives: try RecognitionCoding.decodeArray(
                RecognitionAlternative.self,
                from: container,
                forKey: .alternatives,
                field: "alternatives",
                maximum: limits.maxAlternatives,
                limits: limits
            ),
            utteranceEvidence: try container.decodeIfPresent(
                UtteranceEvidence.self,
                forKey: .utteranceEvidence
            ) ?? .unavailable,
            timing: try container.decodeIfPresent(
                RecognitionTiming.self,
                forKey: .timing
            ) ?? .unavailable,
            completeness: try container.decodeIfPresent(
                DecodeCompleteness.self,
                forKey: .completeness
            ) ?? .finalSession,
            passMetadata: try container.decodeIfPresent(
                RecognitionPassMetadata.self,
                forKey: .passMetadata
            ) ?? RecognitionPassMetadata()
        )
        try validate(limits: limits)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(limits: encoder.recognitionDecodingLimits)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(generation, forKey: .generation)
        try container.encode(engine, forKey: .engine)
        try container.encode(model, forKey: .model)
        try container.encode(pass, forKey: .pass)
        try container.encode(text, forKey: .text)
        try container.encode(words, forKey: .words)
        try container.encode(segments, forKey: .segments)
        try container.encode(alternatives, forKey: .alternatives)
        try container.encode(utteranceEvidence, forKey: .utteranceEvidence)
        try container.encode(timing, forKey: .timing)
        try container.encode(completeness, forKey: .completeness)
        try container.encode(passMetadata, forKey: .passMetadata)
    }

    public func validate(limits: RecognitionDecodingLimits = .default) throws {
        try RecognitionCoding.validateString(text, field: "text", limits: limits)
        try RecognitionCoding.validateWords(words, field: "words", limits: limits)
        try RecognitionCoding.validateSegments(segments, field: "segments", limits: limits)
        guard alternatives.count <= limits.maxAlternatives else {
            throw RecognitionContractError.limitExceeded(
                field: "alternatives",
                actual: alternatives.count,
                maximum: limits.maxAlternatives
            )
        }
        for alternative in alternatives {
            try RecognitionCoding.validateAlternative(alternative, limits: limits)
        }
        try RecognitionCoding.validateTiming(timing)
        try RecognitionCoding.validateUtteranceEvidence(utteranceEvidence)
        try RecognitionCoding.validatePassMetadata(passMetadata, limits: limits)
        try RecognitionCoding.validateModel(model, limits: limits)
    }
}

/// Limits are applied before each JSON collection is decoded and again after
/// construction.  The line limit is checked before JSON decoding begins.
public struct RecognitionDecodingLimits: Codable, Hashable, Sendable {
    public let maxLineBytes: Int
    public let maxStringBytes: Int
    public let maxWords: Int
    public let maxSegments: Int
    public let maxAlternatives: Int
    public let maxTokensPerWord: Int
    public let maxTokenLogProbabilitiesPerWord: Int
    public let maxMetadataEntries: Int
    public let maxProvenanceIDs: Int
    public let maxFallbackTemperatures: Int

    public init(
        maxLineBytes: Int = 1_048_576,
        maxStringBytes: Int = 16_384,
        maxWords: Int = 4_096,
        maxSegments: Int = 1_024,
        maxAlternatives: Int = 8,
        maxTokensPerWord: Int = 256,
        maxTokenLogProbabilitiesPerWord: Int = 256,
        maxMetadataEntries: Int = 64,
        maxProvenanceIDs: Int = 256,
        maxFallbackTemperatures: Int = 32
    ) {
        precondition(maxLineBytes > 0)
        precondition(maxStringBytes > 0)
        precondition(maxWords >= 0)
        precondition(maxSegments >= 0)
        precondition(maxAlternatives >= 0)
        precondition(maxTokensPerWord >= 0)
        precondition(maxTokenLogProbabilitiesPerWord >= 0)
        precondition(maxMetadataEntries >= 0)
        precondition(maxProvenanceIDs >= 0)
        precondition(maxFallbackTemperatures >= 0)
        self.maxLineBytes = maxLineBytes
        self.maxStringBytes = maxStringBytes
        self.maxWords = maxWords
        self.maxSegments = maxSegments
        self.maxAlternatives = maxAlternatives
        self.maxTokensPerWord = maxTokensPerWord
        self.maxTokenLogProbabilitiesPerWord = maxTokenLogProbabilitiesPerWord
        self.maxMetadataEntries = maxMetadataEntries
        self.maxProvenanceIDs = maxProvenanceIDs
        self.maxFallbackTemperatures = maxFallbackTemperatures
    }

    public static let `default` = Self()

    /// Set this value on a JSONDecoder/JSONEncoder to apply custom limits to
    /// direct Codable operations.  Protocol helpers set it automatically.
    public static let codingUserInfoKey = CodingUserInfoKey(
        rawValue: "whisper_hotkey.recognition_decoding_limits"
    )!
}

public enum RecognitionContractError: Error, Equatable, Sendable {
    case unsupportedProtocolVersion(Int)
    case lineTooLarge(actualBytes: Int, maximumBytes: Int)
    case limitExceeded(field: String, actual: Int, maximum: Int)
    case malformed(String)
}

public enum RecognitionProtocolEvent: String, Codable, Hashable, Sendable {
    case ready
    case result
    case error
}

/// Version-two JSON-lines envelope.  Rich output is nested so event metadata
/// can evolve without flattening provider-specific fields into the transport.
public struct RecognitionProtocolV2Envelope: Codable, Hashable, Sendable {
    public static let version = 2

    public let protocolVersion: Int
    public let event: RecognitionProtocolEvent
    public let requestID: String?
    public let result: RecognitionResult?
    public let code: String?
    public let message: String?

    public init(
        protocolVersion: Int = Self.version,
        event: RecognitionProtocolEvent,
        requestID: String? = nil,
        result: RecognitionResult? = nil,
        code: String? = nil,
        message: String? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.event = event
        self.requestID = requestID
        self.result = result
        self.code = code
        self.message = message
    }

    public init(
        protocolVersion: Int = Self.version,
        event: String,
        requestID: String? = nil,
        result: RecognitionResult? = nil,
        code: String? = nil,
        message: String? = nil
    ) throws {
        guard let event = RecognitionProtocolEvent(rawValue: event) else {
            throw RecognitionContractError.malformed("unknown event")
        }
        self.init(
            protocolVersion: protocolVersion,
            event: event,
            requestID: requestID,
            result: result,
            code: code,
            message: message
        )
    }

    public func validate(limits: RecognitionDecodingLimits = .default) throws {
        guard protocolVersion == Self.version else {
            throw RecognitionContractError.unsupportedProtocolVersion(protocolVersion)
        }
        if let requestID {
            try RecognitionCoding.validateString(requestID, field: "request_id", limits: limits)
        }
        if let code {
            try RecognitionCoding.validateString(code, field: "code", limits: limits)
        }
        if let message {
            try RecognitionCoding.validateString(message, field: "message", limits: limits)
        }
        switch event {
        case .result:
            guard let result else {
                throw RecognitionContractError.malformed("result event has no result")
            }
            try result.validate(limits: limits)
        case .ready, .error:
            guard result == nil else {
                throw RecognitionContractError.malformed("non-result event has a result")
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case protocolVersion
        case event
        case requestID = "requestId"
        case result
        case code
        case message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let protocolVersion = try container.decode(Int.self, forKey: .protocolVersion)
        guard protocolVersion == Self.version else {
            throw RecognitionContractError.unsupportedProtocolVersion(protocolVersion)
        }
        self.init(
            protocolVersion: protocolVersion,
            event: try container.decode(RecognitionProtocolEvent.self, forKey: .event),
            requestID: try RecognitionCoding.decodeOptionalString(
                from: container,
                forKey: .requestID,
                field: "request_id",
                limits: decoder.recognitionDecodingLimits
            ),
            result: try container.decodeIfPresent(RecognitionResult.self, forKey: .result),
            code: try RecognitionCoding.decodeOptionalString(
                from: container,
                forKey: .code,
                field: "code",
                limits: decoder.recognitionDecodingLimits
            ),
            message: try RecognitionCoding.decodeOptionalString(
                from: container,
                forKey: .message,
                field: "message",
                limits: decoder.recognitionDecodingLimits
            )
        )
        try validate(limits: decoder.recognitionDecodingLimits)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(limits: encoder.recognitionDecodingLimits)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(protocolVersion, forKey: .protocolVersion)
        try container.encode(event, forKey: .event)
        try container.encodeIfPresent(requestID, forKey: .requestID)
        try container.encodeIfPresent(result, forKey: .result)
        try container.encodeIfPresent(code, forKey: .code)
        try container.encodeIfPresent(message, forKey: .message)
    }
}

public enum RecognitionProtocolV2 {
    public static func decode(
        line: String,
        limits: RecognitionDecodingLimits = .default
    ) throws -> RecognitionProtocolV2Envelope {
        guard let data = line.data(using: .utf8) else {
            throw RecognitionContractError.malformed("line is not UTF-8")
        }
        return try decode(data: data, limits: limits)
    }

    public static func decode(
        data: Data,
        limits: RecognitionDecodingLimits = .default
    ) throws -> RecognitionProtocolV2Envelope {
        guard data.count <= limits.maxLineBytes else {
            throw RecognitionContractError.lineTooLarge(
                actualBytes: data.count,
                maximumBytes: limits.maxLineBytes
            )
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.userInfo[RecognitionDecodingLimits.codingUserInfoKey] = limits
        let envelope: RecognitionProtocolV2Envelope
        do {
            envelope = try decoder.decode(RecognitionProtocolV2Envelope.self, from: data)
        } catch let error as RecognitionContractError {
            throw error
        } catch {
            throw RecognitionContractError.malformed(error.localizedDescription)
        }
        try envelope.validate(limits: limits)
        return envelope
    }

    public static func encode(
        _ envelope: RecognitionProtocolV2Envelope,
        limits: RecognitionDecodingLimits = .default
    ) throws -> Data {
        try envelope.validate(limits: limits)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.userInfo[RecognitionDecodingLimits.codingUserInfoKey] = limits
        let data: Data
        do {
            data = try encoder.encode(envelope)
        } catch let error as RecognitionContractError {
            throw error
        } catch {
            throw RecognitionContractError.malformed(error.localizedDescription)
        }
        guard data.count <= limits.maxLineBytes else {
            throw RecognitionContractError.lineTooLarge(
                actualBytes: data.count,
                maximumBytes: limits.maxLineBytes
            )
        }
        return data
    }

    public static func encodeLine(
        _ envelope: RecognitionProtocolV2Envelope,
        limits: RecognitionDecodingLimits = .default
    ) throws -> String {
        let data = try encode(envelope, limits: limits)
        guard let line = String(data: data, encoding: .utf8) else {
            throw RecognitionContractError.malformed("encoded line is not UTF-8")
        }
        return line
    }
}

private extension Decoder {
    var recognitionDecodingLimits: RecognitionDecodingLimits {
        (userInfo[RecognitionDecodingLimits.codingUserInfoKey]
            as? RecognitionDecodingLimits) ?? .default
    }
}

private extension Encoder {
    var recognitionDecodingLimits: RecognitionDecodingLimits {
        (userInfo[RecognitionDecodingLimits.codingUserInfoKey]
            as? RecognitionDecodingLimits) ?? .default
    }
}

private enum RecognitionCoding {
    static func decodeString<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key,
        field: String,
        limits: RecognitionDecodingLimits
    ) throws -> String {
        let value = try container.decode(String.self, forKey: key)
        try validateString(value, field: field, limits: limits)
        return value
    }

    static func decodeOptionalString<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key,
        field: String,
        limits: RecognitionDecodingLimits
    ) throws -> String? {
        guard let value = try container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        try validateString(value, field: field, limits: limits)
        return value
    }

    static func decodeArray<Element: Decodable, Key: CodingKey>(
        _ type: Element.Type,
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key,
        field: String,
        maximum: Int,
        limits: RecognitionDecodingLimits
    ) throws -> [Element] {
        guard container.contains(key), try !container.decodeNil(forKey: key) else {
            return []
        }
        let nested = try container.nestedUnkeyedContainer(forKey: key)
        guard let count = nested.count else {
            throw RecognitionContractError.malformed("cannot determine (field) count")
        }
        guard count <= maximum else {
            throw RecognitionContractError.limitExceeded(
                field: field,
                actual: count,
                maximum: maximum
            )
        }
        _ = type
        _ = limits
        return try container.decode([Element].self, forKey: key)
    }

    static func validateString(
        _ value: String,
        field: String,
        limits: RecognitionDecodingLimits
    ) throws {
        let bytes = value.utf8.count
        guard bytes <= limits.maxStringBytes else {
            throw RecognitionContractError.limitExceeded(
                field: field,
                actual: bytes,
                maximum: limits.maxStringBytes
            )
        }
    }

    static func validateWords(
        _ words: [RecognizedWord],
        field: String,
        limits: RecognitionDecodingLimits
    ) throws {
        guard words.count <= limits.maxWords else {
            throw RecognitionContractError.limitExceeded(
                field: field,
                actual: words.count,
                maximum: limits.maxWords
            )
        }
        for word in words {
            try validateWord(word, limits: limits)
        }
    }

    static func validateWord(
        _ word: RecognizedWord,
        limits: RecognitionDecodingLimits
    ) throws {
        try validateString(word.text, field: "word.text", limits: limits)
        guard word.id.wordIndex >= 0, !word.id.providerDecodeID.isEmpty else {
            throw RecognitionContractError.malformed("invalid stable word ID")
        }
        try validateWordTiming(start: word.startSeconds, end: word.endSeconds)
        if let tokenRange = word.tokenRange {
            guard tokenRange.lowerBound >= 0,
                  tokenRange.upperBound >= tokenRange.lowerBound
            else {
                throw RecognitionContractError.malformed("invalid word token range")
            }
            guard tokenRange.count <= limits.maxTokensPerWord else {
                throw RecognitionContractError.limitExceeded(
                    field: "word.token_range",
                    actual: tokenRange.count,
                    maximum: limits.maxTokensPerWord
                )
            }
        }
        try validateWordEvidence(word.rawEvidence, limits: limits)
        if let probability = word.calibratedErrorProbability {
            try validateProbability(probability, field: "word.calibrated_error_probability")
        }
        try validateWordProvenance(word.provenance, limits: limits)
    }

    static func validateWordEvidence(
        _ evidence: WordEvidence,
        limits: RecognitionDecodingLimits = .default
    ) throws {
        guard evidence.tokenIDs.count <= limits.maxTokensPerWord else {
            throw RecognitionContractError.limitExceeded(
                field: "word.evidence.token_ids",
                actual: evidence.tokenIDs.count,
                maximum: limits.maxTokensPerWord
            )
        }
        guard evidence.tokenLogProbabilities.count <= limits.maxTokenLogProbabilitiesPerWord else {
            throw RecognitionContractError.limitExceeded(
                field: "word.evidence.token_log_probabilities",
                actual: evidence.tokenLogProbabilities.count,
                maximum: limits.maxTokenLogProbabilitiesPerWord
            )
        }
        for value in evidence.tokenLogProbabilities where !value.isFinite {
            throw RecognitionContractError.malformed("non-finite token log probability")
        }
        if let posterior = evidence.posterior {
            try validateProbability(posterior, field: "word.evidence.posterior")
        }
        if let entropy = evidence.entropy, !entropy.isFinite || entropy < 0 {
            throw RecognitionContractError.malformed("invalid word evidence entropy")
        }
        if let beamScore = evidence.beamScore, !beamScore.isFinite {
            throw RecognitionContractError.malformed("non-finite word beam score")
        }
        guard evidence.beamRank == nil || evidence.beamRank! >= 0 else {
            throw RecognitionContractError.malformed("negative word beam rank")
        }
    }

    static func validateWordProvenance(
        _ provenance: WordProvenance,
        limits: RecognitionDecodingLimits
    ) throws {
        guard provenance.sourceWordIDs.count <= limits.maxProvenanceIDs else {
            throw RecognitionContractError.limitExceeded(
                field: "word.provenance.source_word_ids",
                actual: provenance.sourceWordIDs.count,
                maximum: limits.maxProvenanceIDs
            )
        }
        if let providerDecodeID = provenance.providerDecodeID {
            try validateString(
                providerDecodeID,
                field: "word.provenance.provider_decode_id",
                limits: limits
            )
        }
        if let providerWordIndex = provenance.providerWordIndex, providerWordIndex < 0 {
            throw RecognitionContractError.malformed("negative provider word index")
        }
        if let reason = provenance.reason {
            try validateString(reason, field: "word.provenance.reason", limits: limits)
        }
    }

    static func validateSegments(
        _ segments: [RecognizedSegment],
        field: String,
        limits: RecognitionDecodingLimits
    ) throws {
        guard segments.count <= limits.maxSegments else {
            throw RecognitionContractError.limitExceeded(
                field: field,
                actual: segments.count,
                maximum: limits.maxSegments
            )
        }
        for segment in segments {
            try validateSegment(segment, limits: limits)
        }
    }

    static func validateSegment(
        _ segment: RecognizedSegment,
        limits: RecognitionDecodingLimits
    ) throws {
        try validateString(segment.text, field: "segment.text", limits: limits)
        try validateWordTiming(start: segment.startSeconds, end: segment.endSeconds)
        guard segment.wordIDs.count <= limits.maxProvenanceIDs else {
            throw RecognitionContractError.limitExceeded(
                field: "segment.word_ids",
                actual: segment.wordIDs.count,
                maximum: limits.maxProvenanceIDs
            )
        }
        if let tokenRange = segment.tokenRange {
            guard tokenRange.lowerBound >= 0,
                  tokenRange.upperBound >= tokenRange.lowerBound
            else {
                throw RecognitionContractError.malformed("invalid segment token range")
            }
            guard tokenRange.count <= limits.maxTokensPerWord else {
                throw RecognitionContractError.limitExceeded(
                    field: "segment.token_range",
                    actual: tokenRange.count,
                    maximum: limits.maxTokensPerWord
                )
            }
        }
        try validateUtteranceEvidence(segment.evidence)
        try validateProvenance(segment.provenance, limits: limits)
    }

    static func validateAlternative(
        _ alternative: RecognitionAlternative,
        limits: RecognitionDecodingLimits
    ) throws {
        try validateString(alternative.text, field: "alternative.text", limits: limits)
        try validateWords(alternative.words, field: "alternative.words", limits: limits)
        try validateSegments(
            alternative.segments,
            field: "alternative.segments",
            limits: limits
        )
        guard alternative.rank == nil || alternative.rank! >= 0 else {
            throw RecognitionContractError.malformed("negative alternative rank")
        }
        if let score = alternative.score, !score.isFinite {
            throw RecognitionContractError.malformed("non-finite alternative score")
        }
        if let model = alternative.model {
            try validateModel(model, limits: limits)
        }
        try validateProvenance(alternative.provenance, limits: limits)
    }

    static func validateProvenance(
        _ provenance: RecognitionProvenance,
        limits: RecognitionDecodingLimits
    ) throws {
        guard provenance.sourceWordIDs.count <= limits.maxProvenanceIDs else {
            throw RecognitionContractError.limitExceeded(
                field: "provenance.source_word_ids",
                actual: provenance.sourceWordIDs.count,
                maximum: limits.maxProvenanceIDs
            )
        }
        guard provenance.sourceAlternativeIDs.count <= limits.maxProvenanceIDs else {
            throw RecognitionContractError.limitExceeded(
                field: "provenance.source_alternative_ids",
                actual: provenance.sourceAlternativeIDs.count,
                maximum: limits.maxProvenanceIDs
            )
        }
        if let reason = provenance.reason {
            try validateString(reason, field: "provenance.reason", limits: limits)
        }
    }

    static func validateTiming(_ timing: RecognitionTiming) throws {
        let values: [(Double?, String)] = [
            (timing.audioDurationSeconds, "timing.audio_duration_seconds"),
            (timing.decodeDurationSeconds, "timing.decode_duration_seconds"),
            (timing.firstWordStartSeconds, "timing.first_word_start_seconds"),
            (timing.lastWordEndSeconds, "timing.last_word_end_seconds")
        ]
        for (value, field) in values {
            if let value {
                try validateNonNegative(value, field: field)
            }
        }
    }

    static func validateUtteranceEvidence(_ evidence: UtteranceEvidence) throws {
        let finiteValues: [(Double?, String)] = [
            (evidence.sequenceScore, "evidence.sequence_score"),
            (evidence.averageLogProbability, "evidence.average_log_probability"),
            (evidence.temperature, "evidence.temperature")
        ]
        for (value, field) in finiteValues {
            if let value, !value.isFinite {
                throw RecognitionContractError.malformed("non-finite \(field)")
            }
        }
        if let value = evidence.noSpeechProbability {
            try validateProbability(value, field: "evidence.no_speech_probability")
        }
        if let value = evidence.maximumNoSpeechProbability {
            try validateProbability(value, field: "evidence.maximum_no_speech_probability")
        }
        if let value = evidence.weakTokenFraction {
            try validateProbability(value, field: "evidence.weak_token_fraction")
        }
        for value in evidence.fallbackTemperatures where !value.isFinite {
            throw RecognitionContractError.malformed("non-finite fallback temperature")
        }
    }

    static func validatePassMetadata(
        _ metadata: RecognitionPassMetadata,
        limits: RecognitionDecodingLimits
    ) throws {
        if let strategy = metadata.strategy {
            try validateString(strategy, field: "pass_metadata.strategy", limits: limits)
        }
        if let requestID = metadata.requestID {
            try validateString(requestID, field: "pass_metadata.request_id", limits: limits)
        }
        guard metadata.beamSize == nil || metadata.beamSize! >= 0 else {
            throw RecognitionContractError.malformed("negative beam size")
        }
        guard metadata.promptCharacterCount == nil
                || metadata.promptCharacterCount! >= 0
        else {
            throw RecognitionContractError.malformed("negative prompt character count")
        }
        guard metadata.protocolVersion > 0 else {
            throw RecognitionContractError.malformed("invalid metadata protocol version")
        }
        if let temperature = metadata.temperature, !temperature.isFinite {
            throw RecognitionContractError.malformed("non-finite pass temperature")
        }
    }

    static func validateModel(
        _ model: ModelIdentity,
        limits: RecognitionDecodingLimits
    ) throws {
        guard !model.identifier.isEmpty else {
            throw RecognitionContractError.malformed("empty model identifier")
        }
        try validateString(model.identifier, field: "model.identifier", limits: limits)
        for (value, field) in [
            (model.version, "model.version"),
            (model.revision, "model.revision"),
            (model.quantization, "model.quantization"),
            (model.computeUnits, "model.compute_units")
        ] {
            if let value {
                try validateString(value, field: field, limits: limits)
            }
        }
    }

    static func validateWordTiming(start: Double?, end: Double?) throws {
        if let start {
            try validateNonNegative(start, field: "word.start_seconds")
        }
        if let end {
            try validateNonNegative(end, field: "word.end_seconds")
        }
        if let start, let end, end < start {
            throw RecognitionContractError.malformed("word timing ends before it starts")
        }
    }

    static func validateNonNegative(_ value: Double, field: String) throws {
        guard value.isFinite, value >= 0 else {
            throw RecognitionContractError.malformed("invalid \(field)")
        }
    }

    static func validateProbability(_ value: Double, field: String) throws {
        guard value.isFinite, (0...1).contains(value) else {
            throw RecognitionContractError.malformed("invalid \(field)")
        }
    }
}
