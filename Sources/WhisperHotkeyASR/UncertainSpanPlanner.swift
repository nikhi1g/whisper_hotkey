import Foundation
import WhisperHotkeyCore

private func safeClosedRange(
    _ range: ClosedRange<Double>
) -> ClosedRange<Double>? {
    guard range.lowerBound.isFinite,
          range.upperBound.isFinite,
          range.lowerBound <= range.upperBound
    else { return nil }
    return range
}

/// A VAD interval supplied to the planner as timing-only evidence.
///
/// The planner never reads an audio buffer.  VAD intervals are used only to
/// choose safer boundaries for a verifier request.
public struct UncertainSpanVADRegion: Codable, Hashable, Sendable {
    public let startSeconds: Double
    public let endSeconds: Double

    public init(startSeconds: Double, endSeconds: Double) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }

    public init(start: Double, end: Double) {
        self.init(startSeconds: start, endSeconds: end)
    }

    public var durationSeconds: Double { endSeconds - startSeconds }

    /// Invalid externally supplied timing must remain observable as missing
    /// evidence rather than trapping while constructing a ClosedRange.
    public var range: ClosedRange<Double>? {
        guard startSeconds.isFinite,
              endSeconds.isFinite,
              startSeconds <= endSeconds
        else { return nil }
        return startSeconds...endSeconds
    }
}

/// Compatibility spelling for callers that call a VAD interval a boundary.
public typealias UncertainSpanVADBoundary = UncertainSpanVADRegion
public typealias VADRegion = UncertainSpanVADRegion

/// Evidence that a word may have been deleted between two timed regions.
///
/// A gap is intentionally independent of a primary word ID: an insertion
/// candidate may have no corresponding primary word.  Optional neighboring
/// IDs are retained when a provider already has that information.
public struct DeletionGapEvidence: Codable, Hashable, Sendable {
    public let startSeconds: Double
    public let endSeconds: Double
    public let errorProbability: Double
    public let leftWordID: StableWordID?
    public let rightWordID: StableWordID?
    public let explicitlyFlagged: Bool

    public init(
        startSeconds: Double,
        endSeconds: Double,
        errorProbability: Double,
        leftWordID: StableWordID? = nil,
        rightWordID: StableWordID? = nil,
        explicitlyFlagged: Bool = true
    ) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.errorProbability = errorProbability
        self.leftWordID = leftWordID
        self.rightWordID = rightWordID
        self.explicitlyFlagged = explicitlyFlagged
    }

    /// Alternate spelling used by confidence pipelines.
    public init(
        startSeconds: Double,
        endSeconds: Double,
        risk: Double,
        leftWordID: StableWordID? = nil,
        rightWordID: StableWordID? = nil,
        explicitlyFlagged: Bool = true
    ) {
        self.init(
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            errorProbability: risk,
            leftWordID: leftWordID,
            rightWordID: rightWordID,
            explicitlyFlagged: explicitlyFlagged
        )
    }

    public init(
        gapStartSeconds: Double,
        gapEndSeconds: Double,
        deletionProbability: Double,
        leftWordID: StableWordID? = nil,
        rightWordID: StableWordID? = nil,
        explicitlyFlagged: Bool = true
    ) {
        self.init(
            startSeconds: gapStartSeconds,
            endSeconds: gapEndSeconds,
            errorProbability: deletionProbability,
            leftWordID: leftWordID,
            rightWordID: rightWordID,
            explicitlyFlagged: explicitlyFlagged
        )
    }

    public var risk: Double { errorProbability }
    public var durationSeconds: Double { endSeconds - startSeconds }
}

/// Short compatibility spelling for deletion-gap evidence.
public typealias GapEvidence = DeletionGapEvidence

/// Catastrophic evidence requests a bounded sentence repair instead of a
/// collection of ordinary word repairs.  Every flag is content-free.
public struct CatastrophicEvidence: Codable, Hashable, Sendable {
    public let primaryOutputEmpty: Bool
    public let strongSpeechEvidence: Bool
    public let severeRepetition: Bool
    public let alignmentImpossible: Bool
    public let mostWordsUncertain: Bool
    public let truncatedBoundary: Bool
    public let invalidTimestampMonotonicity: Bool
    public let sentenceRegion: ClosedRange<Double>?

    public init(
        primaryOutputEmpty: Bool = false,
        strongSpeechEvidence: Bool = false,
        severeRepetition: Bool = false,
        alignmentImpossible: Bool = false,
        mostWordsUncertain: Bool = false,
        truncatedBoundary: Bool = false,
        invalidTimestampMonotonicity: Bool = false,
        sentenceRegion: ClosedRange<Double>? = nil
    ) {
        self.primaryOutputEmpty = primaryOutputEmpty
        self.strongSpeechEvidence = strongSpeechEvidence
        self.severeRepetition = severeRepetition
        self.alignmentImpossible = alignmentImpossible
        self.mostWordsUncertain = mostWordsUncertain
        self.truncatedBoundary = truncatedBoundary
        self.invalidTimestampMonotonicity = invalidTimestampMonotonicity
        self.sentenceRegion = sentenceRegion
    }

    /// Convenience spelling for the first catastrophic condition in the
    /// packet.  It remains separate from `primaryOutputEmpty` so an empty
    /// result without speech does not trigger a verifier.
    public init(
        primaryEmptyDespiteStrongSpeech: Bool,
        severeRepetition: Bool = false,
        alignmentImpossible: Bool = false,
        mostWordsUncertain: Bool = false,
        truncatedBoundary: Bool = false,
        invalidTimestampMonotonicity: Bool = false,
        sentenceRegion: ClosedRange<Double>? = nil
    ) {
        self.init(
            primaryOutputEmpty: primaryEmptyDespiteStrongSpeech,
            strongSpeechEvidence: primaryEmptyDespiteStrongSpeech,
            severeRepetition: severeRepetition,
            alignmentImpossible: alignmentImpossible,
            mostWordsUncertain: mostWordsUncertain,
            truncatedBoundary: truncatedBoundary,
            invalidTimestampMonotonicity: invalidTimestampMonotonicity,
            sentenceRegion: sentenceRegion
        )
    }

    public init(
        emptyPrimaryDespiteSpeech: Bool,
        repetitionRisk: Bool = false,
        alignmentFailure: Bool = false,
        sentenceRegion: ClosedRange<Double>? = nil
    ) {
        self.init(
            primaryEmptyDespiteStrongSpeech: emptyPrimaryDespiteSpeech,
            severeRepetition: repetitionRisk,
            alignmentImpossible: alignmentFailure,
            sentenceRegion: sentenceRegion
        )
    }

    public static let none = Self()

    public var primaryEmptyDespiteStrongSpeech: Bool {
        primaryOutputEmpty && strongSpeechEvidence
    }

    public var requiresSentenceFallback: Bool {
        primaryEmptyDespiteStrongSpeech
            || severeRepetition
            || alignmentImpossible
            || mostWordsUncertain
            || truncatedBoundary
            || invalidTimestampMonotonicity
    }
}

/// Reasons exposed to benchmark/control code when a bounded plan is reduced.
public enum UncertainSpanPlanningIssue: String, Codable, Hashable, Sendable {
    case wordBudgetExceeded
    case gapEvidenceBudgetExceeded
    case spanBudgetExceeded
    case verifierAudioBudgetExceeded
    case perSpanDurationCapped
    case contextTextCapped
    case catastrophicRegionCapped
    case catastrophicWordBudgetExceeded
}

/// Fail-closed causes.  These values are safe to expose to callers and do not
/// include transcript or audio content.
public enum UncertainSpanPlanningFailure: String, Codable, Hashable, Sendable, Error {
    case invalidSessionDuration
    case invalidSampleRate
    case invalidConfiguration
    case duplicateWordID
    case missingWordTiming
    case invalidWordTiming
    case nonMonotonicWordTiming
    case invalidWordProbability
    case invalidGapTiming
    case nonMonotonicGapTiming
    case invalidGapProbability
    case invalidVADTiming
    case nonMonotonicVADTiming
    case missingBoundedSentenceRegion
    case invalidSentenceRegion
    case sentenceRegionOutsideSession
    case integerSampleOverflow
}

/// Why a verifier request was admitted to a span.
public enum UncertainSpanTrigger: String, Codable, Hashable, Sendable {
    case uncertainWord
    case deletionGap
    case catastrophicFallback
}

/// Why a candidate risk was not selected.  Keeping this metadata makes
/// budget degradation observable without retaining text or audio.
public enum UnselectedSpanReason: String, Codable, Hashable, Sendable {
    case spanBudget
    case verifierAudioBudget
    case lowerExpectedRepairValue
    case wordBudget
    case invalidTiming
}

/// Per-word risk metadata retained for selected and unselected risks.
public struct UncertainWordRiskMetadata: Codable, Hashable, Sendable {
    public let wordID: StableWordID
    public let wordIndex: Int
    public let errorProbability: Double
    public let selected: Bool
    public let reason: UnselectedSpanReason?

    public init(
        wordID: StableWordID,
        wordIndex: Int,
        errorProbability: Double,
        selected: Bool,
        reason: UnselectedSpanReason? = nil
    ) {
        self.wordID = wordID
        self.wordIndex = wordIndex
        self.errorProbability = errorProbability
        self.selected = selected
        self.reason = reason
    }
}

/// A risk record for a candidate span that was not admitted to the verifier
/// budget.  It intentionally contains only IDs, timing, and numeric metadata.
public struct UnselectedSpanRiskMetadata: Codable, Hashable, Sendable {
    public let startSeconds: Double
    public let endSeconds: Double
    public let riskScore: Double
    public let expectedRepairValue: Double
    public let trigger: UncertainSpanTrigger
    public let authorizedWordIDs: Set<StableWordID>
    public let reason: UnselectedSpanReason

    public init(
        startSeconds: Double,
        endSeconds: Double,
        riskScore: Double,
        expectedRepairValue: Double,
        trigger: UncertainSpanTrigger,
        authorizedWordIDs: Set<StableWordID>,
        reason: UnselectedSpanReason
    ) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.riskScore = riskScore
        self.expectedRepairValue = expectedRepairValue
        self.trigger = trigger
        self.authorizedWordIDs = authorizedWordIDs
        self.reason = reason
    }

    public var durationSeconds: Double { endSeconds - startSeconds }
}

/// A typed, bounded sentence fallback request.
public struct BoundedSentenceFallbackRequest: Codable, Hashable, Sendable {
    public let reason: UncertainSpanTrigger
    public let startSeconds: Double
    public let endSeconds: Double
    public let startSample: Int64
    public let endSample: Int64
    public let sampleRate: Int
    public let authorizedWordIDs: Set<StableWordID>
    public let authorizedTimeRange: ClosedRange<Double>
    public let contextText: String

    public init(
        reason: UncertainSpanTrigger = .catastrophicFallback,
        startSeconds: Double,
        endSeconds: Double,
        startSample: Int64,
        endSample: Int64,
        sampleRate: Int,
        authorizedWordIDs: Set<StableWordID>,
        authorizedTimeRange: ClosedRange<Double>,
        contextText: String
    ) {
        self.reason = reason
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.startSample = startSample
        self.endSample = endSample
        self.sampleRate = sampleRate
        self.authorizedWordIDs = authorizedWordIDs
        self.authorizedTimeRange = authorizedTimeRange
        self.contextText = contextText
    }

    public var durationSeconds: Double { endSeconds - startSeconds }
    public var timeRange: ClosedRange<Double> { authorizedTimeRange }
    public var sampleRange: ClosedRange<Int64>? {
        guard startSample <= endSample else { return nil }
        return startSample...endSample
    }
    public var authorizedPrimaryWordIDs: Set<StableWordID> {
        authorizedWordIDs
    }
    public var authorizedPrimaryTimeRange: ClosedRange<Double> {
        authorizedTimeRange
    }

    public var fusionConfiguration: CandidateFusionConfiguration {
        CandidateFusionConfiguration(
            maximumWordsPerSpan: CandidateFusionConfiguration.hardMaximumWordsPerSpan,
            authorizedWordIDs: authorizedWordIDs,
            authorizedTimeRange: safeClosedRange(authorizedTimeRange)
        )
    }

    public var candidateFusionConfiguration: CandidateFusionConfiguration {
        fusionConfiguration
    }
}

/// One verifier request.  It contains a sample range and a timestamp range;
/// it never owns or copies audio.  `authorizedWordIDs` are the exact primary
/// IDs the fusion guard may unlock for this request.
public struct UncertainAudioSpan: Codable, Hashable, Sendable {
    public let id: Int
    public let startSeconds: Double
    public let endSeconds: Double
    public let startSample: Int64
    public let endSample: Int64
    public let sampleRate: Int
    public let authorizedWordIDs: Set<StableWordID>
    public let authorizedTimeRange: ClosedRange<Double>
    public let trigger: UncertainSpanTrigger
    public let riskScore: Double
    public let expectedRepairValue: Double
    public let contextText: String

    public init(
        id: Int,
        startSeconds: Double,
        endSeconds: Double,
        startSample: Int64,
        endSample: Int64,
        sampleRate: Int,
        authorizedWordIDs: Set<StableWordID>,
        authorizedTimeRange: ClosedRange<Double>,
        trigger: UncertainSpanTrigger,
        riskScore: Double,
        expectedRepairValue: Double,
        contextText: String
    ) {
        self.id = id
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.startSample = startSample
        self.endSample = endSample
        self.sampleRate = sampleRate
        self.authorizedWordIDs = authorizedWordIDs
        self.authorizedTimeRange = authorizedTimeRange
        self.trigger = trigger
        self.riskScore = riskScore
        self.expectedRepairValue = expectedRepairValue
        self.contextText = contextText
    }

    public var durationSeconds: Double { endSeconds - startSeconds }
    public var sampleRange: ClosedRange<Int64>? {
        guard startSample <= endSample else { return nil }
        return startSample...endSample
    }
    public var timestampRange: ClosedRange<Double> { authorizedTimeRange }
    public var timeRange: ClosedRange<Double> { authorizedTimeRange }
    public var primaryWordIDs: Set<StableWordID> { authorizedWordIDs }
    public var authorizedPrimaryWordIDs: Set<StableWordID> {
        authorizedWordIDs
    }
    public var authorizedPrimaryTimeRange: ClosedRange<Double> {
        authorizedTimeRange
    }

    public var fusionConfiguration: CandidateFusionConfiguration {
        CandidateFusionConfiguration(
            maximumWordsPerSpan: CandidateFusionConfiguration.hardMaximumWordsPerSpan,
            authorizedWordIDs: authorizedWordIDs,
            authorizedTimeRange: safeClosedRange(authorizedTimeRange)
        )
    }

    public var candidateFusionConfiguration: CandidateFusionConfiguration {
        fusionConfiguration
    }
}

/// The planner's status is intentionally separate from its issue list: a
/// normal plan can be degraded by a budget while a fail-closed plan has no
/// verifier spans at all.
public enum UncertainSpanPlanStatus: String, Codable, Hashable, Sendable {
    case noRepair
    case planned
    case degraded
    case catastrophicFallback
    case failed
}

/// Complete deterministic planner output.
public struct UncertainSpanPlan: Codable, Hashable, Sendable {
    public let status: UncertainSpanPlanStatus
    public let spans: [UncertainAudioSpan]
    public let unselectedSpanRisks: [UnselectedSpanRiskMetadata]
    public let wordRisks: [UncertainWordRiskMetadata]
    public let issues: [UncertainSpanPlanningIssue]
    public let failure: UncertainSpanPlanningFailure?
    public let fallbackRequest: BoundedSentenceFallbackRequest?
    public let sessionDurationSeconds: Double
    public let totalVerifierDurationSeconds: Double

    public init(
        status: UncertainSpanPlanStatus,
        spans: [UncertainAudioSpan],
        unselectedSpanRisks: [UnselectedSpanRiskMetadata] = [],
        wordRisks: [UncertainWordRiskMetadata] = [],
        issues: [UncertainSpanPlanningIssue] = [],
        failure: UncertainSpanPlanningFailure? = nil,
        fallbackRequest: BoundedSentenceFallbackRequest? = nil,
        sessionDurationSeconds: Double,
        totalVerifierDurationSeconds: Double
    ) {
        self.status = status
        self.spans = spans
        self.unselectedSpanRisks = unselectedSpanRisks
        self.wordRisks = wordRisks
        self.issues = issues
        self.failure = failure
        self.fallbackRequest = fallbackRequest
        self.sessionDurationSeconds = sessionDurationSeconds
        self.totalVerifierDurationSeconds = totalVerifierDurationSeconds
    }

    public var selectedSpans: [UncertainAudioSpan] { spans }
    public var fallback: BoundedSentenceFallbackRequest? { fallbackRequest }
    public var unselectedRisks: [UnselectedSpanRiskMetadata] {
        unselectedSpanRisks
    }
    public var isFailClosed: Bool { failure != nil && spans.isEmpty }
    public var requiresVerifier: Bool { !spans.isEmpty }
    public var totalVerifierAudioRatio: Double {
        guard sessionDurationSeconds > 0, sessionDurationSeconds.isFinite else {
            return 0
        }
        return totalVerifierDurationSeconds / sessionDurationSeconds
    }

    public var authorizedWordIDs: Set<StableWordID> {
        spans.reduce(into: Set<StableWordID>()) { result, span in
            result.formUnion(span.authorizedWordIDs)
        }
    }

    public var authorizedTimeRanges: [ClosedRange<Double>] {
        spans.map(\.authorizedTimeRange)
    }

    public var fusionConfigurations: [CandidateFusionConfiguration] {
        spans.map(\.fusionConfiguration)
    }

    public var authorizedPrimaryWordIDs: Set<StableWordID> {
        authorizedWordIDs
    }
}

/// Planner configuration.  The static experiment defaults are explicitly
/// uncalibrated; a calibrated operating point must be supplied by the caller.
public struct UncertainSpanPlannerConfiguration: Codable, Hashable, Sendable {
    public static let hardMaximumWordsPerSpan = 128
    public static let hardMaximumGapEvidence = 256
    public static let hardMaximumSpanCount = 32
    public static let hardMaximumSpanDurationSeconds = 30.0
    public static let hardMaximumContextCharacters = 320

    public let threshold: ConfidenceThreshold
    public let minimumRepairSpanDurationSeconds: Double
    public let maximumRepairSpanDurationSeconds: Double
    public let maximumMergedGapSeconds: Double
    public let leftPaddingSeconds: Double
    public let rightPaddingSeconds: Double
    public let maximumVerifierAudioRatio: Double
    public let maximumSpanCount: Int
    public let maximumWordsPerSpan: Int
    public let maximumGapEvidenceCount: Int
    public let maximumContextCharacters: Int
    public let contextWordRadius: Int
    public let sampleRate: Int
    public let adjustToWordBoundaries: Bool
    public let adjustToVADBoundaries: Bool
    public let maximumCatastrophicSpanDurationSeconds: Double
    public let verifierCostPerSecond: Double
    public let anchorRiskWeight: Double
    public let allowWholeSessionFallback: Bool

    public init(
        threshold: ConfidenceThreshold = .uncalibrated(0.35),
        minimumRepairSpanDurationSeconds: Double = 0.8,
        maximumRepairSpanDurationSeconds: Double = 8.0,
        maximumMergedGapSeconds: Double = 0.35,
        leftPaddingSeconds: Double = 0.35,
        rightPaddingSeconds: Double = 0.35,
        maximumVerifierAudioRatio: Double = 0.25,
        maximumSpanCount: Int = 2,
        maximumWordsPerSpan: Int = 96,
        maximumGapEvidenceCount: Int = 64,
        maximumContextCharacters: Int = 240,
        contextWordRadius: Int = 2,
        sampleRate: Int = 16_000,
        adjustToWordBoundaries: Bool = true,
        adjustToVADBoundaries: Bool = true,
        maximumCatastrophicSpanDurationSeconds: Double = 30.0,
        verifierCostPerSecond: Double = 0.05,
        anchorRiskWeight: Double = 0.1,
        allowWholeSessionFallback: Bool = false
    ) {
        self.threshold = threshold
        self.minimumRepairSpanDurationSeconds = minimumRepairSpanDurationSeconds
        self.maximumRepairSpanDurationSeconds = maximumRepairSpanDurationSeconds
        self.maximumMergedGapSeconds = maximumMergedGapSeconds
        self.leftPaddingSeconds = leftPaddingSeconds
        self.rightPaddingSeconds = rightPaddingSeconds
        self.maximumVerifierAudioRatio = maximumVerifierAudioRatio
        self.maximumSpanCount = maximumSpanCount
        self.maximumWordsPerSpan = maximumWordsPerSpan
        self.maximumGapEvidenceCount = maximumGapEvidenceCount
        self.maximumContextCharacters = maximumContextCharacters
        self.contextWordRadius = contextWordRadius
        self.sampleRate = sampleRate
        self.adjustToWordBoundaries = adjustToWordBoundaries
        self.adjustToVADBoundaries = adjustToVADBoundaries
        self.maximumCatastrophicSpanDurationSeconds =
            maximumCatastrophicSpanDurationSeconds
        self.verifierCostPerSecond = verifierCostPerSecond
        self.anchorRiskWeight = anchorRiskWeight
        self.allowWholeSessionFallback = allowWholeSessionFallback
    }

    /// Initial packet bounds.  The threshold is intentionally uncalibrated.
    public static let uncalibratedExperimentDefaults = Self()
    public static let initialUncalibrated = Self.uncalibratedExperimentDefaults
    public static let `default` = Self.uncalibratedExperimentDefaults

    public var errorProbabilityThreshold: Double { threshold.errorProbability }
    public var wordErrorProbabilityThreshold: Double {
        threshold.errorProbability
    }
    public var maximumVerifierCoverageRatio: Double {
        maximumVerifierAudioRatio
    }
    public var maximumTotalVerifierAudioRatio: Double {
        maximumVerifierAudioRatio
    }
    public var minimumSpanDurationSeconds: Double {
        minimumRepairSpanDurationSeconds
    }
    public var maximumSpanDurationSeconds: Double {
        maximumRepairSpanDurationSeconds
    }
    public var maximumMergedGap: Double { maximumMergedGapSeconds }
    public var verifierAudioRatio: Double { maximumVerifierAudioRatio }
    public var maximumSpanDuration: Double {
        maximumRepairSpanDurationSeconds
    }
    public var minimumSpanDuration: Double {
        minimumRepairSpanDurationSeconds
    }
    public var maximumWordCount: Int { maximumWordsPerSpan }
    public var maximumGapCount: Int { maximumGapEvidenceCount }
    public var maximumContextLength: Int { maximumContextCharacters }
}

/// Deterministic, audio-free uncertain span planner.
public struct UncertainSpanPlanner: Sendable {
    public let configuration: UncertainSpanPlannerConfiguration

    public init(
        configuration: UncertainSpanPlannerConfiguration =
            .uncalibratedExperimentDefaults
    ) {
        self.configuration = configuration
    }

    public func plan(
        words: [RecognizedWord],
        deletionGaps: [DeletionGapEvidence] = [],
        catastrophicEvidence: CatastrophicEvidence = .none,
        sessionDurationSeconds: Double,
        sentenceRegion: ClosedRange<Double>? = nil,
        vadRegions: [UncertainSpanVADRegion] = []
    ) -> UncertainSpanPlan {
        Self.plan(
            words: words,
            deletionGaps: deletionGaps,
            catastrophicEvidence: catastrophicEvidence,
            sessionDurationSeconds: sessionDurationSeconds,
            sentenceRegion: sentenceRegion,
            vadRegions: vadRegions,
            configuration: configuration
        )
    }

    public func plan(
        words: [RecognizedWord],
        wordErrorProbabilities: [StableWordID: Double],
        deletionGaps: [DeletionGapEvidence] = [],
        catastrophicEvidence: CatastrophicEvidence = .none,
        sessionDurationSeconds: Double,
        sentenceRegion: ClosedRange<Double>? = nil,
        vadRegions: [UncertainSpanVADRegion] = []
    ) -> UncertainSpanPlan {
        Self.plan(
            words: words,
            wordErrorProbabilities: wordErrorProbabilities,
            deletionGaps: deletionGaps,
            catastrophicEvidence: catastrophicEvidence,
            sessionDurationSeconds: sessionDurationSeconds,
            sentenceRegion: sentenceRegion,
            vadRegions: vadRegions,
            configuration: configuration
        )
    }

    private struct RiskEvent: Sendable {
        var start: Double
        var end: Double
        let risk: Double
        let trigger: UncertainSpanTrigger
        let wordIndices: [Int]
        let wordIDs: Set<StableWordID>
        let ordinal: Int
    }

    private struct MergedRisk: Sendable {
        var start: Double
        var end: Double
        var risk: Double
        var trigger: UncertainSpanTrigger
        var wordIndices: Set<Int>
        var wordIDs: Set<StableWordID>
        var events: [RiskEvent]
        var ordinal: Int
    }

    private struct Candidate: Sendable {
        let start: Double
        let end: Double
        let riskScore: Double
        let expectedRepairValue: Double
        let trigger: UncertainSpanTrigger
        let wordIndices: Set<Int>
        let wordIDs: Set<StableWordID>
        let contextText: String
        let contextWasCapped: Bool
        let wordCountWasCapped: Bool
        let ordinal: Int
    }

    private struct ValidatedInput {
        let probabilities: [Double?]
        let gaps: [DeletionGapEvidence]
        let vad: [UncertainSpanVADRegion]
    }

    private struct RankedGap {
        let gap: DeletionGapEvidence
        let sourceIndex: Int
    }

    /// Plans from probabilities already attached to `RecognizedWord` values.
    public static func plan(
        words: [RecognizedWord],
        deletionGaps: [DeletionGapEvidence] = [],
        catastrophicEvidence: CatastrophicEvidence = .none,
        sessionDurationSeconds: Double,
        sentenceRegion: ClosedRange<Double>? = nil,
        vadRegions: [UncertainSpanVADRegion] = [],
        configuration: UncertainSpanPlannerConfiguration =
            .uncalibratedExperimentDefaults
    ) -> UncertainSpanPlan {
        planInternal(
            words: words,
            probabilities: words.map(\.calibratedErrorProbability),
            deletionGaps: deletionGaps,
            catastrophicEvidence: catastrophicEvidence,
            sessionDurationSeconds: sessionDurationSeconds,
            sentenceRegion: sentenceRegion,
            vadRegions: vadRegions,
            configuration: configuration
        )
    }

    /// Plans from a stable-ID keyed probability map.  Missing IDs remain
    /// unknown; they do not become synthetic zero-error values.
    public static func plan(
        words: [RecognizedWord],
        wordErrorProbabilities: [StableWordID: Double],
        deletionGaps: [DeletionGapEvidence] = [],
        catastrophicEvidence: CatastrophicEvidence = .none,
        sessionDurationSeconds: Double,
        sentenceRegion: ClosedRange<Double>? = nil,
        vadRegions: [UncertainSpanVADRegion] = [],
        configuration: UncertainSpanPlannerConfiguration =
            .uncalibratedExperimentDefaults
    ) -> UncertainSpanPlan {
        planInternal(
            words: words,
            probabilities: words.map { wordErrorProbabilities[$0.id] },
            deletionGaps: deletionGaps,
            catastrophicEvidence: catastrophicEvidence,
            sessionDurationSeconds: sessionDurationSeconds,
            sentenceRegion: sentenceRegion,
            vadRegions: vadRegions,
            configuration: configuration
        )
    }

    /// Plans from an ordered probability array.  A count mismatch fails
    /// closed instead of silently shifting risks to the wrong word IDs.
    public static func plan(
        words: [RecognizedWord],
        calibratedErrorProbabilities: [Double],
        deletionGaps: [DeletionGapEvidence] = [],
        catastrophicEvidence: CatastrophicEvidence = .none,
        sessionDurationSeconds: Double,
        sentenceRegion: ClosedRange<Double>? = nil,
        vadRegions: [UncertainSpanVADRegion] = [],
        configuration: UncertainSpanPlannerConfiguration =
            .uncalibratedExperimentDefaults
    ) -> UncertainSpanPlan {
        guard calibratedErrorProbabilities.count == words.count else {
            return failedPlan(
                failure: .invalidWordProbability,
                sessionDurationSeconds: sessionDurationSeconds
            )
        }
        return planInternal(
            words: words,
            probabilities: calibratedErrorProbabilities.map(Optional.some),
            deletionGaps: deletionGaps,
            catastrophicEvidence: catastrophicEvidence,
            sessionDurationSeconds: sessionDurationSeconds,
            sentenceRegion: sentenceRegion,
            vadRegions: vadRegions,
            configuration: configuration
        )
    }

    /// Uses W05's typed estimates while retaining only numeric risk in the
    /// planner.  A missing estimate remains unknown and is never imputed.
    public static func plan(
        words: [RecognizedWord],
        estimates: [ConfidenceEstimate],
        deletionGaps: [DeletionGapEvidence] = [],
        catastrophicEvidence: CatastrophicEvidence = .none,
        sessionDurationSeconds: Double,
        sentenceRegion: ClosedRange<Double>? = nil,
        vadRegions: [UncertainSpanVADRegion] = [],
        configuration: UncertainSpanPlannerConfiguration =
            .uncalibratedExperimentDefaults
    ) -> UncertainSpanPlan {
        guard estimates.count == words.count else {
            return failedPlan(
                failure: .invalidWordProbability,
                sessionDurationSeconds: sessionDurationSeconds
            )
        }
        let probabilities = estimates.map(\.errorProbability)
        return planInternal(
            words: words,
            probabilities: probabilities,
            deletionGaps: deletionGaps,
            catastrophicEvidence: catastrophicEvidence,
            sessionDurationSeconds: sessionDurationSeconds,
            sentenceRegion: sentenceRegion,
            vadRegions: vadRegions,
            configuration: configuration
        )
    }

    /// Alias for call sites that name the operation rather than the result.
    public static func planSpans(
        words: [RecognizedWord],
        wordErrorProbabilities: [StableWordID: Double] = [:],
        deletionGaps: [DeletionGapEvidence] = [],
        catastrophicEvidence: CatastrophicEvidence = .none,
        sessionDurationSeconds: Double,
        sentenceRegion: ClosedRange<Double>? = nil,
        vadRegions: [UncertainSpanVADRegion] = [],
        configuration: UncertainSpanPlannerConfiguration =
            .uncalibratedExperimentDefaults
    ) -> UncertainSpanPlan {
        if wordErrorProbabilities.isEmpty {
            return plan(
                words: words,
                deletionGaps: deletionGaps,
                catastrophicEvidence: catastrophicEvidence,
                sessionDurationSeconds: sessionDurationSeconds,
                sentenceRegion: sentenceRegion,
                vadRegions: vadRegions,
                configuration: configuration
            )
        }
        return plan(
            words: words,
            wordErrorProbabilities: wordErrorProbabilities,
            deletionGaps: deletionGaps,
            catastrophicEvidence: catastrophicEvidence,
            sessionDurationSeconds: sessionDurationSeconds,
            sentenceRegion: sentenceRegion,
            vadRegions: vadRegions,
            configuration: configuration
        )
    }

    /// Throwing adapter for coordinators that prefer an explicit error path.
    /// The primary planner remains non-throwing and fail-closed.
    public static func planOrThrow(
        words: [RecognizedWord],
        wordErrorProbabilities: [StableWordID: Double] = [:],
        deletionGaps: [DeletionGapEvidence] = [],
        catastrophicEvidence: CatastrophicEvidence = .none,
        sessionDurationSeconds: Double,
        sentenceRegion: ClosedRange<Double>? = nil,
        vadRegions: [UncertainSpanVADRegion] = [],
        configuration: UncertainSpanPlannerConfiguration =
            .uncalibratedExperimentDefaults
    ) throws -> UncertainSpanPlan {
        let result = planSpans(
            words: words,
            wordErrorProbabilities: wordErrorProbabilities,
            deletionGaps: deletionGaps,
            catastrophicEvidence: catastrophicEvidence,
            sessionDurationSeconds: sessionDurationSeconds,
            sentenceRegion: sentenceRegion,
            vadRegions: vadRegions,
            configuration: configuration
        )
        if let failure = result.failure { throw failure }
        return result
    }

    private static func planInternal(
        words: [RecognizedWord],
        probabilities: [Double?],
        deletionGaps: [DeletionGapEvidence],
        catastrophicEvidence: CatastrophicEvidence,
        sessionDurationSeconds: Double,
        sentenceRegion: ClosedRange<Double>?,
        vadRegions: [UncertainSpanVADRegion],
        configuration: UncertainSpanPlannerConfiguration
    ) -> UncertainSpanPlan {
        guard sessionDurationSeconds.isFinite, sessionDurationSeconds > 0 else {
            return failedPlan(
                failure: .invalidSessionDuration,
                sessionDurationSeconds: sessionDurationSeconds
            )
        }
        guard configurationIsValid(configuration) else {
            return failedPlan(
                failure: .invalidConfiguration,
                sessionDurationSeconds: sessionDurationSeconds
            )
        }
        let validation = validate(
            words: words,
            probabilities: probabilities,
            deletionGaps: deletionGaps,
            vadRegions: vadRegions,
            sessionDurationSeconds: sessionDurationSeconds,
            sampleRate: configuration.sampleRate
        )
        guard let validated = validation.value else {
            return failedPlan(
                failure: validation.failure ?? .invalidConfiguration,
                sessionDurationSeconds: sessionDurationSeconds
            )
        }

        let effectiveSentenceRegion = sentenceRegion
            ?? catastrophicEvidence.sentenceRegion
        if catastrophicEvidence.requiresSentenceFallback {
            return catastrophicPlan(
                words: words,
                probabilities: validated.probabilities,
                evidence: catastrophicEvidence,
                requestedRegion: effectiveSentenceRegion,
                sessionDurationSeconds: sessionDurationSeconds,
                configuration: configuration
            )
        }

        var issues: [UncertainSpanPlanningIssue] = []
        var events: [RiskEvent] = []
        var wordRisks: [UncertainWordRiskMetadata] = []
        wordRisks.reserveCapacity(words.count)

        for index in words.indices {
            guard let probability = validated.probabilities[index] else {
                continue
            }
            guard probability >= configuration.errorProbabilityThreshold else {
                continue
            }
            let word = words[index]
            guard let start = word.startSeconds, let end = word.endSeconds else {
                continue
            }
            let event = RiskEvent(
                start: start,
                end: end,
                risk: probability,
                trigger: .uncertainWord,
                wordIndices: [index],
                wordIDs: [word.id],
                ordinal: index
            )
            events.append(event)
            wordRisks.append(
                UncertainWordRiskMetadata(
                    wordID: word.id,
                    wordIndex: index,
                    errorProbability: probability,
                    selected: false
                )
            )
        }

        let eligibleGaps = validated.gaps.enumerated().filter {
            $0.element.explicitlyFlagged
                || $0.element.errorProbability >= configuration.errorProbabilityThreshold
        }
        let rankedGapEntries = rankedGaps(
            eligibleGaps,
            maximumCount: configuration.maximumGapEvidenceCount
        )
        let selectedGaps = rankedGapEntries.map(\.gap)
        let selectedGapIndices = Set(rankedGapEntries.map(\.sourceIndex))
        let droppedGaps = eligibleGaps.filter {
            !selectedGapIndices.contains($0.offset)
        }
        let droppedGapRisks = droppedGaps.map { item in
            return UnselectedSpanRiskMetadata(
                startSeconds: item.element.startSeconds,
                endSeconds: item.element.endSeconds,
                riskScore: item.element.errorProbability,
                expectedRepairValue: item.element.errorProbability,
                trigger: .deletionGap,
                authorizedWordIDs: [],
                reason: .wordBudget
            )
        }
        if validated.gaps.count > selectedGaps.count {
            issues.append(.gapEvidenceBudgetExceeded)
        }
        for (gapOrdinal, gap) in selectedGaps.enumerated() {
            guard gap.explicitlyFlagged
                || gap.errorProbability >= configuration.errorProbabilityThreshold
            else { continue }
            let neighboring = neighboringWordIndices(
                for: gap,
                words: words
            )
            events.append(
                RiskEvent(
                    start: gap.startSeconds,
                    end: gap.endSeconds,
                    risk: max(0, gap.errorProbability),
                    trigger: .deletionGap,
                    wordIndices: neighboring,
                    // A gap has no primary word to unlock.  Its bounded time
                    // range authorizes an insertion while neighboring words
                    // remain anchors for substitution/deletion guards.
                    wordIDs: [],
                    ordinal: words.count + gapOrdinal
                )
            )
        }

        guard !events.isEmpty else {
            return UncertainSpanPlan(
                status: .noRepair,
                spans: [],
                unselectedSpanRisks: droppedGapRisks,
                wordRisks: wordRisks,
                issues: issues,
                sessionDurationSeconds: sessionDurationSeconds,
                totalVerifierDurationSeconds: 0
            )
        }

        let merged = merge(events: events, maximumGap: configuration.maximumMergedGapSeconds)
        var candidates: [Candidate] = []
        candidates.reserveCapacity(merged.count)
        for mergedRisk in merged {
            let split = split(
                mergedRisk,
                maximumDuration: configuration.maximumRepairSpanDurationSeconds,
                configuration: configuration
            )
            if split.wasCapped { issues.append(.perSpanDurationCapped) }
            for piece in split.parts {
                let range = expandedRange(
                    for: piece,
                    words: words,
                    vadRegions: validated.vad,
                    sessionDurationSeconds: sessionDurationSeconds,
                    configuration: configuration
                )
                let bounded = boundedRange(
                    range,
                    center: (piece.start + piece.end) / 2,
                    minimumDuration: configuration.minimumRepairSpanDurationSeconds,
                    maximumDuration: configuration.maximumRepairSpanDurationSeconds,
                    sessionDurationSeconds: sessionDurationSeconds
                )
                if bounded.wasCapped { issues.append(.perSpanDurationCapped) }
                let boundedIDs = boundedAuthorizedIDs(
                    for: piece,
                    words: words,
                    maximumCount: configuration.maximumWordsPerSpan
                )
                var contextWasCapped = false
                let context = contextText(
                    for: bounded.start...bounded.end,
                    words: words,
                    contextWordRadius: configuration.contextWordRadius,
                    maximumCharacters: configuration.maximumContextCharacters,
                    wasCapped: &contextWasCapped
                )
                let expected = expectedRepairValue(
                    risk: piece.risk,
                    duration: bounded.end - bounded.start,
                    wordIndices: piece.wordIndices,
                    words: words,
                    configuration: configuration
                )
                candidates.append(
                    Candidate(
                        start: bounded.start,
                        end: bounded.end,
                        riskScore: piece.risk,
                        expectedRepairValue: expected,
                        trigger: piece.trigger,
                        wordIndices: piece.wordIndices,
                        wordIDs: boundedIDs.ids,
                        contextText: context,
                        contextWasCapped: contextWasCapped,
                        wordCountWasCapped: boundedIDs.wasCapped,
                        ordinal: piece.ordinal
                    )
                )
            }
        }

        let coalesced = coalesceCandidates(
            candidates,
            maximumDuration: configuration.maximumRepairSpanDurationSeconds,
            sessionDurationSeconds: sessionDurationSeconds,
            configuration: configuration
        )
        if coalesced.didCap { issues.append(.perSpanDurationCapped) }
        candidates = coalesced.candidates
        let ranked = candidates.sorted(by: candidatePrecedes)
        let budget = sessionDurationSeconds * configuration.maximumVerifierAudioRatio
        var selected: [Candidate] = []
        var selectedDuration = 0.0
        var unselected: [UnselectedSpanRiskMetadata] = droppedGapRisks
        var selectedIDs = Set<StableWordID>()
        for candidate in ranked {
            let duration = candidate.end - candidate.start
            let countReached = selected.count >= configuration.maximumSpanCount
            let audioReached = selectedDuration + duration > budget + 1e-9
            if !countReached && !audioReached {
                selected.append(candidate)
                selectedDuration += duration
                selectedIDs.formUnion(candidate.wordIDs)
                continue
            }
            let reason: UnselectedSpanReason = countReached
                ? .spanBudget
                : .verifierAudioBudget
            if reason == .spanBudget {
                issues.append(.spanBudgetExceeded)
            } else {
                issues.append(.verifierAudioBudgetExceeded)
            }
            unselected.append(
                UnselectedSpanRiskMetadata(
                    startSeconds: candidate.start,
                    endSeconds: candidate.end,
                    riskScore: candidate.riskScore,
                    expectedRepairValue: candidate.expectedRepairValue,
                    trigger: candidate.trigger,
                    authorizedWordIDs: candidate.wordIDs,
                    reason: reason
                )
            )
        }

        let cappedContext = selected.contains { $0.contextWasCapped }
        if cappedContext { issues.append(.contextTextCapped) }
        if selected.contains(where: { $0.wordCountWasCapped }) {
            issues.append(.wordBudgetExceeded)
        }

        for index in wordRisks.indices {
            let risk = wordRisks[index]
            if selectedIDs.contains(risk.wordID) {
                wordRisks[index] = UncertainWordRiskMetadata(
                    wordID: risk.wordID,
                    wordIndex: risk.wordIndex,
                    errorProbability: risk.errorProbability,
                    selected: true
                )
            } else {
                let reason: UnselectedSpanReason = unselected.isEmpty
                    ? .lowerExpectedRepairValue
                    : .verifierAudioBudget
                wordRisks[index] = UncertainWordRiskMetadata(
                    wordID: risk.wordID,
                    wordIndex: risk.wordIndex,
                    errorProbability: risk.errorProbability,
                    selected: false,
                    reason: reason
                )
            }
        }

        let output = selected
            .sorted { left, right in
                if left.start != right.start { return left.start < right.start }
                if left.end != right.end { return left.end < right.end }
                return left.ordinal < right.ordinal
            }
            .enumerated()
            .compactMap { index, candidate in
                makeSpan(
                    id: index,
                    candidate: candidate,
                    sessionDurationSeconds: sessionDurationSeconds,
                    sampleRate: configuration.sampleRate,
                    words: words,
                    configuration: configuration
                )
            }

        let status: UncertainSpanPlanStatus = output.isEmpty
            ? .noRepair
            : (issues.isEmpty ? .planned : .degraded)
        return UncertainSpanPlan(
            status: status,
            spans: output,
            unselectedSpanRisks: unselected,
            wordRisks: wordRisks,
            issues: stableIssues(issues),
            sessionDurationSeconds: sessionDurationSeconds,
            totalVerifierDurationSeconds: output.reduce(0) {
                $0 + $1.durationSeconds
            }
        )
    }

    private static func catastrophicPlan(
        words: [RecognizedWord],
        probabilities: [Double?],
        evidence: CatastrophicEvidence,
        requestedRegion: ClosedRange<Double>?,
        sessionDurationSeconds: Double,
        configuration: UncertainSpanPlannerConfiguration
    ) -> UncertainSpanPlan {
        var issues: [UncertainSpanPlanningIssue] = []
        let region: ClosedRange<Double>
        if let requestedRegion,
           requestedRegion.lowerBound.isFinite,
           requestedRegion.upperBound.isFinite,
           requestedRegion.lowerBound >= 0,
           requestedRegion.upperBound >= requestedRegion.lowerBound,
           requestedRegion.upperBound <= sessionDurationSeconds
        {
            region = requestedRegion
        } else if let first = words.first?.startSeconds,
                  let last = words.last?.endSeconds,
                  first.isFinite,
                  last.isFinite,
                  first >= 0,
                  last >= first,
                  last <= sessionDurationSeconds
        {
            region = first...last
        } else {
            return failedPlan(
                failure: requestedRegion == nil
                    ? .missingBoundedSentenceRegion
                    : .invalidSentenceRegion,
                sessionDurationSeconds: sessionDurationSeconds
            )
        }

        var start = max(0, region.lowerBound - configuration.leftPaddingSeconds)
        var end = min(
            sessionDurationSeconds,
            region.upperBound + configuration.rightPaddingSeconds
        )
        var maxDuration = min(
            sessionDurationSeconds,
            configuration.maximumCatastrophicSpanDurationSeconds,
            sessionDurationSeconds * configuration.maximumVerifierAudioRatio
        )
        if !configuration.allowWholeSessionFallback,
           region.lowerBound <= 0,
           region.upperBound >= sessionDurationSeconds
        {
            // A full-session region is not an implicit catastrophic policy.
            // Leave one sample outside it by default, even for a short
            // dictation; an explicit opt-in is required to use the whole
            // session as a fallback.
            maxDuration = min(
                maxDuration,
                max(0, sessionDurationSeconds - 1 / Double(configuration.sampleRate))
            )
            issues.append(.catastrophicRegionCapped)
        }
        if region.upperBound - region.lowerBound
            + configuration.leftPaddingSeconds
            + configuration.rightPaddingSeconds
            > sessionDurationSeconds * configuration.maximumVerifierAudioRatio
        {
            issues.append(.verifierAudioBudgetExceeded)
        }
        guard maxDuration > 0 else {
            return failedPlan(
                failure: .invalidConfiguration,
                sessionDurationSeconds: sessionDurationSeconds
            )
        }
        if end - start > maxDuration {
            let center = (start + end) / 2
            let half = maxDuration / 2
            start = max(0, center - half)
            end = min(sessionDurationSeconds, start + maxDuration)
            start = max(0, end - maxDuration)
            issues.append(.catastrophicRegionCapped)
        }
        let bounded = boundedRange(
            (start: start, end: end),
            center: (start + end) / 2,
            minimumDuration: min(
                configuration.minimumRepairSpanDurationSeconds,
                maxDuration
            ),
            maximumDuration: maxDuration,
            sessionDurationSeconds: sessionDurationSeconds
        )
        start = bounded.start
        end = bounded.end

        let overlapping = words.indices.filter { index in
            guard let wordStart = words[index].startSeconds,
                  let wordEnd = words[index].endSeconds
            else { return false }
            return wordEnd >= start && wordStart <= end
        }
        var authorized = Set(overlapping.prefix(configuration.maximumWordsPerSpan).map {
            words[$0].id
        })
        if overlapping.count > authorized.count {
            issues.append(.catastrophicWordBudgetExceeded)
        }
        // A catastrophic request may be generated from invalid confidence
        // values, but never from invalid timing: `validate` ran first.
        if authorized.isEmpty {
            authorized = Set(words.prefix(configuration.maximumWordsPerSpan).map(\.id))
        }
        var contextWasCapped = false
        let context = contextText(
            for: start...end,
            words: words,
            contextWordRadius: configuration.contextWordRadius,
            maximumCharacters: configuration.maximumContextCharacters,
            wasCapped: &contextWasCapped
        )
        if contextWasCapped { issues.append(.contextTextCapped) }
        guard let samples = sampleBounds(
            start: start,
            end: end,
            sessionDurationSeconds: sessionDurationSeconds,
            sampleRate: configuration.sampleRate
        ) else {
            return failedPlan(
                failure: .integerSampleOverflow,
                sessionDurationSeconds: sessionDurationSeconds
            )
        }
        let span = UncertainAudioSpan(
            id: 0,
            startSeconds: start,
            endSeconds: end,
            startSample: samples.start,
            endSample: samples.end,
            sampleRate: configuration.sampleRate,
            authorizedWordIDs: authorized,
            authorizedTimeRange: start...end,
            trigger: .catastrophicFallback,
            riskScore: 1,
            expectedRepairValue: 1,
            contextText: context
        )
        let fallback = BoundedSentenceFallbackRequest(
            startSeconds: start,
            endSeconds: end,
            startSample: samples.start,
            endSample: samples.end,
            sampleRate: configuration.sampleRate,
            authorizedWordIDs: authorized,
            authorizedTimeRange: start...end,
            contextText: context
        )
        let wordRisks = words.indices.compactMap { index -> UncertainWordRiskMetadata? in
            guard let probability = probabilities[index] else { return nil }
            return UncertainWordRiskMetadata(
                wordID: words[index].id,
                wordIndex: index,
                errorProbability: probability,
                selected: authorized.contains(words[index].id),
                reason: authorized.contains(words[index].id) ? nil : .wordBudget
            )
        }
        _ = evidence
        return UncertainSpanPlan(
            status: .catastrophicFallback,
            spans: [span],
            wordRisks: wordRisks,
            issues: stableIssues(issues),
            fallbackRequest: fallback,
            sessionDurationSeconds: sessionDurationSeconds,
            totalVerifierDurationSeconds: span.durationSeconds
        )
    }

    private static func validate(
        words: [RecognizedWord],
        probabilities: [Double?],
        deletionGaps: [DeletionGapEvidence],
        vadRegions: [UncertainSpanVADRegion],
        sessionDurationSeconds: Double,
        sampleRate: Int
    ) -> (value: ValidatedInput?, failure: UncertainSpanPlanningFailure?) {
        guard sampleRate > 0 else {
            return (nil, .invalidSampleRate)
        }
        guard probabilities.count == words.count else {
            return (nil, .invalidWordProbability)
        }
        var previousEnd = 0.0
        var IDs = Set<StableWordID>()
        for (index, word) in words.enumerated() {
            guard IDs.insert(word.id).inserted else {
                return (nil, .duplicateWordID)
            }
            guard let start = word.startSeconds, let end = word.endSeconds else {
                return (nil, .missingWordTiming)
            }
            guard start.isFinite, end.isFinite, start >= 0, end >= start,
                  end <= sessionDurationSeconds
            else {
                return (nil, .invalidWordTiming)
            }
            if index > 0, start < previousEnd {
                return (nil, .nonMonotonicWordTiming)
            }
            previousEnd = end
            if let probability = probabilities[index],
               (!probability.isFinite || !(0...1).contains(probability))
            {
                return (nil, .invalidWordProbability)
            }
        }
        var previousGapEnd = 0.0
        var checkedGaps: [DeletionGapEvidence] = []
        checkedGaps.reserveCapacity(deletionGaps.count)
        for (index, gap) in deletionGaps.enumerated() {
            guard gap.startSeconds.isFinite, gap.endSeconds.isFinite,
                  gap.startSeconds >= 0,
                  gap.endSeconds >= gap.startSeconds,
                  gap.endSeconds <= sessionDurationSeconds
            else {
                return (nil, .invalidGapTiming)
            }
            if index > 0, gap.startSeconds < previousGapEnd {
                return (nil, .nonMonotonicGapTiming)
            }
            previousGapEnd = gap.endSeconds
            guard gap.errorProbability.isFinite,
                  (0...1).contains(gap.errorProbability)
            else {
                return (nil, .invalidGapProbability)
            }
            checkedGaps.append(gap)
        }
        var previousVADEnd = 0.0
        var checkedVAD: [UncertainSpanVADRegion] = []
        checkedVAD.reserveCapacity(vadRegions.count)
        for (index, region) in vadRegions.enumerated() {
            guard region.startSeconds.isFinite,
                  region.endSeconds.isFinite,
                  region.startSeconds >= 0,
                  region.endSeconds >= region.startSeconds,
                  region.endSeconds <= sessionDurationSeconds
            else {
                return (nil, .invalidVADTiming)
            }
            if index > 0, region.startSeconds < previousVADEnd {
                return (nil, .nonMonotonicVADTiming)
            }
            previousVADEnd = region.endSeconds
            checkedVAD.append(region)
        }
        return (
            ValidatedInput(
                probabilities: probabilities,
                gaps: checkedGaps,
                vad: checkedVAD
            ),
            nil
        )
    }

    private static func configurationIsValid(
        _ configuration: UncertainSpanPlannerConfiguration
    ) -> Bool {
        let finiteNonnegative = [
            configuration.minimumRepairSpanDurationSeconds,
            configuration.maximumRepairSpanDurationSeconds,
            configuration.maximumMergedGapSeconds,
            configuration.leftPaddingSeconds,
            configuration.rightPaddingSeconds,
            configuration.maximumCatastrophicSpanDurationSeconds,
            configuration.verifierCostPerSecond,
            configuration.anchorRiskWeight,
        ].allSatisfy { $0.isFinite && $0 >= 0 }
        guard finiteNonnegative,
              configuration.maximumRepairSpanDurationSeconds > 0,
              configuration.maximumRepairSpanDurationSeconds
                  <= UncertainSpanPlannerConfiguration.hardMaximumSpanDurationSeconds,
              configuration.minimumRepairSpanDurationSeconds
                  <= configuration.maximumRepairSpanDurationSeconds,
              configuration.maximumCatastrophicSpanDurationSeconds > 0,
              configuration.maximumCatastrophicSpanDurationSeconds
                  <= UncertainSpanPlannerConfiguration.hardMaximumSpanDurationSeconds,
              configuration.maximumVerifierAudioRatio.isFinite,
              (0...1).contains(configuration.maximumVerifierAudioRatio),
              configuration.maximumSpanCount > 0,
              configuration.maximumSpanCount <= UncertainSpanPlannerConfiguration.hardMaximumSpanCount,
              configuration.maximumWordsPerSpan > 0,
              configuration.maximumWordsPerSpan <= UncertainSpanPlannerConfiguration.hardMaximumWordsPerSpan,
              configuration.maximumGapEvidenceCount >= 0,
              configuration.maximumGapEvidenceCount <= UncertainSpanPlannerConfiguration.hardMaximumGapEvidence,
              configuration.maximumContextCharacters >= 0,
              configuration.maximumContextCharacters <= UncertainSpanPlannerConfiguration.hardMaximumContextCharacters,
              configuration.contextWordRadius >= 0,
              configuration.sampleRate > 0,
              configuration.threshold.errorProbability.isFinite,
              (0...1).contains(configuration.threshold.errorProbability)
        else { return false }
        return true
    }

    private static func rankedGaps(
        _ gaps: [(offset: Int, element: DeletionGapEvidence)],
        maximumCount: Int
    ) -> [RankedGap] {
        gaps
            .sorted { left, right in
                if left.element.errorProbability != right.element.errorProbability {
                    return left.element.errorProbability > right.element.errorProbability
                }
                if left.element.startSeconds != right.element.startSeconds {
                    return left.element.startSeconds < right.element.startSeconds
                }
                if left.element.endSeconds != right.element.endSeconds {
                    return left.element.endSeconds < right.element.endSeconds
                }
                return left.offset < right.offset
            }
            .prefix(maximumCount)
            .map { RankedGap(gap: $0.element, sourceIndex: $0.offset) }
    }

    private static func neighboringWordIndices(
        for gap: DeletionGapEvidence,
        words: [RecognizedWord]
    ) -> [Int] {
        // Word timing was validated and is monotonic, so each neighboring
        // lookup is binary-searchable rather than a scan per gap.
        var low = 0
        var high = words.count
        while low < high {
            let middle = low + (high - low) / 2
            if let end = words[middle].endSeconds,
               end <= gap.startSeconds
            {
                low = middle + 1
            } else {
                high = middle
            }
        }
        let left: Int? = low > 0 ? low - 1 : nil

        low = 0
        high = words.count
        while low < high {
            let middle = low + (high - low) / 2
            if let start = words[middle].startSeconds,
               start < gap.endSeconds
            {
                low = middle + 1
            } else {
                high = middle
            }
        }
        let right: Int? = low < words.count ? low : nil
        return [left, right].compactMap { $0 }
    }

    private static func merge(
        events: [RiskEvent],
        maximumGap: Double
    ) -> [MergedRisk] {
        let sorted = events.sorted { left, right in
            if left.start != right.start { return left.start < right.start }
            if left.end != right.end { return left.end < right.end }
            if left.trigger != right.trigger {
                return triggerRank(left.trigger) < triggerRank(right.trigger)
            }
            return left.ordinal < right.ordinal
        }
        var output: [MergedRisk] = []
        for event in sorted {
            guard var last = output.popLast() else {
                output.append(
                    MergedRisk(
                        start: event.start,
                        end: event.end,
                        risk: event.risk,
                        trigger: event.trigger,
                        wordIndices: Set(event.wordIndices),
                        wordIDs: event.wordIDs,
                        events: [event],
                        ordinal: event.ordinal
                    )
                )
                continue
            }
            if event.start - last.end <= maximumGap {
                last.end = max(last.end, event.end)
                last.risk += event.risk
                last.wordIndices.formUnion(event.wordIndices)
                last.wordIDs.formUnion(event.wordIDs)
                last.events.append(event)
                if triggerRank(event.trigger) < triggerRank(last.trigger) {
                    last.trigger = event.trigger
                }
                output.append(last)
            } else {
                output.append(last)
                output.append(
                    MergedRisk(
                        start: event.start,
                        end: event.end,
                        risk: event.risk,
                        trigger: event.trigger,
                        wordIndices: Set(event.wordIndices),
                        wordIDs: event.wordIDs,
                        events: [event],
                        ordinal: event.ordinal
                    )
                )
            }
        }
        return output
    }

    private static func split(
        _ merged: MergedRisk,
        maximumDuration: Double,
        configuration: UncertainSpanPlannerConfiguration
    ) -> (parts: [MergedRisk], wasCapped: Bool) {
        guard merged.end - merged.start > maximumDuration else {
            return ([merged], false)
        }
        let sortedEvents = merged.events.sorted { left, right in
            if left.start != right.start { return left.start < right.start }
            return left.ordinal < right.ordinal
        }
        var parts: [MergedRisk] = []
        var current: MergedRisk?
        var capped = false
        for event in sortedEvents {
            var eventValue = event
            if eventValue.end - eventValue.start > maximumDuration {
                let center = (eventValue.start + eventValue.end) / 2
                eventValue.start = max(0, center - maximumDuration / 2)
                eventValue.end = eventValue.start + maximumDuration
                capped = true
            }
            guard var value = current else {
                current = MergedRisk(
                    start: eventValue.start,
                    end: eventValue.end,
                    risk: eventValue.risk,
                    trigger: eventValue.trigger,
                    wordIndices: Set(eventValue.wordIndices),
                    wordIDs: eventValue.wordIDs,
                    events: [eventValue],
                    ordinal: eventValue.ordinal
                )
                continue
            }
            let candidateEnd = max(value.end, eventValue.end)
            if candidateEnd - value.start <= maximumDuration {
                value.end = candidateEnd
                value.risk += eventValue.risk
                value.wordIndices.formUnion(eventValue.wordIndices)
                value.wordIDs.formUnion(eventValue.wordIDs)
                value.events.append(eventValue)
                if triggerRank(eventValue.trigger) < triggerRank(value.trigger) {
                    value.trigger = eventValue.trigger
                }
                current = value
            } else {
                parts.append(value)
                current = MergedRisk(
                    start: eventValue.start,
                    end: eventValue.end,
                    risk: eventValue.risk,
                    trigger: eventValue.trigger,
                    wordIndices: Set(eventValue.wordIndices),
                    wordIDs: eventValue.wordIDs,
                    events: [eventValue],
                    ordinal: eventValue.ordinal
                )
                capped = true
            }
        }
        if let current { parts.append(current) }
        if parts.isEmpty {
            parts = [merged]
            capped = true
        }
        // A maliciously large event list cannot create an unbounded number of
        // verifier requests.  The caller's span budget will reduce further.
        if parts.count > configuration.maximumSpanCount * 4 {
            parts = Array(parts.prefix(configuration.maximumSpanCount * 4))
            capped = true
        }
        return (parts, capped)
    }

    private static func expandedRange(
        for risk: MergedRisk,
        words: [RecognizedWord],
        vadRegions: [UncertainSpanVADRegion],
        sessionDurationSeconds: Double,
        configuration: UncertainSpanPlannerConfiguration
    ) -> (start: Double, end: Double) {
        var start = max(0, risk.start - configuration.leftPaddingSeconds)
        var end = min(sessionDurationSeconds, risk.end + configuration.rightPaddingSeconds)
        if configuration.adjustToWordBoundaries {
            if let prior = words.last(where: {
                guard let wordStart = $0.startSeconds else { return false }
                return wordStart <= start
            }), let wordStart = prior.startSeconds {
                start = min(start, wordStart)
            }
            if let following = words.first(where: {
                guard let wordEnd = $0.endSeconds else { return false }
                return wordEnd >= end
            }), let wordEnd = following.endSeconds {
                end = max(end, wordEnd)
            }
        }
        if configuration.adjustToVADBoundaries {
            let intersecting = vadRegions.filter {
                $0.endSeconds >= risk.start && $0.startSeconds <= risk.end
            }
            if let first = intersecting.first {
                start = min(start, first.startSeconds)
            }
            if let last = intersecting.last {
                end = max(end, last.endSeconds)
            }
        }
        return (
            max(0, min(start, sessionDurationSeconds)),
            max(0, min(end, sessionDurationSeconds))
        )
    }

    private static func boundedRange(
        _ input: (start: Double, end: Double),
        center: Double,
        minimumDuration: Double,
        maximumDuration: Double,
        sessionDurationSeconds: Double
    ) -> (start: Double, end: Double, wasCapped: Bool) {
        var start = max(0, min(input.start, sessionDurationSeconds))
        var end = max(start, min(input.end, sessionDurationSeconds))
        var capped = false
        if end - start < minimumDuration {
            let needed = minimumDuration - (end - start)
            start = max(0, start - needed / 2)
            end = min(sessionDurationSeconds, end + needed / 2)
            if end - start < minimumDuration {
                if start == 0 {
                    end = min(sessionDurationSeconds, minimumDuration)
                } else if end == sessionDurationSeconds {
                    start = max(0, sessionDurationSeconds - minimumDuration)
                }
            }
        }
        if end - start > maximumDuration {
            let safeCenter = max(0, min(center, sessionDurationSeconds))
            let half = maximumDuration / 2
            start = max(0, safeCenter - half)
            end = min(sessionDurationSeconds, start + maximumDuration)
            start = max(0, end - maximumDuration)
            capped = true
        }
        return (start, end, capped)
    }

    private static func boundedAuthorizedIDs(
        for risk: MergedRisk,
        words: [RecognizedWord],
        maximumCount: Int
    ) -> (ids: Set<StableWordID>, wasCapped: Bool) {
        let all = risk.wordIDs
        if all.count <= maximumCount { return (all, false) }
        let ordered = words.enumerated().compactMap { index, word in
            all.contains(word.id) ? (index, word.id) : nil
        }
        return (Set(ordered.prefix(maximumCount).map(\.1)), true)
    }

    private static func expectedRepairValue(
        risk: Double,
        duration: Double,
        wordIndices: Set<Int>,
        words: [RecognizedWord],
        configuration: UncertainSpanPlannerConfiguration
    ) -> Double {
        let anchors = wordIndices.filter { index in
            guard words.indices.contains(index) else { return false }
            return words[index].lockState != .unlocked
        }.count
        return risk
            - duration * configuration.verifierCostPerSecond
            - Double(anchors) * configuration.anchorRiskWeight
    }

    private static func contextText(
        for range: ClosedRange<Double>,
        words: [RecognizedWord],
        contextWordRadius: Int,
        maximumCharacters: Int,
        wasCapped: UnsafeMutablePointer<Bool>? = nil
    ) -> String {
        let overlaps = words.indices.filter { index in
            guard let start = words[index].startSeconds,
                  let end = words[index].endSeconds
            else { return false }
            return end >= range.lowerBound && start <= range.upperBound
        }
        guard !overlaps.isEmpty else { return "" }
        let first = max(0, overlaps.first! - contextWordRadius)
        let last = min(words.count - 1, overlaps.last! + contextWordRadius)
        let text = (first...last).map { words[$0].text }.joined(separator: " ")
        guard maximumCharacters >= 0, text.count > maximumCharacters else {
            return text
        }
        wasCapped?.pointee = true
        return String(text.prefix(maximumCharacters))
    }

    private static func coalesceCandidates(
        _ candidates: [Candidate],
        maximumDuration: Double,
        sessionDurationSeconds: Double,
        configuration: UncertainSpanPlannerConfiguration
    ) -> (candidates: [Candidate], didCap: Bool) {
        let sorted = candidates.sorted { left, right in
            if left.start != right.start { return left.start < right.start }
            return left.ordinal < right.ordinal
        }
        var output: [Candidate] = []
        var capped = false
        for candidate in sorted {
            guard var last = output.popLast() else {
                output.append(candidate)
                continue
            }
            if candidate.start <= last.end {
                let newEnd = max(last.end, candidate.end)
                if newEnd - last.start <= maximumDuration {
                    last = Candidate(
                        start: last.start,
                        end: newEnd,
                        riskScore: last.riskScore + candidate.riskScore,
                        expectedRepairValue: last.expectedRepairValue + candidate.expectedRepairValue,
                        trigger: triggerRank(last.trigger) <= triggerRank(candidate.trigger)
                            ? last.trigger : candidate.trigger,
                        wordIndices: last.wordIndices.union(candidate.wordIndices),
                        wordIDs: last.wordIDs.union(candidate.wordIDs),
                        contextText: last.contextText.isEmpty
                            ? candidate.contextText
                            : last.contextText,
                        contextWasCapped: last.contextWasCapped
                            || candidate.contextWasCapped,
                        wordCountWasCapped: last.wordCountWasCapped
                            || candidate.wordCountWasCapped,
                        ordinal: min(last.ordinal, candidate.ordinal)
                    )
                    output.append(last)
                } else {
                    output.append(last)
                    // Padding around two pieces may overlap even though the
                    // raw risk events were split at a safe boundary.  Trim
                    // only the duplicated padding so selected verifier
                    // regions remain disjoint and the ratio is exact.
                    let trimmedStart = max(candidate.start, last.end)
                    guard candidate.end > trimmedStart else {
                        capped = true
                        continue
                    }
                    output.append(
                        Candidate(
                            start: trimmedStart,
                            end: candidate.end,
                            riskScore: candidate.riskScore,
                            expectedRepairValue: candidate.expectedRepairValue,
                            trigger: candidate.trigger,
                            wordIndices: candidate.wordIndices,
                            wordIDs: candidate.wordIDs,
                            contextText: candidate.contextText,
                            contextWasCapped: candidate.contextWasCapped,
                            wordCountWasCapped: candidate.wordCountWasCapped,
                            ordinal: candidate.ordinal
                        )
                    )
                    capped = true
                }
            } else {
                output.append(last)
                output.append(candidate)
            }
        }
        _ = sessionDurationSeconds
        _ = configuration
        return (output, capped)
    }

    private static func candidatePrecedes(_ left: Candidate, _ right: Candidate) -> Bool {
        if left.expectedRepairValue != right.expectedRepairValue {
            return left.expectedRepairValue > right.expectedRepairValue
        }
        if left.riskScore != right.riskScore {
            return left.riskScore > right.riskScore
        }
        if left.start != right.start { return left.start < right.start }
        if left.end != right.end { return left.end < right.end }
        return left.ordinal < right.ordinal
    }

    private static func makeSpan(
        id: Int,
        candidate: Candidate,
        sessionDurationSeconds: Double,
        sampleRate: Int,
        words: [RecognizedWord],
        configuration: UncertainSpanPlannerConfiguration
    ) -> UncertainAudioSpan? {
        guard let samples = sampleBounds(
            start: candidate.start,
            end: candidate.end,
            sessionDurationSeconds: sessionDurationSeconds,
            sampleRate: sampleRate
        ) else { return nil }
        var contextWasCapped = false
        let context = contextText(
            for: candidate.start...candidate.end,
            words: words,
            contextWordRadius: configuration.contextWordRadius,
            maximumCharacters: configuration.maximumContextCharacters,
            wasCapped: &contextWasCapped
        )
        _ = contextWasCapped
        return UncertainAudioSpan(
            id: id,
            startSeconds: candidate.start,
            endSeconds: candidate.end,
            startSample: samples.start,
            endSample: samples.end,
            sampleRate: sampleRate,
            authorizedWordIDs: candidate.wordIDs,
            authorizedTimeRange: candidate.start...candidate.end,
            trigger: candidate.trigger,
            riskScore: candidate.riskScore,
            expectedRepairValue: candidate.expectedRepairValue,
            contextText: context
        )
    }

    private static func sampleBounds(
        start: Double,
        end: Double,
        sessionDurationSeconds: Double,
        sampleRate: Int
    ) -> (start: Int64, end: Int64)? {
        guard start.isFinite, end.isFinite,
              start >= 0, end > start,
              end <= sessionDurationSeconds,
              sampleRate > 0
        else { return nil }
        let scale = Double(sampleRate)
        let maxSamples = sessionDurationSeconds * scale
        // `Double(Int64.max)` rounds to 2^63.  Require a strict bound before
        // converting so externally supplied extreme durations cannot trap.
        guard maxSamples.isFinite, maxSamples < Double(Int64.max) else {
            return nil
        }
        let startValue = floor(start * scale)
        let endValue = ceil(end * scale)
        guard startValue.isFinite, endValue.isFinite,
              startValue >= 0, endValue < Double(Int64.max),
              let exactStart = Int64(exactly: startValue),
              let exactEnd = Int64(exactly: endValue),
              let exactSession = Int64(exactly: ceil(maxSamples))
        else { return nil }
        var startSample = exactStart
        var endSample = exactEnd
        let sessionSamples = exactSession
        startSample = min(max(0, startSample), sessionSamples)
        endSample = min(max(0, endSample), sessionSamples)
        if endSample <= startSample {
            guard startSample < sessionSamples else { return nil }
            endSample = startSample + 1
        }
        return (startSample, endSample)
    }

    private static func failedPlan(
        failure: UncertainSpanPlanningFailure,
        sessionDurationSeconds: Double
    ) -> UncertainSpanPlan {
        UncertainSpanPlan(
            status: .failed,
            spans: [],
            failure: failure,
            sessionDurationSeconds: sessionDurationSeconds,
            totalVerifierDurationSeconds: 0
        )
    }

    private static func triggerRank(_ trigger: UncertainSpanTrigger) -> Int {
        switch trigger {
        case .catastrophicFallback: return 0
        case .deletionGap: return 1
        case .uncertainWord: return 2
        }
    }

    private static func stableIssues(
        _ issues: [UncertainSpanPlanningIssue]
    ) -> [UncertainSpanPlanningIssue] {
        var seen = Set<UncertainSpanPlanningIssue>()
        return issues.filter { seen.insert($0).inserted }
    }
}

/// Compatibility aliases for coordinator code that uses “repair” language.
public typealias SpanRepairPlan = UncertainSpanPlan
public typealias PlannedRepairSpan = UncertainAudioSpan
public typealias TimestampSampleSpan = UncertainAudioSpan
public typealias UncertainSpanPlanningResult = UncertainSpanPlan
public typealias UncertainSpanGapEvidence = DeletionGapEvidence
