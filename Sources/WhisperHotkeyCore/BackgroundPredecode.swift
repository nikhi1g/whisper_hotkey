import Foundation

/// Processing choices that can consume streaming decode updates.
///
/// Recognition and delivery are deliberately separate: `pauseMode` can expose
/// whole-sentence candidates, while the accumulator itself never pastes text.
public enum BackgroundPredecodeMode: String, Codable, CaseIterable, Sendable {
    /// Keep all words provisional until finalization.
    case deferred
    /// Decode during capture, but deliver one ordered result at the end.
    case decodeWhileSpeaking
    /// Decode during capture and expose whole-sentence commit candidates.
    case pauseMode

    // Compatibility spellings for callers whose processing selector uses the
    // product labels rather than the accumulator's three semantic modes.
    public static let decodeAfterSpeaking = Self.deferred
    public static let modelReady = Self.deferred
}

public typealias PredecodeMode = BackgroundPredecodeMode
public typealias PredecodedTranscriptMode = BackgroundPredecodeMode

public enum BackgroundPredecodePolicy {
    public static let minimumSegmentDuration: TimeInterval = 5
    public static let preferredBoundarySilence: TimeInterval = 0.3
    public static let maximumSegmentDuration: TimeInterval = 8

    /// The active tail is intentionally much smaller than a full recording.
    /// Overflow is retained in the stable prefix and marks the accumulator as
    /// requiring a full-session fallback before delivery.
    public static let maximumRevisableTailWords = 96
    public static let maximumTailWords = maximumRevisableTailWords
    public static let maximumPendingSentenceCandidates = 16
    public static let maximumStoredLegacyChunks = 128
    public static let requiredStableHypotheses = 2
    public static let protectedOverlapDuration: TimeInterval = 0.5
    public static let timingMatchTolerance: TimeInterval = 0.65
    public static let overlapTolerance = timingMatchTolerance

    public static func shouldRotate(
        segmentDuration: TimeInterval,
        containsSpeech: Bool,
        trailingSilence: TimeInterval
    ) -> Bool {
        guard containsSpeech,
              segmentDuration >= minimumSegmentDuration
        else {
            return false
        }
        return trailingSilence >= preferredBoundarySilence
            || segmentDuration >= maximumSegmentDuration
    }
}

/// The boundary at which the recognizer has produced enough audio to describe
/// a result. This is not a punctuation or paste decision.
public enum PredecodeDecodeBoundary: String, Codable, Hashable, Sendable {
    case provisional
    case stablePrefix
    case completeSentence
    case finalSession
    case truncated
    case failed
}

/// The boundary at which lexical words may be formatted. Formatting is still
/// expected to preserve the word sequence.
public enum PredecodeFormattingBoundary: String, Codable, Hashable, Sendable {
    case revisableTail
    case stablePrefix
    case finalSession
}

/// Semantic endpoint evidence is independent of the decode window. A pause
/// alone maps to `continuation`, never to an accepted endpoint.
public enum PredecodeSemanticEndpoint: String, Codable, Hashable, Sendable {
    case unknown
    case continuation
    case candidate
    case accepted
    case truncated
    case failed
}

/// Readiness is an observable state for the coordinator. No state here causes
/// paste or submit side effects.
public enum PredecodePasteReadiness: String, Codable, Hashable, Sendable {
    case notReady
    case sentenceCandidate
    case finalReady
    case fallbackRequired
    case cancelled

    public var isReady: Bool {
        switch self {
        case .sentenceCandidate, .finalReady:
            true
        case .notReady, .fallbackRequired, .cancelled:
            false
        }
    }

    public static let candidateReady = Self.sentenceCandidate
    public static let readyForFinalPaste = Self.finalReady
}

public struct PredecodeBoundaries: Codable, Equatable, Hashable, Sendable {
    public let decode: PredecodeDecodeBoundary
    public let formatting: PredecodeFormattingBoundary
    public let semanticEndpoint: PredecodeSemanticEndpoint
    public let pasteReadiness: PredecodePasteReadiness

    public init(
        decode: PredecodeDecodeBoundary = .provisional,
        formatting: PredecodeFormattingBoundary = .revisableTail,
        semanticEndpoint: PredecodeSemanticEndpoint = .unknown,
        pasteReadiness: PredecodePasteReadiness = .notReady
    ) {
        self.decode = decode
        self.formatting = formatting
        self.semanticEndpoint = semanticEndpoint
        self.pasteReadiness = pasteReadiness
    }
}

/// A whole sentence which Pause Mode may hand to a later coordinator. The
/// candidate is data only; the accumulator does not paste it.
public struct PauseModeSentenceCandidate: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let sessionID: UUID?
    public let generation: UInt64
    public let words: [RecognizedWord]
    public let text: String
    public let semanticEndpoint: PredecodeSemanticEndpoint
    public let decodeBoundary: PredecodeDecodeBoundary
    public let formattingBoundary: PredecodeFormattingBoundary
    public let pasteReadiness: PredecodePasteReadiness
    public let isFinal: Bool

    public init(
        id: String,
        sessionID: UUID? = nil,
        generation: UInt64,
        words: [RecognizedWord],
        text: String,
        semanticEndpoint: PredecodeSemanticEndpoint = .accepted,
        decodeBoundary: PredecodeDecodeBoundary = .completeSentence,
        formattingBoundary: PredecodeFormattingBoundary = .stablePrefix,
        pasteReadiness: PredecodePasteReadiness = .sentenceCandidate,
        isFinal: Bool = false
    ) {
        self.id = id
        self.sessionID = sessionID
        self.generation = generation
        self.words = words
        self.text = text
        self.semanticEndpoint = semanticEndpoint
        self.decodeBoundary = decodeBoundary
        self.formattingBoundary = formattingBoundary
        self.pasteReadiness = pasteReadiness
        self.isFinal = isFinal
    }
}

public typealias SentenceCommitCandidate = PauseModeSentenceCandidate

/// Immutable state returned after every accepted or ignored update.
public struct PredecodeSnapshot: Codable, Equatable, Hashable, Sendable {
    public let stablePrefix: [RecognizedWord]
    public let revisableTail: [RecognizedWord]
    public let transcript: String
    public let sentenceCandidates: [PauseModeSentenceCandidate]
    public let boundaries: PredecodeBoundaries
    public let generation: UInt64
    public let mode: BackgroundPredecodeMode
    public let accepted: Bool
    public let ignored: Bool
    public let fallbackRequired: Bool
    public let cancelled: Bool
    public let finalized: Bool

    public init(
        stablePrefix: [RecognizedWord],
        revisableTail: [RecognizedWord],
        transcript: String,
        sentenceCandidates: [PauseModeSentenceCandidate],
        boundaries: PredecodeBoundaries,
        generation: UInt64,
        mode: BackgroundPredecodeMode,
        accepted: Bool,
        ignored: Bool,
        fallbackRequired: Bool,
        cancelled: Bool,
        finalized: Bool
    ) {
        self.stablePrefix = stablePrefix
        self.revisableTail = revisableTail
        self.transcript = transcript
        self.sentenceCandidates = sentenceCandidates
        self.boundaries = boundaries
        self.generation = generation
        self.mode = mode
        self.accepted = accepted
        self.ignored = ignored
        self.fallbackRequired = fallbackRequired
        self.cancelled = cancelled
        self.finalized = finalized
    }

    public var decodeBoundary: PredecodeDecodeBoundary {
        boundaries.decode
    }

    public var formattingBoundary: PredecodeFormattingBoundary {
        boundaries.formatting
    }

    public var punctuationBoundary: PredecodeFormattingBoundary {
        boundaries.formatting
    }

    public var semanticEndpoint: PredecodeSemanticEndpoint {
        boundaries.semanticEndpoint
    }

    public var pasteReadiness: PredecodePasteReadiness {
        boundaries.pasteReadiness
    }
}

public enum PredecodeFinalizationSource: String, Codable, Hashable, Sendable {
    case finalTail
    case fallback
    case accumulated
    case none
}

public struct PredecodeFinalization: Codable, Equatable, Hashable, Sendable {
    public let snapshot: PredecodeSnapshot
    public let source: PredecodeFinalizationSource
    public let finalTailAccepted: Bool
    public let fallbackUsed: Bool

    public init(
        snapshot: PredecodeSnapshot,
        source: PredecodeFinalizationSource,
        finalTailAccepted: Bool,
        fallbackUsed: Bool
    ) {
        self.snapshot = snapshot
        self.source = source
        self.finalTailAccepted = finalTailAccepted
        self.fallbackUsed = fallbackUsed
    }

    public var transcript: String { snapshot.transcript }
    public var stablePrefix: [RecognizedWord] { snapshot.stablePrefix }
    public var revisableTail: [RecognizedWord] { snapshot.revisableTail }
    public var pasteReadiness: PredecodePasteReadiness {
        snapshot.pasteReadiness
    }
    public var fallbackRequired: Bool { snapshot.fallbackRequired }
}

private struct StoredPredecodedWord: Equatable, Hashable, Sendable {
    var word: RecognizedWord
    var stabilityCount: Int
    var lastSourceToken: String
    var truncated: Bool
    var order: UInt64
}

/// Reconciles overlapping streaming results without retaining an unbounded
/// list of strings. Timed words are the source of truth; the legacy String
/// overload is only a migration adapter for the current coordinator.
public struct PredecodedTranscriptAccumulator: Equatable, Sendable {
    private var committedWords: [RecognizedWord] = []
    private var tail: [StoredPredecodedWord] = []
    private var legacyChunkTexts: [String] = []
    private var processedSourceTokens: [String] = []
    private var retiredSessions: [UUID: UInt64] = [:]
    private var legacySessionID: UUID?
    private var acceptedSessionID: UUID?
    private var identityAdopted = false
    private var highestResultEndSeconds: Double?
    private var sequence: UInt64 = 0
    private var renderedTextOverride: String?
    private var lastSemanticEndpoint: PredecodeSemanticEndpoint = .unknown
    private var lastDecodeBoundary: PredecodeDecodeBoundary = .provisional
    private var pendingCandidates: [PauseModeSentenceCandidate] = []
    private var tailLimit: Int

    public private(set) var generation: UInt64
    public private(set) var mode: BackgroundPredecodeMode
    public private(set) var fallbackRequired = false
    public private(set) var cancelled = false
    public private(set) var finalized = false

    public init(
        mode: BackgroundPredecodeMode = .decodeWhileSpeaking,
        sessionID: UUID? = nil,
        generation: UInt64 = 0,
        maximumRevisableTailWords: Int = BackgroundPredecodePolicy.maximumRevisableTailWords,
        maximumTailWords: Int? = nil
    ) {
        let requestedLimit = maximumTailWords ?? maximumRevisableTailWords
        precondition(requestedLimit > 0)
        self.mode = mode
        self.generation = generation
        self.acceptedSessionID = sessionID
        self.identityAdopted = sessionID != nil
        self.tailLimit = requestedLimit
    }

    /// Compatibility view retained for callers which have not migrated to
    /// timed results. Transcript assembly never uses this array.
    public var chunks: [String] { legacyChunkTexts }

    public var stablePrefix: [RecognizedWord] { committedWords }

    public var revisableTail: [RecognizedWord] {
        tail.map(\.word)
    }

    public var pendingSentenceCandidates: [PauseModeSentenceCandidate] {
        pendingCandidates
    }

    public var sentenceCandidates: [PauseModeSentenceCandidate] {
        pendingCandidates
    }

    public var stablePrefixText: String {
        Self.render(committedWords)
    }

    public var revisableTailText: String {
        Self.render(tail.map(\.word))
    }

    public var transcript: String {
        if let renderedTextOverride {
            return renderedTextOverride
        }
        return Self.render(committedWords + tail.map(\.word))
    }

    public var text: String { transcript }

    public var boundaries: PredecodeBoundaries { currentBoundaries }

    public var decodeBoundary: PredecodeDecodeBoundary {
        currentBoundaries.decode
    }

    public var formattingBoundary: PredecodeFormattingBoundary {
        currentBoundaries.formatting
    }

    public var punctuationBoundary: PredecodeFormattingBoundary {
        currentBoundaries.formatting
    }

    public var semanticEndpoint: PredecodeSemanticEndpoint {
        currentBoundaries.semanticEndpoint
    }

    public var pasteReadiness: PredecodePasteReadiness {
        currentBoundaries.pasteReadiness
    }

    public var isEmpty: Bool {
        committedWords.isEmpty && tail.isEmpty && transcript.isEmpty
    }

    public var activeTailWordCount: Int { tail.count }

    public var isMemoryBounded: Bool {
        tail.count <= tailLimit
            && pendingCandidates.count <= BackgroundPredecodePolicy.maximumPendingSentenceCandidates
            && legacyChunkTexts.count <= BackgroundPredecodePolicy.maximumStoredLegacyChunks
    }

    /// Starts a new rich-result session and rejects all prior generations.
    public mutating func begin(
        sessionID: UUID,
        generation: UInt64 = 0,
        mode: BackgroundPredecodeMode? = nil
    ) {
        retireCurrentSession()
        clearContent()
        self.acceptedSessionID = sessionID
        self.identityAdopted = true
        self.generation = generation
        self.cancelled = false
        self.finalized = false
        self.fallbackRequired = false
        if let mode {
            self.mode = mode
        }
    }

    public mutating func setMode(_ mode: BackgroundPredecodeMode) {
        guard !finalized, !cancelled else { return }
        self.mode = mode
    }

    /// Invalidates the active identity. A subsequent rich result may adopt a
    /// new session, but a stale result from the retired generation is ignored.
    public mutating func reset() {
        retireCurrentSession()
        clearContent()
        generation &+= 1
        acceptedSessionID = nil
        identityAdopted = false
        cancelled = false
        finalized = false
        fallbackRequired = false
    }

    /// Cancellation discards both the provisional tail and stable prefix so a
    /// later coordinator cannot accidentally deliver partial text.
    public mutating func cancel() {
        retireCurrentSession()
        clearContent()
        cancelled = true
        finalized = true
        fallbackRequired = false
        lastSemanticEndpoint = .failed
        lastDecodeBoundary = .failed
    }

    public mutating func markBackgroundFailure() {
        guard !cancelled, !finalized else { return }
        fallbackRequired = true
    }

    @discardableResult
    public mutating func takePauseModeSentenceCandidates() -> [PauseModeSentenceCandidate] {
        let result = pendingCandidates
        pendingCandidates.removeAll(keepingCapacity: true)
        return result
    }

    @discardableResult
    public mutating func drainSentenceCandidates() -> [PauseModeSentenceCandidate] {
        takePauseModeSentenceCandidates()
    }

    /// Migration adapter for the current String-only coordinator. It still
    /// tokenizes into stable IDs and uses lexical overlap, rather than joining
    /// independent strings.
    @discardableResult
    public mutating func append(_ transcript: String) -> PredecodeSnapshot {
        guard !cancelled, !finalized else {
            return snapshot(accepted: false, ignored: true)
        }
        let normalized = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return snapshot(accepted: false, ignored: true)
        }

        sequence &+= 1
        let sourceToken = "legacy-\(sequence)"
        legacyChunkTexts.append(normalized)
        if legacyChunkTexts.count > BackgroundPredecodePolicy.maximumStoredLegacyChunks {
            legacyChunkTexts.removeFirst(
                legacyChunkTexts.count - BackgroundPredecodePolicy.maximumStoredLegacyChunks
            )
        }
        let sessionID = legacySessionID ?? {
            let value = UUID()
            legacySessionID = value
            return value
        }()
        let words = normalized
            .split(whereSeparator: \.isWhitespace)
            .enumerated()
            .map { index, substring in
                RecognizedWord(
                    id: StableWordID(
                        sessionID: sessionID,
                        providerDecodeID: sourceToken,
                        wordIndex: index
                    ),
                    text: String(substring)
                )
            }
        return ingestWords(
            words,
            sourceToken: sourceToken,
            completeness: .provisional,
            semanticEndpoint: .continuation,
            resultText: normalized,
            resultSessionID: nil,
            resultGeneration: generation,
            forceFinal: false,
            allowDuplicateSource: false
        )
    }

    @discardableResult
    public mutating func append(_ result: RecognitionResult) -> PredecodeSnapshot {
        ingest(result, forceFinal: false, allowDuplicateSource: false)
    }

    @discardableResult
    public mutating func append(
        _ hypothesis: RecognitionHypothesis,
        sessionID: UUID? = nil,
        generation: UInt64? = nil
    ) -> PredecodeSnapshot {
        let resolvedSessionID = sessionID ?? acceptedSessionID ?? UUID()
        let result = hypothesis.asRecognitionResult(
            sessionID: resolvedSessionID,
            generation: generation ?? self.generation,
            completeness: hypothesis.pass == .provisional
                ? .provisional
                : .stablePrefix
        )
        return append(result)
    }

    @discardableResult
    public mutating func append(
        words: [RecognizedWord],
        text: String? = nil,
        sessionID: UUID? = nil,
        generation: UInt64? = nil,
        completeness: DecodeCompleteness = .provisional,
        requestID: String? = nil
    ) -> PredecodeSnapshot {
        let resolvedSessionID = sessionID ?? acceptedSessionID ?? UUID()
        let resolvedGeneration = generation ?? self.generation
        let result = RecognitionResult(
            sessionID: resolvedSessionID,
            generation: resolvedGeneration,
            engine: .whisperTurbo,
            pass: .provisional,
            text: text ?? Self.render(words),
            words: words,
            completeness: completeness,
            passMetadata: RecognitionPassMetadata(requestID: requestID)
        )
        return append(result)
    }

    @discardableResult
    public mutating func append(
        timedWords: [TimedWord],
        text: String? = nil,
        sessionID: UUID? = nil,
        generation: UInt64? = nil,
        completeness: DecodeCompleteness = .provisional,
        decodeID: String = "timed"
    ) -> PredecodeSnapshot {
        let resolvedSessionID = sessionID ?? acceptedSessionID ?? UUID()
        let words = timedWords.enumerated().map { index, timedWord in
            RecognizedWord(
                id: StableWordID(
                    sessionID: resolvedSessionID,
                    providerDecodeID: decodeID,
                    wordIndex: index
                ),
                text: timedWord.text,
                startSeconds: timedWord.startSeconds,
                endSeconds: timedWord.endSeconds,
                rawEvidence: timedWord.confidence.map {
                    WordEvidence(posterior: $0, availability: .posterior)
                } ?? .unavailable
            )
        }
        return append(
            words: words,
            text: text,
            sessionID: resolvedSessionID,
            generation: generation,
            completeness: completeness,
            requestID: decodeID
        )
    }

    @discardableResult
    public mutating func append(
        words: [TimedWord],
        text: String? = nil,
        sessionID: UUID? = nil,
        generation: UInt64? = nil,
        completeness: DecodeCompleteness = .provisional,
        decodeID: String = "timed"
    ) -> PredecodeSnapshot {
        append(
            timedWords: words,
            text: text,
            sessionID: sessionID,
            generation: generation,
            completeness: completeness,
            decodeID: decodeID
        )
    }

    @discardableResult
    public mutating func append(
        _ words: [TimedWord],
        sessionID: UUID? = nil,
        generation: UInt64? = nil,
        completeness: DecodeCompleteness = .provisional,
        decodeID: String = "timed"
    ) -> PredecodeSnapshot {
        append(
            timedWords: words,
            sessionID: sessionID,
            generation: generation,
            completeness: completeness,
            decodeID: decodeID
        )
    }

    /// Finalizes with the last short decode when it is usable. If that decode
    /// failed or was truncated, the complete-session fallback replaces the
    /// accumulated state. The caller decides whether and where to paste.
    @discardableResult
    public mutating func finalize(
        finalTail: RecognitionResult? = nil,
        fallback: RecognitionResult? = nil
    ) -> PredecodeFinalization {
        guard !cancelled else {
            return PredecodeFinalization(
                snapshot: snapshot(accepted: false, ignored: true),
                source: .none,
                finalTailAccepted: false,
                fallbackUsed: false
            )
        }

        var finalTailAccepted = false
        var fallbackUsed = false
        var source: PredecodeFinalizationSource = .none

        if let finalTail,
           finalTail.completeness != .failed,
           finalTail.completeness != .truncated,
           acceptsIdentity(of: finalTail)
        {
            let update = ingest(
                finalTail,
                forceFinal: true,
                allowDuplicateSource: true
            )
            finalTailAccepted = update.accepted
            if update.accepted {
                source = .finalTail
            }
        }

        if !finalTailAccepted,
           let fallback,
           fallback.completeness != .failed,
           fallback.completeness != .truncated,
           acceptsIdentity(of: fallback)
        {
            if applyFallback(fallback) {
                source = .fallback
                fallbackUsed = true
            }
        }

        if source == .none {
            if fallbackRequired || tail.contains(where: \.truncated) {
                return PredecodeFinalization(
                    snapshot: snapshot(accepted: false, ignored: false),
                    source: .none,
                    finalTailAccepted: false,
                    fallbackUsed: false
                )
            }
            if mode == .pauseMode, !tail.isEmpty {
                let finalWords = tail.map(\.word)
                commitAllTail()
                enqueueCandidate(finalWords, isFinal: true)
            } else {
                commitAllTail()
            }
            source = .accumulated
        }

        finalized = true
        fallbackRequired = false
        lastDecodeBoundary = .finalSession
        lastSemanticEndpoint = .accepted
        // A final tail is bounded audio, so its text must not replace the
        // already committed prefix. Formatting remains a later stage.
        renderedTextOverride = fallbackUsed
            ? fallback?.text.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        if renderedTextOverride?.isEmpty == true {
            renderedTextOverride = nil
        }
        return PredecodeFinalization(
            snapshot: snapshot(accepted: true, ignored: false),
            source: source,
            finalTailAccepted: finalTailAccepted,
            fallbackUsed: fallbackUsed
        )
    }

    @discardableResult
    public mutating func finalize(
        finalTailText: String?,
        fallbackText: String? = nil
    ) -> PredecodeFinalization {
        if let finalTailText {
            let update = append(finalTailText)
            if update.accepted {
                commitAllTail()
                finalized = true
                fallbackRequired = false
                lastDecodeBoundary = .finalSession
                lastSemanticEndpoint = .accepted
                renderedTextOverride = finalTailText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                return PredecodeFinalization(
                    snapshot: snapshot(accepted: true, ignored: false),
                    source: .finalTail,
                    finalTailAccepted: true,
                    fallbackUsed: false
                )
            }
        }
        if let fallbackText, !fallbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resetContentOnly()
            _ = append(fallbackText)
            commitAllTail()
            finalized = true
            fallbackRequired = false
            lastDecodeBoundary = .finalSession
            lastSemanticEndpoint = .accepted
            renderedTextOverride = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
            return PredecodeFinalization(
                snapshot: snapshot(accepted: true, ignored: false),
                source: .fallback,
                finalTailAccepted: false,
                fallbackUsed: true
            )
        }
        return finalize()
    }

    @discardableResult
    public mutating func finish(
        finalTail: RecognitionResult? = nil,
        fallback: RecognitionResult? = nil
    ) -> PredecodeFinalization {
        finalize(finalTail: finalTail, fallback: fallback)
    }

    private mutating func ingest(
        _ result: RecognitionResult,
        forceFinal: Bool,
        allowDuplicateSource: Bool
    ) -> PredecodeSnapshot {
        guard !cancelled, !finalized else {
            return snapshot(accepted: false, ignored: true)
        }
        guard acceptsIdentity(of: result) else {
            return snapshot(accepted: false, ignored: true)
        }
        if result.completeness == .failed {
            fallbackRequired = true
            lastDecodeBoundary = .failed
            lastSemanticEndpoint = .failed
            return snapshot(accepted: false, ignored: false)
        }
        if !allowDuplicateSource {
            let token = sourceToken(for: result)
            guard rememberSourceToken(token) else {
                return snapshot(accepted: false, ignored: true)
            }
        }

        if !identityAdopted {
            acceptedSessionID = result.sessionID
            generation = result.generation
            identityAdopted = true
        }
        let semantic = semanticEndpoint(for: result)
        let words = normalizedWords(from: result)
        return ingestWords(
            words,
            sourceToken: sourceToken(for: result),
            completeness: result.completeness,
            semanticEndpoint: semantic,
            resultText: result.text,
            resultSessionID: result.sessionID,
            resultGeneration: result.generation,
            forceFinal: forceFinal,
            allowDuplicateSource: true
        )
    }

    private mutating func ingestWords(
        _ incomingWords: [RecognizedWord],
        sourceToken: String,
        completeness: DecodeCompleteness,
        semanticEndpoint: PredecodeSemanticEndpoint,
        resultText: String?,
        resultSessionID: UUID?,
        resultGeneration: UInt64,
        forceFinal: Bool,
        allowDuplicateSource: Bool
    ) -> PredecodeSnapshot {
        guard !cancelled, !finalized else {
            return snapshot(accepted: false, ignored: true)
        }
        guard resultGeneration == generation || !identityAdopted else {
            return snapshot(accepted: false, ignored: true)
        }

        if resultSessionID != nil, !identityAdopted {
            acceptedSessionID = resultSessionID
            generation = resultGeneration
            identityAdopted = true
        }
        sequence &+= 1
        renderedTextOverride = nil
        let accepted = reconcile(
            incomingWords,
            sourceToken: sourceToken,
            completeness: completeness
        )
        if !allowDuplicateSource {
            _ = rememberSourceToken(sourceToken)
        }
        lastSemanticEndpoint = semanticEndpoint
        lastDecodeBoundary = decodeBoundary(for: completeness)
        if forceFinal {
            commitAllTail()
        } else {
            commitEligible(
                completeness: completeness,
                semanticEndpoint: semanticEndpoint
            )
        }
        if incomingWords.isEmpty,
           let resultText,
           !resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            // A text-only result is still accepted as a compatibility result;
            // `normalizedWords(from:)` normally creates words before here.
            renderedTextOverride = resultText.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        }
        return snapshot(accepted: accepted || !incomingWords.isEmpty, ignored: false)
    }

    private mutating func reconcile(
        _ incoming: [RecognizedWord],
        sourceToken: String,
        completeness: DecodeCompleteness
    ) -> Bool {
        guard !incoming.isEmpty else { return false }
        let words = incoming
        let bounds = timeBounds(of: words)
        let isOlderWindow: Bool
        if let incomingEnd = bounds?.end,
           let highestResultEndSeconds
        {
            isOlderWindow = incomingEnd + BackgroundPredecodePolicy.timingMatchTolerance
                < highestResultEndSeconds
        } else {
            isOlderWindow = false
        }

        var updatedCurrent = tail
        var matchedCurrent = Set<Int>()
        var unmatchedIncoming: [RecognizedWord] = []

        if words.allSatisfy({ $0.startSeconds == nil })
            && updatedCurrent.allSatisfy({ $0.word.startSeconds == nil })
        {
            let overlap = lexicalOverlap(
                current: updatedCurrent.map(\.word),
                incoming: words
            )
            if overlap > 0 {
                for offset in 0..<overlap {
                    let currentIndex = updatedCurrent.count - overlap + offset
                    matchedCurrent.insert(currentIndex)
                    updatedCurrent[currentIndex] = updated(
                        updatedCurrent[currentIndex],
                        with: words[offset],
                        sourceToken: sourceToken,
                        completeness: completeness
                    )
                }
            }
            unmatchedIncoming = Array(words.dropFirst(overlap))
        } else {
            for incomingWord in words {
                if matchesAny(incomingWord, in: committedWords) {
                    continue
                }
                if let currentIndex = bestMatch(
                    incomingWord,
                    in: updatedCurrent,
                    excluding: matchedCurrent
                ) {
                    matchedCurrent.insert(currentIndex)
                    updatedCurrent[currentIndex] = updated(
                        updatedCurrent[currentIndex],
                        with: incomingWord,
                        sourceToken: sourceToken,
                        completeness: completeness
                    )
                } else {
                    unmatchedIncoming.append(incomingWord)
                }
            }
        }

        let shouldReplaceCoveredWords = !isOlderWindow
            && bounds != nil
            && completeness != .truncated
        let survivors = updatedCurrent.enumerated().compactMap { index, stored -> StoredPredecodedWord? in
            guard !shouldReplaceCoveredWords || matchedCurrent.contains(index) else {
                guard let bounds,
                      let start = stored.word.startSeconds,
                      let end = stored.word.endSeconds
                else {
                    return stored
                }
                let covered = start < bounds.end && end > bounds.start
                return covered ? nil : stored
            }
            return stored
        }

        tail = survivors + unmatchedIncoming.map {
            StoredPredecodedWord(
                word: $0,
                stabilityCount: 1,
                lastSourceToken: sourceToken,
                truncated: completeness == .truncated,
                order: sequence
            )
        }
        sortTail()
        if let end = bounds?.end {
            highestResultEndSeconds = max(highestResultEndSeconds ?? end, end)
        }
        enforceTailLimit()
        return true
    }

    private func bestMatch(
        _ incoming: RecognizedWord,
        in values: [StoredPredecodedWord],
        excluding: Set<Int>
    ) -> Int? {
        if let exact = values.indices.first(where: {
            !excluding.contains($0) && values[$0].word.id == incoming.id
        }) {
            return exact
        }
        if let lexicalAndTimed = values.indices.first(where: {
            !excluding.contains($0)
                && Self.lexicalKey(values[$0].word.text) == Self.lexicalKey(incoming.text)
                && timingCompatible(values[$0].word, incoming)
        }) {
            return lexicalAndTimed
        }
        if let timedReplacement = values.indices.first(where: {
            !excluding.contains($0)
                && timingReplacementCompatible(values[$0].word, incoming)
        }) {
            return timedReplacement
        }
        return values.indices.first(where: {
            !excluding.contains($0)
                && values[$0].word.startSeconds == nil
                && incoming.startSeconds == nil
                && Self.lexicalKey(values[$0].word.text) == Self.lexicalKey(incoming.text)
        })
    }

    private func lexicalOverlap(
        current: [RecognizedWord],
        incoming: [RecognizedWord]
    ) -> Int {
        guard !current.isEmpty, !incoming.isEmpty else { return 0 }
        let maximum = min(current.count, incoming.count)
        guard maximum > 0 else { return 0 }
        for length in stride(from: maximum, through: 1, by: -1) {
            let currentSuffix = current.suffix(length).map { Self.lexicalKey($0.text) }
            let incomingPrefix = incoming.prefix(length).map { Self.lexicalKey($0.text) }
            if currentSuffix == incomingPrefix {
                return length
            }
        }
        return 0
    }

    private func matchesAny(
        _ incoming: RecognizedWord,
        in values: [RecognizedWord]
    ) -> Bool {
        values.contains { existing in
            existing.id == incoming.id
                || (Self.lexicalKey(existing.text) == Self.lexicalKey(incoming.text)
                    && timingCompatible(existing, incoming))
                || timingReplacementCompatible(existing, incoming)
        }
    }

    private func updated(
        _ existing: StoredPredecodedWord,
        with incoming: RecognizedWord,
        sourceToken: String,
        completeness: DecodeCompleteness
    ) -> StoredPredecodedWord {
        var value = existing
        let sameLexical = Self.lexicalKey(existing.word.text) == Self.lexicalKey(incoming.text)
        value.word = incoming
        value.stabilityCount = sameLexical
            ? min(existing.stabilityCount + (existing.lastSourceToken == sourceToken ? 0 : 1), 1_000)
            : 1
        value.lastSourceToken = sourceToken
        value.truncated = completeness == .truncated
        return value
    }

    private mutating func commitEligible(
        completeness: DecodeCompleteness,
        semanticEndpoint: PredecodeSemanticEndpoint
    ) {
        guard !tail.isEmpty else { return }
        switch mode {
        case .deferred:
            return
        case .pauseMode:
            guard semanticEndpoint == .accepted,
                  completeness == .completeSentence || completeness == .finalSession
            else { return }
            let count = tail.last?.truncated == true ? max(0, tail.count - 1) : tail.count
            guard count > 0 else { return }
            let words = commitPrefix(count)
            enqueueCandidate(words, isFinal: false)
        case .decodeWhileSpeaking:
            let count = stableCutCount()
            guard count > 0 else { return }
            _ = commitPrefix(count)
        }
    }

    private func stableCutCount() -> Int {
        guard !tail.isEmpty else { return 0 }
        let timedProtection = highestResultEndSeconds.map {
            $0 - BackgroundPredecodePolicy.protectedOverlapDuration
        }
        var unprotectedCount = 0
        for (index, stored) in tail.enumerated() {
            let timingEligible: Bool
            if let end = stored.word.endSeconds, let timedProtection {
                timingEligible = end <= timedProtection
            } else {
                timingEligible = index < tail.count - 8
            }
            guard stored.stabilityCount >= BackgroundPredecodePolicy.requiredStableHypotheses,
                  timingEligible,
                  !stored.truncated
            else {
                break
            }
            unprotectedCount += 1
        }
        return unprotectedCount
    }

    @discardableResult
    private mutating func commitPrefix(_ count: Int) -> [RecognizedWord] {
        guard count > 0 else { return [] }
        let boundedCount = min(count, tail.count)
        let words = tail.prefix(boundedCount).map(\.word)
        committedWords.append(contentsOf: words)
        tail.removeFirst(boundedCount)
        return words
    }

    private mutating func commitAllTail() {
        guard !tail.isEmpty else { return }
        _ = commitPrefix(tail.count)
    }

    private mutating func enqueueCandidate(
        _ words: [RecognizedWord],
        isFinal: Bool
    ) {
        guard !words.isEmpty else { return }
        let firstID = words.first?.id.rawValue ?? "empty"
        let lastID = words.last?.id.rawValue ?? firstID
        let id = "\(generation):\(firstID):\(lastID)"
        let candidate = PauseModeSentenceCandidate(
            id: id,
            sessionID: acceptedSessionID,
            generation: generation,
            words: words,
            text: Self.render(words),
            semanticEndpoint: .accepted,
            decodeBoundary: isFinal ? .finalSession : .completeSentence,
            formattingBoundary: isFinal ? .finalSession : .stablePrefix,
            pasteReadiness: .sentenceCandidate,
            isFinal: isFinal
        )
        pendingCandidates.append(candidate)
        if pendingCandidates.count > BackgroundPredecodePolicy.maximumPendingSentenceCandidates {
            pendingCandidates.removeFirst(
                pendingCandidates.count
                    - BackgroundPredecodePolicy.maximumPendingSentenceCandidates
            )
        }
    }

    private mutating func enforceTailLimit() {
        guard tail.count > tailLimit else { return }
        let overflow = tail.count - tailLimit
        // The discarded revision window is represented in the stable prefix,
        // but a complete-session fallback remains mandatory for final safety.
        _ = commitPrefix(overflow)
        fallbackRequired = true
    }

    private mutating func applyFallback(_ result: RecognitionResult) -> Bool {
        let words = normalizedWords(from: result)
        guard !words.isEmpty || !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        committedWords = words
        tail.removeAll(keepingCapacity: true)
        pendingCandidates.removeAll(keepingCapacity: true)
        fallbackRequired = false
        lastDecodeBoundary = .finalSession
        lastSemanticEndpoint = .accepted
        highestResultEndSeconds = timeBounds(of: words)?.end
        if !identityAdopted {
            acceptedSessionID = result.sessionID
            generation = result.generation
            identityAdopted = true
        }
        renderedTextOverride = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if renderedTextOverride?.isEmpty == true {
            renderedTextOverride = nil
        }
        _ = rememberSourceToken(sourceToken(for: result))
        return true
    }

    private func normalizedWords(from result: RecognitionResult) -> [RecognizedWord] {
        if !result.words.isEmpty {
            return result.words.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .sorted(by: Self.wordOrder)
        }
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let decodeID = result.passMetadata.requestID ?? "text-\(result.generation)"
        return text
            .split(whereSeparator: \.isWhitespace)
            .enumerated()
            .map { index, substring in
                RecognizedWord(
                    id: StableWordID(
                        sessionID: result.sessionID,
                        providerDecodeID: decodeID,
                        wordIndex: index
                    ),
                    text: String(substring)
                )
            }
    }

    private func acceptsIdentity(of result: RecognitionResult) -> Bool {
        if let retiredGeneration = retiredSessions[result.sessionID],
           result.generation <= retiredGeneration
        {
            return false
        }
        if identityAdopted {
            return result.sessionID == acceptedSessionID && result.generation == generation
        }
        return true
    }

    private func sourceToken(for result: RecognitionResult) -> String {
        if let requestID = result.passMetadata.requestID, !requestID.isEmpty {
            return requestID
        }
        if let first = result.words.first {
            return first.id.providerDecodeID
        }
        return "result-\(result.sessionID.uuidString)-\(result.generation)-\(result.text)"
    }

    private mutating func rememberSourceToken(_ token: String) -> Bool {
        guard !processedSourceTokens.contains(token) else { return false }
        processedSourceTokens.append(token)
        if processedSourceTokens.count > 128 {
            processedSourceTokens.removeFirst(processedSourceTokens.count - 128)
        }
        return true
    }

    private func semanticEndpoint(
        for result: RecognitionResult
    ) -> PredecodeSemanticEndpoint {
        if result.completeness == .failed { return .failed }
        if result.completeness == .truncated || result.utteranceEvidence.truncated {
            return .truncated
        }
        switch result.completeness {
        case .completeSentence, .finalSession:
            return .accepted
        case .stablePrefix:
            return .candidate
        case .provisional:
            return .continuation
        case .truncated:
            return .truncated
        case .failed:
            return .failed
        }
    }

    private func decodeBoundary(
        for completeness: DecodeCompleteness
    ) -> PredecodeDecodeBoundary {
        switch completeness {
        case .provisional: return .provisional
        case .stablePrefix: return .stablePrefix
        case .completeSentence: return .completeSentence
        case .finalSession: return .finalSession
        case .truncated: return .truncated
        case .failed: return .failed
        }
    }

    private var currentBoundaries: PredecodeBoundaries {
        let formatting: PredecodeFormattingBoundary
        if finalized {
            formatting = .finalSession
        } else if !committedWords.isEmpty {
            formatting = .stablePrefix
        } else {
            formatting = .revisableTail
        }
        let readiness: PredecodePasteReadiness
        if cancelled {
            readiness = .cancelled
        } else if fallbackRequired {
            readiness = .fallbackRequired
        } else if finalized {
            readiness = .finalReady
        } else if !pendingCandidates.isEmpty && mode == .pauseMode {
            readiness = .sentenceCandidate
        } else {
            readiness = .notReady
        }
        return PredecodeBoundaries(
            decode: lastDecodeBoundary,
            formatting: formatting,
            semanticEndpoint: lastSemanticEndpoint,
            pasteReadiness: readiness
        )
    }

    private func snapshot(accepted: Bool, ignored: Bool) -> PredecodeSnapshot {
        PredecodeSnapshot(
            stablePrefix: committedWords,
            revisableTail: tail.map(\.word),
            transcript: transcript,
            sentenceCandidates: pendingCandidates,
            boundaries: currentBoundaries,
            generation: generation,
            mode: mode,
            accepted: accepted,
            ignored: ignored,
            fallbackRequired: fallbackRequired,
            cancelled: cancelled,
            finalized: finalized
        )
    }

    private mutating func retireCurrentSession() {
        if let acceptedSessionID {
            retiredSessions[acceptedSessionID] = generation
            if retiredSessions.count > 8,
               let oldest = retiredSessions.keys.first
            {
                retiredSessions.removeValue(forKey: oldest)
            }
        }
        if let legacySessionID {
            retiredSessions[legacySessionID] = generation
        }
    }

    private mutating func clearContent() {
        committedWords.removeAll(keepingCapacity: true)
        tail.removeAll(keepingCapacity: true)
        legacyChunkTexts.removeAll(keepingCapacity: true)
        processedSourceTokens.removeAll(keepingCapacity: true)
        pendingCandidates.removeAll(keepingCapacity: true)
        highestResultEndSeconds = nil
        renderedTextOverride = nil
        lastSemanticEndpoint = .unknown
        lastDecodeBoundary = .provisional
        legacySessionID = nil
    }

    private mutating func resetContentOnly() {
        committedWords.removeAll(keepingCapacity: true)
        tail.removeAll(keepingCapacity: true)
        pendingCandidates.removeAll(keepingCapacity: true)
        fallbackRequired = false
        finalized = false
        renderedTextOverride = nil
        highestResultEndSeconds = nil
        lastSemanticEndpoint = .unknown
        lastDecodeBoundary = .provisional
    }

    private mutating func sortTail() {
        tail.sort { lhs, rhs in
            if lhs.word.startSeconds == nil, rhs.word.startSeconds == nil {
                if lhs.order != rhs.order {
                    return lhs.order < rhs.order
                }
            }
            return Self.wordOrder(lhs.word, rhs.word)
        }
    }

    private static func wordOrder(_ lhs: RecognizedWord, _ rhs: RecognizedWord) -> Bool {
        if let left = lhs.startSeconds, let right = rhs.startSeconds {
            if left != right {
                return left < right
            }
        } else if lhs.startSeconds == nil, rhs.startSeconds != nil {
            return false
        } else if lhs.startSeconds != nil, rhs.startSeconds == nil {
            return true
        }

        if let left = lhs.endSeconds, let right = rhs.endSeconds,
           left != right
        {
            return left < right
        }
        return lhs.id.rawValue < rhs.id.rawValue
    }

    private func timeBounds(
        of words: [RecognizedWord]
    ) -> (start: Double, end: Double)? {
        let starts = words.compactMap(\.startSeconds)
        let ends = words.compactMap(\.endSeconds)
        guard let start = starts.min(), let end = ends.max(), end >= start else {
            return nil
        }
        return (start, end)
    }

    private func timingCompatible(
        _ lhs: RecognizedWord,
        _ rhs: RecognizedWord
    ) -> Bool {
        guard let lhsStart = lhs.startSeconds,
              let lhsEnd = lhs.endSeconds,
              let rhsStart = rhs.startSeconds,
              let rhsEnd = rhs.endSeconds
        else { return false }
        let tolerance = BackgroundPredecodePolicy.timingMatchTolerance
        let overlap = min(lhsEnd, rhsEnd) - max(lhsStart, rhsStart)
        return overlap >= -tolerance
            || abs(lhsStart - rhsStart) <= tolerance
            || abs(lhsEnd - rhsEnd) <= tolerance
    }

    private func timingReplacementCompatible(
        _ lhs: RecognizedWord,
        _ rhs: RecognizedWord
    ) -> Bool {
        guard let lhsStart = lhs.startSeconds,
              let lhsEnd = lhs.endSeconds,
              let rhsStart = rhs.startSeconds,
              let rhsEnd = rhs.endSeconds
        else { return false }
        let tolerance = BackgroundPredecodePolicy.timingMatchTolerance / 2
        let overlap = min(lhsEnd, rhsEnd) - max(lhsStart, rhsStart)
        let shorterDuration = max(0.001, min(lhsEnd - lhsStart, rhsEnd - rhsStart))
        return overlap / shorterDuration >= 0.5
            || (abs(lhsStart - rhsStart) <= tolerance
                && abs(lhsEnd - rhsEnd) <= tolerance)
    }

    private static func lexicalKey(_ text: String) -> String {
        let scalars = text.lowercased().unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || scalar == "'"
                || scalar == "-"
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func render(_ words: [RecognizedWord]) -> String {
        render(words.map(\.text))
    }

    private static func render(_ words: [String]) -> String {
        var result = ""
        for rawWord in words {
            let word = rawWord.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { continue }
            if result.isEmpty {
                result = word
                continue
            }
            let startsWithClosingPunctuation = word.first.map {
                ".,!?;:%)]}".contains($0)
            } ?? false
            let previousEndsWithOpeningPunctuation = result.last.map {
                "([{\"".contains($0)
            } ?? false
            if startsWithClosingPunctuation || previousEndsWithOpeningPunctuation {
                result += word
            } else {
                result += " " + word
            }
        }
        return result
    }
}
