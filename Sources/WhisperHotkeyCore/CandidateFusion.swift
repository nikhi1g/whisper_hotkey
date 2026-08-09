import Foundation

/// Deterministic candidate-selection paths.  All paths operate on bounded
/// word arrays and ultimately pass through the same guarded repair step.
public enum CandidateFusionStrategy: String, Codable, Hashable, Sendable {
    case pairwise
    case weightedROVER
    case mbrMedoid
}

/// Content-free reason codes for a fusion decision.  These are suitable for
/// benchmark metadata; they intentionally contain no transcript text.
public enum CandidateFusionReason: String, Codable, Hashable, Sendable {
    case accepted
    case noChange
    case noCandidates
    case emptyPrimary
    case candidateLimitExceeded
    case wordLimitExceeded
    case alignmentInvalid
    case duplicateWordID
    case outsideAuthorizedSpan
    case insufficientEvidence
    case ambiguousMargin
    case lowTimeOverlap
    case lockedAnchor
    case protectedDictionaryTerm
    case numberChange
    case identifierChange
    case negationChange
    case destructiveCommandChange
    case emptyResult
    case invalidCandidate
}

/// A bounded candidate hypothesis.  `posterior` is accepted only when the
/// caller has a calibrated candidate posterior; a missing value is retained
/// as missing and is never inferred from text or rank.
public struct FusionCandidate: Codable, Hashable, Sendable {
    public let words: [RecognizedWord]
    public let posterior: Double?
    public let sourceAlternativeID: UUID?
    public let provenance: RecognitionProvenance

    public init(
        words: [RecognizedWord],
        posterior: Double? = nil,
        sourceAlternativeID: UUID? = nil,
        provenance: RecognitionProvenance = RecognitionProvenance()
    ) {
        precondition(
            posterior == nil
                || (posterior!.isFinite && (0...1).contains(posterior!))
        )
        self.words = words
        self.posterior = posterior
        self.sourceAlternativeID = sourceAlternativeID
        self.provenance = provenance
    }

    public init(_ result: RecognitionResult, posterior: Double? = nil) {
        self.init(
            words: result.words,
            posterior: posterior,
            provenance: RecognitionProvenance(
                sourceWordIDs: result.words.map(\.id),
                reason: "recognition_result"
            )
        )
    }

    public init(_ alternative: RecognitionAlternative, posterior: Double? = nil) {
        self.init(
            words: alternative.words,
            posterior: posterior,
            sourceAlternativeID: alternative.id,
            provenance: alternative.provenance
        )
    }

    public var text: String {
        words.map(\.text).joined(separator: " ")
    }
}

/// Bounds and safety gates for candidate fusion.
public struct CandidateFusionConfiguration: Codable, Hashable, Sendable {
    public static let hardMaximumCandidates = 8
    public static let hardMaximumWordsPerSpan = WordAlignmentConfiguration.hardMaximumWords

    public let strategy: CandidateFusionStrategy
    public let maximumCandidates: Int
    public let maximumWordsPerSpan: Int
    public let minimumTimeOverlap: Double
    public let minimumEvidenceMargin: Double
    public let minimumInsertionSupport: Double
    public let minimumDeletionErrorProbability: Double
    public let protectedDictionaryTerms: Set<String>
    public let authorizedWordIDs: Set<StableWordID>?
    public let authorizedTimeRange: ClosedRange<Double>?

    public init(
        strategy: CandidateFusionStrategy = .pairwise,
        maximumCandidates: Int = Self.hardMaximumCandidates,
        maximumWordsPerSpan: Int = Self.hardMaximumWordsPerSpan,
        minimumTimeOverlap: Double = 0.35,
        minimumEvidenceMargin: Double = 0.15,
        minimumInsertionSupport: Double = 0.75,
        minimumDeletionErrorProbability: Double = 0.60,
        protectedDictionaryTerms: Set<String> = [],
        authorizedWordIDs: Set<StableWordID>? = nil,
        authorizedTimeRange: ClosedRange<Double>? = nil
    ) {
        precondition(maximumCandidates >= 0)
        precondition(maximumWordsPerSpan >= 0)
        precondition(minimumTimeOverlap.isFinite)
        precondition(minimumEvidenceMargin.isFinite)
        precondition(minimumInsertionSupport.isFinite)
        precondition(minimumDeletionErrorProbability.isFinite)
        if let authorizedTimeRange {
            precondition(
                authorizedTimeRange.lowerBound.isFinite
                    && authorizedTimeRange.upperBound.isFinite
                    && authorizedTimeRange.lowerBound >= 0
                    && authorizedTimeRange.upperBound >= authorizedTimeRange.lowerBound
            )
        }
        self.strategy = strategy
        self.maximumCandidates = min(Self.hardMaximumCandidates, maximumCandidates)
        self.maximumWordsPerSpan = min(Self.hardMaximumWordsPerSpan, maximumWordsPerSpan)
        self.minimumTimeOverlap = min(1, max(0, minimumTimeOverlap))
        self.minimumEvidenceMargin = min(1, max(0, minimumEvidenceMargin))
        self.minimumInsertionSupport = min(1, max(0, minimumInsertionSupport))
        self.minimumDeletionErrorProbability = min(1, max(0, minimumDeletionErrorProbability))
        self.protectedDictionaryTerms = protectedDictionaryTerms
        self.authorizedWordIDs = authorizedWordIDs
        self.authorizedTimeRange = authorizedTimeRange
    }

    public static let `default` = Self()
}

/// Result of a guarded fusion attempt.  On rejection `words` is exactly the
/// primary array, preserving every primary identity and provenance edge.
public struct CandidateFusionResult: Codable, Hashable, Sendable {
    public let words: [RecognizedWord]
    public let accepted: Bool
    public let strategy: CandidateFusionStrategy
    public let reason: CandidateFusionReason
    public let alignment: WordAlignmentResult?
    public let primaryScore: Double?
    public let candidateScore: Double?
    public let margin: Double?
    public let wordsChanged: Int
    public let wordsUnlocked: Int

    public init(
        words: [RecognizedWord],
        accepted: Bool,
        strategy: CandidateFusionStrategy,
        reason: CandidateFusionReason,
        alignment: WordAlignmentResult? = nil,
        primaryScore: Double? = nil,
        candidateScore: Double? = nil,
        margin: Double? = nil,
        wordsChanged: Int = 0,
        wordsUnlocked: Int = 0
    ) {
        self.words = words
        self.accepted = accepted
        self.strategy = strategy
        self.reason = reason
        self.alignment = alignment
        self.primaryScore = primaryScore
        self.candidateScore = candidateScore
        self.margin = margin
        self.wordsChanged = wordsChanged
        self.wordsUnlocked = wordsUnlocked
    }

    public var text: String {
        words.map(\.text).joined(separator: " ")
    }

    /// Compatibility spelling for repair-decision consumers.
    public var decision: CandidateFusionReason { reason }
    public var reasonCode: String { reason.rawValue }
}

/// A bounded deterministic fusion implementation.  It provides pairwise,
/// weighted ROVER/confusion-network, and MBR/medoid experiment paths while
/// keeping one fail-closed repair guard at the output boundary.
public enum CandidateFusion {
    public static func fuse(
        primary: [RecognizedWord],
        candidates: [FusionCandidate],
        configuration: CandidateFusionConfiguration = .default
    ) -> CandidateFusionResult {
        switch configuration.strategy {
        case .pairwise:
            return pairwise(
                primary: primary,
                candidates: candidates,
                configuration: configuration
            )
        case .weightedROVER:
            return weightedROVER(
                primary: primary,
                candidates: candidates,
                configuration: configuration
            )
        case .mbrMedoid:
            return mbrMedoid(
                primary: primary,
                candidates: candidates,
                configuration: configuration
            )
        }
    }

    public static func fuse(
        primary: RecognitionResult,
        candidates: [RecognitionResult],
        configuration: CandidateFusionConfiguration = .default
    ) -> CandidateFusionResult {
        fuse(
            primary: primary.words,
            candidates: candidates.map { FusionCandidate($0) },
            configuration: configuration
        )
    }

    public static func fuse(
        primary: RecognitionResult,
        alternatives: [RecognitionAlternative],
        configuration: CandidateFusionConfiguration = .default
    ) -> CandidateFusionResult {
        fuse(
            primary: primary.words,
            candidates: alternatives.map { FusionCandidate($0) },
            configuration: configuration
        )
    }

    public static func pairwise(
        primary: [RecognizedWord],
        candidates: [FusionCandidate],
        configuration: CandidateFusionConfiguration = .default
    ) -> CandidateFusionResult {
        let preflight = preflight(
            primary: primary,
            candidates: candidates,
            configuration: configuration
        )
        guard preflight.canProceed else { return preflight.result }
        guard !candidates.isEmpty else {
            return unchanged(
                primary: primary,
                configuration: configuration,
                reason: .noCandidates
            )
        }

        var evaluations: [Evaluation] = []
        evaluations.reserveCapacity(candidates.count)
        for (ordinal, candidate) in candidates.enumerated() {
            evaluations.append(
                evaluate(
                    primary: primary,
                    candidate: candidate,
                    candidateOrdinal: ordinal,
                    configuration: configuration
                )
            )
        }

        let accepted = evaluations.filter(\.accepted)
        if let best = accepted.min(by: betterEvaluation) {
            return result(
                from: best,
                strategy: .pairwise
            )
        }
        let rejected = evaluations.min(by: preferredRejection)
        return result(
            from: rejected
                ?? Evaluation(
                    candidateOrdinal: 0,
                    alignment: nil,
                    output: primary,
                    accepted: false,
                    reason: .noCandidates,
                    score: nil,
                    margin: nil,
                    wordsChanged: 0,
                    wordsUnlocked: 0
                ),
            strategy: .pairwise
        )
    }

    public static func weightedROVER(
        primary: [RecognizedWord],
        candidates: [FusionCandidate],
        configuration: CandidateFusionConfiguration = .default
    ) -> CandidateFusionResult {
        let preflight = preflight(
            primary: primary,
            candidates: candidates,
            configuration: configuration
        )
        guard preflight.canProceed else { return preflight.result }
        guard !candidates.isEmpty else {
            return unchanged(
                primary: primary,
                configuration: configuration,
                reason: .noCandidates
            )
        }

        guard let proposal = roverProposal(
            primary: primary,
            candidates: candidates,
            configuration: configuration
        ) else {
            return unchanged(
                primary: primary,
                configuration: configuration,
                reason: .alignmentInvalid
            )
        }
        let evaluation = evaluate(
            primary: primary,
            candidate: FusionCandidate(words: proposal.words),
            candidateOrdinal: proposal.candidateOrdinal,
            configuration: configuration
        )
        return result(from: evaluation, strategy: .weightedROVER)
    }

    public static func mbrMedoid(
        primary: [RecognizedWord],
        candidates: [FusionCandidate],
        configuration: CandidateFusionConfiguration = .default
    ) -> CandidateFusionResult {
        let preflight = preflight(
            primary: primary,
            candidates: candidates,
            configuration: configuration
        )
        guard preflight.canProceed else { return preflight.result }
        guard !candidates.isEmpty else {
            return unchanged(
                primary: primary,
                configuration: configuration,
                reason: .noCandidates
            )
        }

        // The primary is always part of the medoid set and remains the safe
        // fallback.  The candidate count is capped before this extra element
        // is added, so the distance matrix remains at most 9x9.
        let all = [FusionCandidate(words: primary)] + candidates
        let count = all.count
        var distances = Array(repeating: 0.0, count: count * count)
        var valid = Array(repeating: true, count: count)
        if count > 1 {
            for lhs in 0..<count {
                for rhs in (lhs + 1)..<count {
                    guard let alignment = WordAlignment.alignIfBounded(
                        source: all[lhs].words,
                        candidate: all[rhs].words,
                        configuration: alignmentConfiguration(from: configuration)
                    ) else {
                        valid[lhs] = false
                        valid[rhs] = false
                        continue
                    }
                    distances[lhs * count + rhs] = alignment.totalScore
                    distances[rhs * count + lhs] = alignment.totalScore
                }
            }
        }

        let weights = mbrWeights(for: all)
        var risks = Array(repeating: Double.greatestFiniteMagnitude, count: count)
        for candidateIndex in 0..<count where valid[candidateIndex] {
            var risk = 0.0
            for referenceIndex in 0..<count where valid[referenceIndex] {
                risk += weights[referenceIndex] * distances[candidateIndex * count + referenceIndex]
            }
            risks[candidateIndex] = risk
        }
        guard let bestIndex = (0..<count).min(by: { lhs, rhs in
            if abs(risks[lhs] - risks[rhs]) > 1e-9 {
                return risks[lhs] < risks[rhs]
            }
            // Keeping the primary on a true tie is the safe deterministic
            // choice; otherwise preserve input candidate order.
            return lhs < rhs
        }),
        risks[bestIndex].isFinite
        else {
            return unchanged(
                primary: primary,
                configuration: configuration,
                reason: .alignmentInvalid
            )
        }

        let primaryRisk = risks[0]
        let riskMargin = primaryRisk - risks[bestIndex]
        if bestIndex == 0 {
            return unchanged(
                primary: primary,
                configuration: configuration,
                reason: .noChange,
                primaryScore: primaryRisk,
                candidateScore: primaryRisk,
                margin: 0
            )
        }
        guard riskMargin >= configuration.minimumEvidenceMargin else {
            return unchanged(
                primary: primary,
                configuration: configuration,
                reason: .ambiguousMargin,
                primaryScore: primaryRisk,
                candidateScore: risks[bestIndex],
                margin: riskMargin
            )
        }

        let candidateOrdinal = bestIndex - 1
        let evaluation = evaluate(
            primary: primary,
            candidate: candidates[candidateOrdinal],
            candidateOrdinal: candidateOrdinal,
            configuration: configuration,
            requiredMargin: riskMargin
        )
        return result(
            from: evaluation,
            strategy: .mbrMedoid,
            primaryScore: primaryRisk,
            candidateScore: risks[bestIndex],
            marginOverride: riskMargin
        )
    }

    private struct Preflight {
        let canProceed: Bool
        let result: CandidateFusionResult
    }

    private static func preflight(
        primary: [RecognizedWord],
        candidates: [FusionCandidate],
        configuration: CandidateFusionConfiguration
    ) -> Preflight {
        if primary.isEmpty {
            return Preflight(
                canProceed: false,
                result: unchanged(
                    primary: primary,
                    configuration: configuration,
                    reason: .emptyPrimary
                )
            )
        }
        guard primary.count <= configuration.maximumWordsPerSpan else {
            return Preflight(
                canProceed: false,
                result: unchanged(
                    primary: primary,
                    configuration: configuration,
                    reason: .wordLimitExceeded
                )
            )
        }
        guard candidates.count <= configuration.maximumCandidates else {
            return Preflight(
                canProceed: false,
                result: unchanged(
                    primary: primary,
                    configuration: configuration,
                    reason: .candidateLimitExceeded
                )
            )
        }
        guard uniqueIDs(in: primary) else {
            return Preflight(
                canProceed: false,
                result: unchanged(
                    primary: primary,
                    configuration: configuration,
                    reason: .duplicateWordID
                )
            )
        }
        for candidate in candidates {
            guard candidate.words.count <= configuration.maximumWordsPerSpan else {
                return Preflight(
                    canProceed: false,
                    result: unchanged(
                        primary: primary,
                        configuration: configuration,
                        reason: .wordLimitExceeded
                    )
                )
            }
            guard uniqueIDs(in: candidate.words) else {
                return Preflight(
                    canProceed: false,
                    result: unchanged(
                        primary: primary,
                        configuration: configuration,
                        reason: .duplicateWordID
                    )
                )
            }
        }
        return Preflight(
            canProceed: true,
            result: unchanged(
                primary: primary,
                configuration: configuration,
                reason: .noChange
            )
        )
    }

    private struct Evaluation {
        let candidateOrdinal: Int
        let alignment: WordAlignmentResult?
        let output: [RecognizedWord]
        let accepted: Bool
        let reason: CandidateFusionReason
        let score: Double?
        let margin: Double?
        let wordsChanged: Int
        let wordsUnlocked: Int
    }

    private struct GuardedRepair {
        let words: [RecognizedWord]
        let reason: CandidateFusionReason
        let accepted: Bool
        let margin: Double?
        let wordsChanged: Int
        let wordsUnlocked: Int
    }

    private static func evaluate(
        primary: [RecognizedWord],
        candidate: FusionCandidate,
        candidateOrdinal: Int,
        configuration: CandidateFusionConfiguration,
        requiredMargin: Double? = nil
    ) -> Evaluation {
        guard let alignment = WordAlignment.alignIfBounded(
            source: primary,
            candidate: candidate.words,
            configuration: alignmentConfiguration(from: configuration)
        ) else {
            return Evaluation(
                candidateOrdinal: candidateOrdinal,
                alignment: nil,
                output: primary,
                accepted: false,
                reason: .alignmentInvalid,
                score: nil,
                margin: nil,
                wordsChanged: 0,
                wordsUnlocked: 0
            )
        }
        guard alignment.changedOperationCount > 0 else {
            return Evaluation(
                candidateOrdinal: candidateOrdinal,
                alignment: alignment,
                output: primary,
                accepted: false,
                reason: .noChange,
                score: alignment.totalScore,
                margin: requiredMargin ?? 0,
                wordsChanged: 0,
                wordsUnlocked: 0
            )
        }

        let repair = guardedRepair(
            primary: primary,
            candidate: candidate,
            alignment: alignment,
            configuration: configuration,
            requiredMargin: requiredMargin
        )
        return Evaluation(
            candidateOrdinal: candidateOrdinal,
            alignment: alignment,
            output: repair.accepted ? repair.words : primary,
            accepted: repair.accepted,
            reason: repair.reason,
            score: alignment.totalScore,
            margin: repair.margin,
            wordsChanged: repair.wordsChanged,
            wordsUnlocked: repair.wordsUnlocked
        )
    }

    private static func guardedRepair(
        primary: [RecognizedWord],
        candidate: FusionCandidate,
        alignment: WordAlignmentResult,
        configuration: CandidateFusionConfiguration,
        requiredMargin: Double?
    ) -> GuardedRepair {
        let sourceDictionary = protectedTermIndices(
            in: primary,
            terms: configuration.protectedDictionaryTerms
        )
        let candidateDictionary = protectedTermIndices(
            in: candidate.words,
            terms: configuration.protectedDictionaryTerms
        )
        let authorizedIDs = configuration.authorizedWordIDs
            ?? Set(primary.map(\.id))

        var output: [RecognizedWord] = []
        output.reserveCapacity(candidate.words.count)
        var margins: [Double] = []
        var changed = 0
        var unlocked = 0

        for (operationIndex, operation) in alignment.operations.enumerated() {
            switch operation.kind {
            case .match:
                guard let sourceWord = operation.sourceWord else {
                    return rejected(primary, .alignmentInvalid)
                }
                output.append(sourceWord)

            case .substitution:
                guard let sourceWord = operation.sourceWord,
                      let candidateWord = operation.candidateWord
                else {
                    return rejected(primary, .alignmentInvalid)
                }
                if !operation.isLexicalChange {
                    output.append(sourceWord)
                    continue
                }
                guard authorizedIDs.contains(sourceWord.id) else {
                    return rejected(primary, .outsideAuthorizedSpan)
                }
                guard authorizedTimeContains(
                    sourceWord,
                    candidate: candidateWord,
                    range: configuration.authorizedTimeRange
                ) else {
                    return rejected(primary, .outsideAuthorizedSpan)
                }
                if let reason = semanticGuardReason(
                    source: sourceWord,
                    candidate: candidateWord,
                    sourceIndex: operation.sourceIndex,
                    candidateIndex: operation.candidateIndex,
                    sourceDictionary: sourceDictionary,
                    candidateDictionary: candidateDictionary
                ) {
                    return rejected(primary, reason)
                }
                guard candidateWord.id != sourceWord.id else {
                    return rejected(primary, .invalidCandidate)
                }
                guard let overlap = operation.timeOverlap else {
                    return rejected(primary, .insufficientEvidence)
                }
                guard overlap >= configuration.minimumTimeOverlap else {
                    return rejected(primary, .lowTimeOverlap)
                }
                guard let sourceSupport = support(of: sourceWord),
                      let candidateSupport = support(of: candidateWord)
                else {
                    return rejected(primary, .insufficientEvidence)
                }
                let margin = candidateSupport - sourceSupport
                guard margin >= configuration.minimumEvidenceMargin else {
                    return rejected(primary, .ambiguousMargin)
                }
                if let requiredMargin, requiredMargin < configuration.minimumEvidenceMargin {
                    return rejected(primary, .ambiguousMargin)
                }
                margins.append(margin)
                output.append(
                    replacementWord(
                        source: sourceWord,
                        candidate: candidateWord,
                        kind: .replacement,
                        reason: .accepted,
                        sourceWordIDs: [sourceWord.id]
                    )
                )
                changed += 1
                if sourceWord.lockState == .unlocked { unlocked += 1 }

            case .insertion:
                guard let candidateWord = operation.candidateWord else {
                    return rejected(primary, .alignmentInvalid)
                }
                if let reason = semanticGuardReason(
                    source: nil,
                    candidate: candidateWord,
                    sourceIndex: nil,
                    candidateIndex: operation.candidateIndex,
                    sourceDictionary: sourceDictionary,
                    candidateDictionary: candidateDictionary
                ) {
                    return rejected(primary, reason)
                }
                let neighbors = neighboringSourceWords(
                    around: operationIndex,
                    operations: alignment.operations
                )
                let authorizedNeighbor = neighbors.contains { authorizedIDs.contains($0.id) }
                guard authorizedNeighbor || isInsideAuthorizedTimeRange(
                    candidateWord,
                    range: configuration.authorizedTimeRange
                ) else {
                    return rejected(primary, .outsideAuthorizedSpan)
                }
                let overlap = neighbors.compactMap {
                    WordAlignment.timeOverlap($0, candidateWord)
                }.max()
                if let overlap {
                    guard overlap >= configuration.minimumTimeOverlap else {
                        return rejected(primary, .lowTimeOverlap)
                    }
                } else if configuration.authorizedTimeRange == nil {
                    return rejected(primary, .insufficientEvidence)
                }
                guard let candidateSupport = support(of: candidateWord),
                      candidateSupport >= configuration.minimumInsertionSupport
                else {
                    return rejected(primary, .insufficientEvidence)
                }
                guard !output.contains(where: { $0.id == candidateWord.id }) else {
                    return rejected(primary, .invalidCandidate)
                }
                let sourceIDs = neighbors.map(\.id)
                output.append(
                    replacementWord(
                        source: nil,
                        candidate: candidateWord,
                        kind: .fused,
                        reason: .accepted,
                        sourceWordIDs: sourceIDs
                    )
                )
                changed += 1
                unlocked += 1

            case .deletion:
                guard let sourceWord = operation.sourceWord else {
                    return rejected(primary, .alignmentInvalid)
                }
                guard authorizedIDs.contains(sourceWord.id) else {
                    return rejected(primary, .outsideAuthorizedSpan)
                }
                guard authorizedTimeContains(
                    sourceWord,
                    candidate: nil,
                    range: configuration.authorizedTimeRange
                ) else {
                    return rejected(primary, .outsideAuthorizedSpan)
                }
                if let reason = semanticGuardReason(
                    source: sourceWord,
                    candidate: nil,
                    sourceIndex: operation.sourceIndex,
                    candidateIndex: nil,
                    sourceDictionary: sourceDictionary,
                    candidateDictionary: candidateDictionary
                ) {
                    return rejected(primary, reason)
                }
                guard let sourceSupport = support(of: sourceWord),
                      1 - sourceSupport >= configuration.minimumDeletionErrorProbability
                else {
                    return rejected(primary, .insufficientEvidence)
                }
                let candidateNeighbors = neighboringCandidateWords(
                    around: operationIndex,
                    operations: alignment.operations
                )
                guard !candidateNeighbors.isEmpty,
                      candidateNeighbors.allSatisfy({ support(of: $0) != nil })
                else {
                    return rejected(primary, .insufficientEvidence)
                }
                let neighborSupport = candidateNeighbors.compactMap { support(of: $0) }.reduce(0, +)
                    / Double(candidateNeighbors.count)
                let margin = neighborSupport - sourceSupport
                guard margin >= configuration.minimumEvidenceMargin else {
                    return rejected(primary, .ambiguousMargin)
                }
                margins.append(margin)
                changed += 1
                if sourceWord.lockState == .unlocked { unlocked += 1 }
            }
        }

        guard !output.isEmpty || primary.isEmpty else {
            return rejected(primary, .emptyResult)
        }
        guard output.count <= configuration.maximumWordsPerSpan,
              uniqueIDs(in: output),
              timestampOrderIsValid(output),
              lockedWordsPreserved(primary: primary, output: output)
        else {
            return rejected(primary, .alignmentInvalid)
        }

        let margin = margins.isEmpty
            ? requiredMargin
            : margins.min() ?? requiredMargin
        return GuardedRepair(
            words: output,
            reason: .accepted,
            accepted: true,
            margin: margin,
            wordsChanged: changed,
            wordsUnlocked: unlocked
        )
    }

    private struct RoverProposal {
        let words: [RecognizedWord]
        let candidateOrdinal: Int
    }

    private struct RoverMember {
        let word: RecognizedWord
        let candidateOrdinal: Int
        let weight: Double
        let isPrimary: Bool
    }

    private static func roverProposal(
        primary: [RecognizedWord],
        candidates: [FusionCandidate],
        configuration: CandidateFusionConfiguration
    ) -> RoverProposal? {
        var columns = Array(repeating: [RoverMember](), count: primary.count)
        var insertionColumns = Array(repeating: [RoverMember](), count: primary.count + 1)
        for (index, word) in primary.enumerated() {
            columns[index].append(
                RoverMember(
                    word: word,
                    candidateOrdinal: -1,
                    // Unknown support is not promoted to confidence; a
                    // missing primary signal contributes no vote and the
                    // guarded repair still requires explicit candidate
                    // evidence.
                    weight: support(of: word) ?? 0,
                    isPrimary: true
                )
            )
        }

        let candidateWeight = 1 / Double(max(1, candidates.count))
        for (ordinal, candidate) in candidates.enumerated() {
            guard let alignment = WordAlignment.alignIfBounded(
                source: primary,
                candidate: candidate.words,
                configuration: alignmentConfiguration(from: configuration)
            ) else {
                continue
            }
            var consumedSource = 0
            for operation in alignment.operations {
                switch operation.kind {
                case .match, .substitution:
                    if let sourceIndex = operation.sourceIndex,
                       let word = operation.candidateWord,
                       sourceIndex < columns.count
                    {
                        let supportWeight = support(of: word) ?? 0
                        columns[sourceIndex].append(
                            RoverMember(
                                word: word,
                                candidateOrdinal: ordinal,
                                weight: candidateWeight * supportWeight,
                                isPrimary: false
                            )
                        )
                    }
                    consumedSource += 1
                case .deletion:
                    consumedSource += 1
                case .insertion:
                    if let word = operation.candidateWord {
                        let boundary = min(insertionColumns.count - 1, max(0, consumedSource))
                        let supportWeight = support(of: word) ?? 0
                        insertionColumns[boundary].append(
                            RoverMember(
                                word: word,
                                candidateOrdinal: ordinal,
                                weight: candidateWeight * supportWeight,
                                isPrimary: false
                            )
                        )
                    }
                }
            }
        }

        var proposal: [RecognizedWord] = []
        proposal.reserveCapacity(primary.count)
        var selectedOrdinal = 0
        for boundary in 0...primary.count {
            if let insertion = winningMember(insertionColumns[boundary]) {
                proposal.append(insertion.word)
                if insertion.candidateOrdinal >= 0 { selectedOrdinal = insertion.candidateOrdinal }
            }
            guard boundary < primary.count else { continue }
            guard let winner = winningMember(columns[boundary]) else { return nil }
            proposal.append(winner.word)
            if winner.candidateOrdinal >= 0 { selectedOrdinal = winner.candidateOrdinal }
        }
        return RoverProposal(words: proposal, candidateOrdinal: selectedOrdinal)
    }

    private static func winningMember(_ members: [RoverMember]) -> RoverMember? {
        guard !members.isEmpty else { return nil }
        var totals: [String: Double] = [:]
        for member in members {
            let key = WordAlignment.normalizedLexicalToken(member.word.text)
            totals[key, default: 0] += member.weight
        }
        guard let winningKey = totals.keys.sorted(by: { lhs, rhs in
            let left = totals[lhs] ?? 0
            let right = totals[rhs] ?? 0
            if abs(left - right) > 1e-9 { return left > right }
            return lhs < rhs
        }).first else { return nil }
        return members
            .filter { WordAlignment.normalizedLexicalToken($0.word.text) == winningKey }
            .sorted { lhs, rhs in
                if lhs.isPrimary != rhs.isPrimary { return lhs.isPrimary }
                if lhs.candidateOrdinal != rhs.candidateOrdinal {
                    return lhs.candidateOrdinal < rhs.candidateOrdinal
                }
                return lhs.word.id.rawValue < rhs.word.id.rawValue
            }
            .first
    }

    private static func result(
        from evaluation: Evaluation,
        strategy: CandidateFusionStrategy,
        primaryScore: Double? = nil,
        candidateScore: Double? = nil,
        marginOverride: Double? = nil
    ) -> CandidateFusionResult {
        CandidateFusionResult(
            words: evaluation.output,
            accepted: evaluation.accepted,
            strategy: strategy,
            reason: evaluation.reason,
            alignment: evaluation.alignment,
            primaryScore: primaryScore ?? (evaluation.accepted ? 0 : evaluation.score),
            candidateScore: candidateScore ?? evaluation.score,
            margin: marginOverride ?? evaluation.margin,
            wordsChanged: evaluation.wordsChanged,
            wordsUnlocked: evaluation.wordsUnlocked
        )
    }

    private static func unchanged(
        primary: [RecognizedWord],
        configuration: CandidateFusionConfiguration,
        reason: CandidateFusionReason,
        primaryScore: Double? = nil,
        candidateScore: Double? = nil,
        margin: Double? = nil
    ) -> CandidateFusionResult {
        CandidateFusionResult(
            words: primary,
            accepted: false,
            strategy: configuration.strategy,
            reason: reason,
            primaryScore: primaryScore,
            candidateScore: candidateScore,
            margin: margin
        )
    }

    private static func rejected(
        _ primary: [RecognizedWord],
        _ reason: CandidateFusionReason
    ) -> GuardedRepair {
        GuardedRepair(
            words: primary,
            reason: reason,
            accepted: false,
            margin: nil,
            wordsChanged: 0,
            wordsUnlocked: 0
        )
    }

    private static func betterEvaluation(_ lhs: Evaluation, _ rhs: Evaluation) -> Bool {
        let lhsScore = lhs.score ?? .greatestFiniteMagnitude
        let rhsScore = rhs.score ?? .greatestFiniteMagnitude
        if abs(lhsScore - rhsScore) > 1e-9 { return lhsScore < rhsScore }
        let lhsMargin = lhs.margin ?? -.greatestFiniteMagnitude
        let rhsMargin = rhs.margin ?? -.greatestFiniteMagnitude
        if abs(lhsMargin - rhsMargin) > 1e-9 { return lhsMargin > rhsMargin }
        return lhs.candidateOrdinal < rhs.candidateOrdinal
    }

    private static func preferredRejection(_ lhs: Evaluation, _ rhs: Evaluation) -> Bool {
        let order: [CandidateFusionReason: Int] = [
            .lockedAnchor: 0,
            .protectedDictionaryTerm: 1,
            .numberChange: 2,
            .identifierChange: 3,
            .negationChange: 4,
            .destructiveCommandChange: 5,
            .lowTimeOverlap: 6,
            .outsideAuthorizedSpan: 7,
            .insufficientEvidence: 8,
            .ambiguousMargin: 9,
            .invalidCandidate: 10,
            .alignmentInvalid: 11,
            .noChange: 12,
            .emptyResult: 13,
            .duplicateWordID: 14,
            .candidateLimitExceeded: 15,
            .wordLimitExceeded: 16,
            .emptyPrimary: 17,
            .noCandidates: 18,
            .accepted: 19
        ]
        let lhsRank = order[lhs.reason] ?? Int.max
        let rhsRank = order[rhs.reason] ?? Int.max
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        return lhs.candidateOrdinal < rhs.candidateOrdinal
    }

    private static func alignmentConfiguration(
        from configuration: CandidateFusionConfiguration
    ) -> WordAlignmentConfiguration {
        WordAlignmentConfiguration(
            maximumSourceWords: configuration.maximumWordsPerSpan,
            maximumCandidateWords: configuration.maximumWordsPerSpan
        )
    }

    private static func uniqueIDs(in words: [RecognizedWord]) -> Bool {
        var ids = Set<StableWordID>()
        ids.reserveCapacity(words.count)
        for word in words where !ids.insert(word.id).inserted {
            return false
        }
        return true
    }

    private static func support(of word: RecognizedWord) -> Double? {
        if let error = word.calibratedErrorProbability,
           error.isFinite,
           (0...1).contains(error)
        {
            return 1 - error
        }
        guard word.rawEvidence.availability.contains(.posterior),
              let posterior = word.rawEvidence.posterior,
              posterior.isFinite,
              (0...1).contains(posterior)
        else {
            return nil
        }
        return posterior
    }

    private static func replacementWord(
        source: RecognizedWord?,
        candidate: RecognizedWord,
        kind: WordProvenanceKind,
        reason: CandidateFusionReason,
        sourceWordIDs: [StableWordID]
    ) -> RecognizedWord {
        var ids: [StableWordID] = []
        ids.reserveCapacity(min(64, sourceWordIDs.count + candidate.provenance.sourceWordIDs.count))
        for id in sourceWordIDs + candidate.provenance.sourceWordIDs where !ids.contains(id) {
            guard ids.count < 64 else { break }
            ids.append(id)
        }
        return RecognizedWord(
            id: candidate.id,
            text: candidate.text,
            startSeconds: candidate.startSeconds,
            endSeconds: candidate.endSeconds,
            tokenRange: candidate.tokenRange,
            rawEvidence: candidate.rawEvidence,
            calibratedErrorProbability: candidate.calibratedErrorProbability,
            lockState: candidate.lockState,
            provenance: WordProvenance(
                kind: kind,
                sourceWordIDs: ids,
                providerDecodeID: candidate.id.providerDecodeID,
                providerWordIndex: candidate.id.wordIndex,
                reason: reason.rawValue
            )
        )
    }

    private static func neighboringSourceWords(
        around operationIndex: Int,
        operations: [WordAlignmentOperation]
    ) -> [RecognizedWord] {
        var result: [RecognizedWord] = []
        if operationIndex > 0 {
            for index in stride(from: operationIndex - 1, through: 0, by: -1) {
                if let word = operations[index].sourceWord {
                    result.append(word)
                    break
                }
            }
        }
        if operationIndex + 1 < operations.count {
            for index in (operationIndex + 1)..<operations.count {
                if let word = operations[index].sourceWord {
                    result.append(word)
                    break
                }
            }
        }
        return result
    }

    private static func neighboringCandidateWords(
        around operationIndex: Int,
        operations: [WordAlignmentOperation]
    ) -> [RecognizedWord] {
        var result: [RecognizedWord] = []
        if operationIndex > 0 {
            for index in stride(from: operationIndex - 1, through: 0, by: -1) {
                if let word = operations[index].candidateWord {
                    result.append(word)
                    break
                }
            }
        }
        if operationIndex + 1 < operations.count {
            for index in (operationIndex + 1)..<operations.count {
                if let word = operations[index].candidateWord {
                    result.append(word)
                    break
                }
            }
        }
        return result
    }

    private static func protectedTermIndices(
        in words: [RecognizedWord],
        terms: Set<String>
    ) -> Set<Int> {
        let termTokens = terms.map { term in
            term.split(whereSeparator: { $0.isWhitespace })
                .map { WordAlignment.normalizedLexicalToken(String($0)) }
                .filter { !$0.isEmpty }
        }.filter { !$0.isEmpty }
        guard !termTokens.isEmpty else { return [] }
        let tokens = words.map { WordAlignment.normalizedLexicalToken($0.text) }
        var protectedIndices = Set<Int>()
        for phrase in termTokens {
            guard phrase.count <= tokens.count else { continue }
            for start in 0...(tokens.count - phrase.count) {
                guard Array(tokens[start..<(start + phrase.count)]) == phrase else { continue }
                for index in start..<(start + phrase.count) {
                    protectedIndices.insert(index)
                }
            }
        }
        return protectedIndices
    }

    private static func semanticGuardReason(
        source: RecognizedWord?,
        candidate: RecognizedWord?,
        sourceIndex: Int?,
        candidateIndex: Int?,
        sourceDictionary: Set<Int>,
        candidateDictionary: Set<Int>
    ) -> CandidateFusionReason? {
        if let source,
           (source.lockState == .locked || source.lockState == .protected),
           let candidate,
           WordAlignment.normalizedLexicalToken(source.text)
                != WordAlignment.normalizedLexicalToken(candidate.text)
        {
            return .lockedAnchor
        }
        if let sourceIndex, sourceDictionary.contains(sourceIndex),
           let source, let candidate,
           WordAlignment.normalizedLexicalToken(source.text)
                != WordAlignment.normalizedLexicalToken(candidate.text)
        {
            return .protectedDictionaryTerm
        }
        if let candidateIndex, candidateDictionary.contains(candidateIndex),
           let source, let candidate,
           WordAlignment.normalizedLexicalToken(source.text)
                != WordAlignment.normalizedLexicalToken(candidate.text)
        {
            return .protectedDictionaryTerm
        }
        if let source, let candidate,
           WordAlignment.normalizedLexicalToken(source.text)
                != WordAlignment.normalizedLexicalToken(candidate.text)
        {
            if isIdentifierLike(source.text) || isIdentifierLike(candidate.text) {
                return .identifierChange
            }
            if isNumberLike(source.text) || isNumberLike(candidate.text) {
                return .numberChange
            }
            if isNegation(source.text) || isNegation(candidate.text) {
                return .negationChange
            }
            if isDestructiveCommand(source.text) || isDestructiveCommand(candidate.text) {
                return .destructiveCommandChange
            }
        } else if let source {
            if isNumberLike(source.text) { return .numberChange }
            if isIdentifierLike(source.text) { return .identifierChange }
            if isNegation(source.text) { return .negationChange }
            if isDestructiveCommand(source.text) { return .destructiveCommandChange }
        } else if let candidate {
            if isNumberLike(candidate.text) { return .numberChange }
            if isIdentifierLike(candidate.text) { return .identifierChange }
            if isNegation(candidate.text) { return .negationChange }
            if isDestructiveCommand(candidate.text) { return .destructiveCommandChange }
        }
        if let source,
           (source.lockState == .locked || source.lockState == .protected)
        {
            if let candidate,
               WordAlignment.normalizedLexicalToken(source.text)
                    != WordAlignment.normalizedLexicalToken(candidate.text)
            {
                return .lockedAnchor
            }
            if candidate == nil { return .lockedAnchor }
        }
        return nil
    }

    private static func isNumberLike(_ text: String) -> Bool {
        if text.unicodeScalars.contains(where: { CharacterSet.decimalDigits.contains($0) }) {
            return true
        }
        let token = WordAlignment.normalizedLexicalToken(text)
        let numberWords: Set<String> = [
            "zero", "one", "two", "three", "four", "five", "six", "seven", "eight",
            "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen",
            "sixteen", "seventeen", "eighteen", "nineteen", "twenty", "thirty", "forty",
            "fifty", "sixty", "seventy", "eighty", "ninety", "hundred", "thousand",
            "million", "billion", "first", "second", "third", "fourth", "fifth"
        ]
        return numberWords.contains(token)
    }

    private static func isIdentifierLike(_ text: String) -> Bool {
        let scalars = Array(text.unicodeScalars)
        guard !scalars.isEmpty else { return false }
        let hasLetter = scalars.contains { CharacterSet.letters.contains($0) }
        let hasDigit = scalars.contains { CharacterSet.decimalDigits.contains($0) }
        if hasLetter && hasDigit { return true }
        if scalars.contains(where: { "_/@.#".unicodeScalars.contains($0) }) { return true }
        let letters = scalars.filter { CharacterSet.letters.contains($0) }
        let uppercaseCount = letters.filter { CharacterSet.uppercaseLetters.contains($0) }.count
        return letters.count >= 2 && uppercaseCount == letters.count
    }

    private static func isNegation(_ text: String) -> Bool {
        let token = WordAlignment.normalizedLexicalToken(text)
        return [
            "no", "not", "never", "cannot", "cant", "wont", "dont", "doesnt", "didnt",
            "wouldnt", "shouldnt", "isnt", "arent", "wasnt", "werent", "neither", "nor",
            "without", "hardly"
        ].contains(token)
    }

    private static func isDestructiveCommand(_ text: String) -> Bool {
        let token = WordAlignment.normalizedLexicalToken(text)
        return [
            "delete", "erase", "remove", "drop", "destroy", "wipe", "kill", "terminate",
            "shutdown", "uninstall", "format", "overwrite", "reset", "clear", "discard",
            "revoke", "cancel"
        ].contains(token)
    }

    private static func isInsideAuthorizedTimeRange(
        _ word: RecognizedWord,
        range: ClosedRange<Double>?
    ) -> Bool {
        guard let range else { return false }
        guard let start = word.startSeconds, let end = word.endSeconds else { return false }
        return start >= range.lowerBound && end <= range.upperBound
    }

    private static func authorizedTimeContains(
        _ source: RecognizedWord,
        candidate: RecognizedWord?,
        range: ClosedRange<Double>?
    ) -> Bool {
        guard let range else { return true }
        guard isInsideAuthorizedTimeRange(source, range: range) else { return false }
        if let candidate {
            return isInsideAuthorizedTimeRange(candidate, range: range)
        }
        return true
    }

    private static func timestampOrderIsValid(_ words: [RecognizedWord]) -> Bool {
        var previousStart: Double?
        var previousEnd: Double?
        for word in words {
            guard let start = word.startSeconds, let end = word.endSeconds else { continue }
            guard start.isFinite, end.isFinite, start >= 0, end >= start else { return false }
            if let previousStart, start < previousStart - 1e-9 { return false }
            if let previousEnd, end < previousEnd - 1e-9 { return false }
            previousStart = start
            previousEnd = end
        }
        return true
    }

    private static func lockedWordsPreserved(
        primary: [RecognizedWord],
        output: [RecognizedWord]
    ) -> Bool {
        let outputByID = Dictionary(uniqueKeysWithValues: output.map { ($0.id, $0) })
        for word in primary where word.lockState == .locked || word.lockState == .protected {
            guard let outputWord = outputByID[word.id],
                  WordAlignment.normalizedLexicalToken(outputWord.text)
                    == WordAlignment.normalizedLexicalToken(word.text)
            else { return false }
        }
        return true
    }

    private static func mbrWeights(for candidates: [FusionCandidate]) -> [Double] {
        let provided = candidates.dropFirst().compactMap(\.posterior)
        if provided.count == candidates.count - 1 {
            let primaryWeight = provided.isEmpty
                ? 1
                : provided.reduce(0, +) / Double(provided.count)
            let raw = [primaryWeight] + provided
            let total = raw.reduce(0, +)
            if total > 0 { return raw.map { $0 / total } }
        }
        return Array(repeating: 1 / Double(max(1, candidates.count)), count: candidates.count)
    }
}

/// Compatibility aliases for pipeline code that uses “repair” terminology.
public typealias FusionDecision = CandidateFusionResult
public typealias CandidateFusionDecision = CandidateFusionResult
