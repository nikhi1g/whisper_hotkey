import Foundation

/// The operation selected by the bounded word aligner.
public enum WordAlignmentOperationKind: String, Codable, Hashable, Sendable {
    case match
    case substitution
    case insertion
    case deletion
}

/// The individual terms used to score one alignment operation.
///
/// `confidencePenalty` is optional on purpose.  A missing provider signal is
/// not converted into a made-up probability.  The aligner may still use the
/// configured missing-evidence cost when ranking paths, but callers can see
/// that the confidence term was unavailable.
public struct WordAlignmentScoreBreakdown: Codable, Hashable, Sendable {
    public let lexicalDistance: Double
    public let timeOverlapPenalty: Double
    public let confidencePenalty: Double?
    public let gapPenalty: Double
    public let anchorPenalty: Double
    public let total: Double

    public init(
        lexicalDistance: Double,
        timeOverlapPenalty: Double,
        confidencePenalty: Double?,
        gapPenalty: Double,
        anchorPenalty: Double,
        total: Double
    ) {
        self.lexicalDistance = lexicalDistance
        self.timeOverlapPenalty = timeOverlapPenalty
        self.confidencePenalty = confidencePenalty
        self.gapPenalty = gapPenalty
        self.anchorPenalty = anchorPenalty
        self.total = total
    }

    /// Compatibility spelling for consumers that call the operation cost a
    /// score rather than a distance.
    public var score: Double { total }
}

/// Typed output of timestamp-aware dynamic-programming alignment.
public struct WordAlignmentOperation: Codable, Hashable, Sendable {
    public let kind: WordAlignmentOperationKind
    public let sourceIndex: Int?
    public let candidateIndex: Int?
    public let sourceWord: RecognizedWord?
    public let candidateWord: RecognizedWord?
    public let timeOverlap: Double?
    public let score: WordAlignmentScoreBreakdown

    public init(
        kind: WordAlignmentOperationKind,
        sourceIndex: Int?,
        candidateIndex: Int?,
        sourceWord: RecognizedWord?,
        candidateWord: RecognizedWord?,
        timeOverlap: Double?,
        score: WordAlignmentScoreBreakdown
    ) {
        self.kind = kind
        self.sourceIndex = sourceIndex
        self.candidateIndex = candidateIndex
        self.sourceWord = sourceWord
        self.candidateWord = candidateWord
        self.timeOverlap = timeOverlap
        self.score = score
    }

    public var sourceWordID: StableWordID? { sourceWord?.id }
    public var candidateWordID: StableWordID? { candidateWord?.id }

    /// Aliases keep the operation useful at call sites that use “primary”
    /// and “alternate” terminology.
    public var primaryWord: RecognizedWord? { sourceWord }
    public var alternateWord: RecognizedWord? { candidateWord }
    public var primaryWordID: StableWordID? { sourceWordID }
    public var alternateWordID: StableWordID? { candidateWordID }

    public var isLexicalChange: Bool {
        guard let sourceWord, let candidateWord else {
            return kind == .insertion || kind == .deletion
        }
        return WordAlignment.normalizedLexicalToken(sourceWord.text)
            != WordAlignment.normalizedLexicalToken(candidateWord.text)
    }
}

/// A bounded, typed alignment path.  The path contains no synthesized text;
/// every non-deletion word comes from one of the two input arrays.
public struct WordAlignmentResult: Codable, Hashable, Sendable {
    public let operations: [WordAlignmentOperation]
    public let totalScore: Double
    public let sourceWordCount: Int
    public let candidateWordCount: Int

    public init(
        operations: [WordAlignmentOperation],
        totalScore: Double,
        sourceWordCount: Int,
        candidateWordCount: Int
    ) {
        self.operations = operations
        self.totalScore = totalScore
        self.sourceWordCount = sourceWordCount
        self.candidateWordCount = candidateWordCount
    }

    public var score: Double { totalScore }
    public var matchedOperationCount: Int {
        operations.reduce(into: 0) { count, operation in
            if operation.kind == .match { count += 1 }
        }
    }
    public var changedOperationCount: Int {
        operations.reduce(into: 0) { count, operation in
            if operation.isLexicalChange { count += 1 }
        }
    }
    public var hasInsertionsOrDeletions: Bool {
        operations.contains { operation in
            operation.kind == .insertion || operation.kind == .deletion
        }
    }

    /// The source IDs participating in the path, in source order.
    public var sourceWordIDs: [StableWordID] {
        operations.compactMap(\.sourceWordID)
    }

    /// The candidate IDs participating in the path, in candidate order.
    public var candidateWordIDs: [StableWordID] {
        operations.compactMap(\.candidateWordID)
    }
}

/// Hard limits for the aligner.  A caller may lower these values, but cannot
/// raise the process-wide bounds and accidentally create a session-sized
/// lattice.
public struct WordAlignmentConfiguration: Codable, Hashable, Sendable {
    public static let hardMaximumWords = 128
    public static let hardMaximumCells = 16_384

    public let maximumSourceWords: Int
    public let maximumCandidateWords: Int
    public let maximumCells: Int
    public let substitutionBaseCost: Double
    public let insertionBaseCost: Double
    public let deletionBaseCost: Double
    public let timeOverlapWeight: Double
    public let confidenceWeight: Double
    public let missingConfidencePenalty: Double
    public let lockedAnchorPenalty: Double
    public let gapDurationWeight: Double

    public init(
        maximumSourceWords: Int = Self.hardMaximumWords,
        maximumCandidateWords: Int = Self.hardMaximumWords,
        maximumCells: Int = Self.hardMaximumCells,
        substitutionBaseCost: Double = 1.0,
        insertionBaseCost: Double = 1.0,
        deletionBaseCost: Double = 1.0,
        timeOverlapWeight: Double = 1.0,
        confidenceWeight: Double = 0.25,
        missingConfidencePenalty: Double = 0.2,
        lockedAnchorPenalty: Double = 1_000_000,
        gapDurationWeight: Double = 0.25
    ) {
        precondition(maximumSourceWords >= 0)
        precondition(maximumCandidateWords >= 0)
        precondition(maximumCells >= 0)
        precondition(substitutionBaseCost.isFinite && substitutionBaseCost >= 0)
        precondition(insertionBaseCost.isFinite && insertionBaseCost >= 0)
        precondition(deletionBaseCost.isFinite && deletionBaseCost >= 0)
        precondition(timeOverlapWeight.isFinite && timeOverlapWeight >= 0)
        precondition(confidenceWeight.isFinite && confidenceWeight >= 0)
        precondition(missingConfidencePenalty.isFinite && missingConfidencePenalty >= 0)
        precondition(lockedAnchorPenalty.isFinite && lockedAnchorPenalty >= 0)
        precondition(gapDurationWeight.isFinite && gapDurationWeight >= 0)
        self.maximumSourceWords = min(Self.hardMaximumWords, maximumSourceWords)
        self.maximumCandidateWords = min(Self.hardMaximumWords, maximumCandidateWords)
        self.maximumCells = min(Self.hardMaximumCells, maximumCells)
        self.substitutionBaseCost = substitutionBaseCost
        self.insertionBaseCost = insertionBaseCost
        self.deletionBaseCost = deletionBaseCost
        self.timeOverlapWeight = timeOverlapWeight
        self.confidenceWeight = confidenceWeight
        self.missingConfidencePenalty = missingConfidencePenalty
        self.lockedAnchorPenalty = lockedAnchorPenalty
        self.gapDurationWeight = gapDurationWeight
    }

    public static let `default` = Self()
}

public enum WordAlignmentError: Error, Equatable, Sendable {
    case sourceWordLimitExceeded(actual: Int, maximum: Int)
    case candidateWordLimitExceeded(actual: Int, maximum: Int)
    case cellLimitExceeded(actual: Int, maximum: Int)
}

/// Timestamp-aware word alignment using bounded dynamic programming.
///
/// Score memory is `O(min(n,m))`; the backtrace stores one byte per bounded
/// cell, so total memory is `O(min(n,m) + n*m)` with an explicit 16,384-cell
/// ceiling.  The algorithm is deterministic: ties prefer diagonal, then
/// deletion, then insertion paths.
public struct WordAlignment: Sendable {
    public static func align(
        source: [RecognizedWord],
        candidate: [RecognizedWord],
        configuration: WordAlignmentConfiguration = .default
    ) throws -> WordAlignmentResult {
        guard source.count <= configuration.maximumSourceWords else {
            throw WordAlignmentError.sourceWordLimitExceeded(
                actual: source.count,
                maximum: configuration.maximumSourceWords
            )
        }
        guard candidate.count <= configuration.maximumCandidateWords else {
            throw WordAlignmentError.candidateWordLimitExceeded(
                actual: candidate.count,
                maximum: configuration.maximumCandidateWords
            )
        }
        let cellCount = source.count.multipliedReportingOverflow(by: candidate.count)
        guard !cellCount.overflow, cellCount.partialValue <= configuration.maximumCells else {
            throw WordAlignmentError.cellLimitExceeded(
                actual: cellCount.overflow ? Int.max : cellCount.partialValue,
                maximum: configuration.maximumCells
            )
        }

        let sourceCount = source.count
        let candidateCount = candidate.count
        let rowWidth = candidateCount + 1
        var previous = Array(repeating: 0.0, count: rowWidth)
        var current = Array(repeating: 0.0, count: rowWidth)
        var backtrace = Array(repeating: BacktraceStep.origin.rawValue, count: rowWidth * (sourceCount + 1))

        if candidateCount > 0 {
            for candidateIndex in 1...candidateCount {
                let operation = insertionBreakdown(
                    candidate[candidateIndex - 1],
                    configuration: configuration
                )
                previous[candidateIndex] = previous[candidateIndex - 1] + operation.total
                backtrace[candidateIndex] = BacktraceStep.insertion.rawValue
            }
        }

        if sourceCount > 0 {
            for sourceIndex in 1...sourceCount {
                let rowOffset = sourceIndex * rowWidth
                let deletion = deletionBreakdown(
                    source[sourceIndex - 1],
                    configuration: configuration
                )
                current[0] = previous[0] + deletion.total
                backtrace[rowOffset] = BacktraceStep.deletion.rawValue

                if candidateCount > 0 {
                    for candidateIndex in 1...candidateCount {
                        let diagonal = substitutionBreakdown(
                            source[sourceIndex - 1],
                            candidate[candidateIndex - 1],
                            configuration: configuration
                        )
                        let diagonalScore = previous[candidateIndex - 1] + diagonal.total

                        let insertion = insertionBreakdown(
                            candidate[candidateIndex - 1],
                            configuration: configuration
                        )
                        let insertionScore = current[candidateIndex - 1] + insertion.total

                        let deletionScore = previous[candidateIndex]
                            + deletionBreakdown(
                                source[sourceIndex - 1],
                                configuration: configuration
                            ).total

                        let selected = selectMinimum(
                            diagonal: diagonalScore,
                            deletion: deletionScore,
                            insertion: insertionScore
                        )
                        current[candidateIndex] = selected.score
                        backtrace[rowOffset + candidateIndex] = selected.step.rawValue
                    }
                }

                swap(&previous, &current)
            }
        }

        var operations: [WordAlignmentOperation] = []
        operations.reserveCapacity(sourceCount + candidateCount)
        var sourceIndex = sourceCount
        var candidateIndex = candidateCount
        while sourceIndex > 0 || candidateIndex > 0 {
            let step = BacktraceStep(rawValue: backtrace[sourceIndex * rowWidth + candidateIndex])
                ?? .origin
            switch step {
            case .diagonal:
                let resolvedSourceIndex = sourceIndex - 1
                let resolvedCandidateIndex = candidateIndex - 1
                let sourceWord = source[resolvedSourceIndex]
                let candidateWord = candidate[resolvedCandidateIndex]
                let breakdown = substitutionBreakdown(
                    sourceWord,
                    candidateWord,
                    configuration: configuration
                )
                operations.append(
                    WordAlignmentOperation(
                        kind: normalizedLexicalToken(sourceWord.text)
                            == normalizedLexicalToken(candidateWord.text)
                            ? .match
                            : .substitution,
                        sourceIndex: resolvedSourceIndex,
                        candidateIndex: resolvedCandidateIndex,
                        sourceWord: sourceWord,
                        candidateWord: candidateWord,
                        timeOverlap: timeOverlap(sourceWord, candidateWord),
                        score: breakdown
                    )
                )
                sourceIndex -= 1
                candidateIndex -= 1
            case .deletion:
                let resolvedSourceIndex = sourceIndex - 1
                let sourceWord = source[resolvedSourceIndex]
                let breakdown = deletionBreakdown(sourceWord, configuration: configuration)
                operations.append(
                    WordAlignmentOperation(
                        kind: .deletion,
                        sourceIndex: resolvedSourceIndex,
                        candidateIndex: nil,
                        sourceWord: sourceWord,
                        candidateWord: nil,
                        timeOverlap: nil,
                        score: breakdown
                    )
                )
                sourceIndex -= 1
            case .insertion:
                let resolvedCandidateIndex = candidateIndex - 1
                let candidateWord = candidate[resolvedCandidateIndex]
                let breakdown = insertionBreakdown(candidateWord, configuration: configuration)
                operations.append(
                    WordAlignmentOperation(
                        kind: .insertion,
                        sourceIndex: nil,
                        candidateIndex: resolvedCandidateIndex,
                        sourceWord: nil,
                        candidateWord: candidateWord,
                        timeOverlap: nil,
                        score: breakdown
                    )
                )
                candidateIndex -= 1
            case .origin:
                // A malformed backtrace should never be silently converted
                // to text.  The bounded DP has a valid path for every cell;
                // stop defensively if an unexpected value is encountered.
                sourceIndex = 0
                candidateIndex = 0
            }
        }

        operations.reverse()
        let totalScore: Double
        if sourceCount == 0 {
            totalScore = previous[candidateCount]
        } else {
            totalScore = previous[candidateCount]
        }
        return WordAlignmentResult(
            operations: operations,
            totalScore: totalScore,
            sourceWordCount: sourceCount,
            candidateWordCount: candidateCount
        )
    }

    /// Non-throwing convenience for callers that want to fail closed when a
    /// requested span exceeds the explicit lattice bound.
    public static func alignIfBounded(
        source: [RecognizedWord],
        candidate: [RecognizedWord],
        configuration: WordAlignmentConfiguration = .default
    ) -> WordAlignmentResult? {
        try? align(source: source, candidate: candidate, configuration: configuration)
    }

    /// Stable lexical comparison used by both alignment and fusion.  It
    /// removes punctuation/case only for comparison; input word text is
    /// never rewritten by this helper.
    public static func normalizedLexicalToken(_ text: String) -> String {
        let lowered = text.lowercased()
        let scalars = lowered.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    public static func lexicalDistance(_ lhs: String, _ rhs: String) -> Double {
        let left = Array(normalizedLexicalToken(lhs).prefix(128))
        let right = Array(normalizedLexicalToken(rhs).prefix(128))
        if left.isEmpty && right.isEmpty { return 0 }
        if left.isEmpty || right.isEmpty { return 1 }
        var previous = Array(0...right.count)
        var current = Array(repeating: 0, count: right.count + 1)
        for leftIndex in 1...left.count {
            current[0] = leftIndex
            if right.count > 0 {
                for rightIndex in 1...right.count {
                    let substitution = previous[rightIndex - 1]
                        + (left[leftIndex - 1] == right[rightIndex - 1] ? 0 : 1)
                    let deletion = previous[rightIndex] + 1
                    let insertion = current[rightIndex - 1] + 1
                    current[rightIndex] = min(substitution, min(deletion, insertion))
                }
            }
            swap(&previous, &current)
        }
        return min(1, Double(previous[right.count]) / Double(max(left.count, right.count)))
    }

    public static func timeOverlap(
        _ source: RecognizedWord,
        _ candidate: RecognizedWord
    ) -> Double? {
        guard let sourceStart = source.startSeconds,
              let sourceEnd = source.endSeconds,
              let candidateStart = candidate.startSeconds,
              let candidateEnd = candidate.endSeconds
        else {
            return nil
        }
        let intersection = max(0, min(sourceEnd, candidateEnd) - max(sourceStart, candidateStart))
        let union = max(sourceEnd, candidateEnd) - min(sourceStart, candidateStart)
        guard union > 0 else {
            return sourceStart == candidateStart ? 1 : 0
        }
        return min(1, max(0, intersection / union))
    }

    private enum BacktraceStep: UInt8 {
        case origin = 0
        case diagonal = 1
        case deletion = 2
        case insertion = 3
    }

    private struct SelectedStep {
        let score: Double
        let step: BacktraceStep
    }

    private static func selectMinimum(
        diagonal: Double,
        deletion: Double,
        insertion: Double
    ) -> SelectedStep {
        // Strictly less comparisons make ties deterministic and prefer the
        // diagonal, then deletion, then insertion path.
        if diagonal <= deletion && diagonal <= insertion {
            return SelectedStep(score: diagonal, step: .diagonal)
        }
        if deletion <= insertion {
            return SelectedStep(score: deletion, step: .deletion)
        }
        return SelectedStep(score: insertion, step: .insertion)
    }

    private static func substitutionBreakdown(
        _ source: RecognizedWord,
        _ candidate: RecognizedWord,
        configuration: WordAlignmentConfiguration
    ) -> WordAlignmentScoreBreakdown {
        let lexical = lexicalDistance(source.text, candidate.text)
        let overlap = timeOverlap(source, candidate)
        let timePenalty = overlap.map { 1 - $0 } ?? 0
        let confidence = confidencePenalty(source, candidate)
        let effectiveConfidence = confidence ?? configuration.missingConfidencePenalty
        let anchorPenalty: Double
        if source.lockState == .locked || source.lockState == .protected {
            anchorPenalty = lexical == 0 ? 0 : configuration.lockedAnchorPenalty
        } else {
            anchorPenalty = 0
        }
        let baseCost = lexical == 0 ? 0 : configuration.substitutionBaseCost
        let total = baseCost
            + lexical
            + configuration.timeOverlapWeight * timePenalty
            + configuration.confidenceWeight * effectiveConfidence
            + anchorPenalty
        return WordAlignmentScoreBreakdown(
            lexicalDistance: lexical,
            timeOverlapPenalty: timePenalty,
            confidencePenalty: confidence,
            gapPenalty: 0,
            anchorPenalty: anchorPenalty,
            total: total
        )
    }

    private static func insertionBreakdown(
        _ candidate: RecognizedWord,
        configuration: WordAlignmentConfiguration
    ) -> WordAlignmentScoreBreakdown {
        let confidence = wordSupport(of: candidate).map { 1 - $0 }
        let effectiveConfidence = confidence ?? configuration.missingConfidencePenalty
        let duration = min(1, max(0, candidate.durationSeconds ?? 0))
        let gapPenalty = configuration.gapDurationWeight * duration
        let total = configuration.insertionBaseCost
            + configuration.confidenceWeight * effectiveConfidence
            + gapPenalty
        return WordAlignmentScoreBreakdown(
            lexicalDistance: 0,
            timeOverlapPenalty: 0,
            confidencePenalty: confidence,
            gapPenalty: gapPenalty,
            anchorPenalty: 0,
            total: total
        )
    }

    private static func deletionBreakdown(
        _ source: RecognizedWord,
        configuration: WordAlignmentConfiguration
    ) -> WordAlignmentScoreBreakdown {
        let confidence = wordSupport(of: source).map { 1 - $0 }
        let effectiveConfidence = confidence ?? configuration.missingConfidencePenalty
        let duration = min(1, max(0, source.durationSeconds ?? 0))
        let gapPenalty = configuration.gapDurationWeight * duration
        let anchorPenalty: Double =
            source.lockState == .locked || source.lockState == .protected
                ? configuration.lockedAnchorPenalty
                : 0
        let total = configuration.deletionBaseCost
            + configuration.confidenceWeight * effectiveConfidence
            + gapPenalty
            + anchorPenalty
        return WordAlignmentScoreBreakdown(
            lexicalDistance: 0,
            timeOverlapPenalty: 0,
            confidencePenalty: confidence,
            gapPenalty: gapPenalty,
            anchorPenalty: anchorPenalty,
            total: total
        )
    }

    private static func confidencePenalty(
        _ source: RecognizedWord,
        _ candidate: RecognizedWord
    ) -> Double? {
        guard let sourceSupport = wordSupport(of: source),
              let candidateSupport = wordSupport(of: candidate)
        else {
            return nil
        }
        return min(1, max(0, ((1 - sourceSupport) + (1 - candidateSupport)) / 2))
    }

    private static func wordSupport(of word: RecognizedWord) -> Double? {
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
}

/// Alternate names used by pipeline code and focused tests.
public typealias TimestampAwareWordAligner = WordAlignment
public typealias TimestampAwareAlignment = WordAlignmentResult
public typealias AlignmentOperation = WordAlignmentOperation
public typealias AlignmentScoreBreakdown = WordAlignmentScoreBreakdown
