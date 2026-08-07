import Foundation

public struct WeightedCandidate: Hashable, Sendable {
    public let hypothesis: RecognitionHypothesis
    public let reliabilityWeight: Double

    public init(hypothesis: RecognitionHypothesis, reliabilityWeight: Double = 1.0) {
        precondition(reliabilityWeight > 0)
        self.hypothesis = hypothesis
        self.reliabilityWeight = reliabilityWeight
    }
}

public struct CandidateSelectionResult: Hashable, Sendable {
    public let hypothesis: RecognitionHypothesis
    public let normalizedRisk: Double

    public init(hypothesis: RecognitionHypothesis, normalizedRisk: Double) {
        self.hypothesis = hypothesis
        self.normalizedRisk = normalizedRisk
    }
}

public enum CandidateSelector {
    public static func weightedMedoid(
        _ candidates: [WeightedCandidate]
    ) -> CandidateSelectionResult? {
        guard !candidates.isEmpty else { return nil }

        let tokenized = candidates.map {
            TranscriptAlignment.lexicalTokens(from: $0.hypothesis.text)
        }

        var bestIndex = 0
        var bestRisk = Double.greatestFiniteMagnitude
        for i in candidates.indices {
            var risk = 0.0
            var weightTotal = 0.0
            for j in candidates.indices where i != j {
                let denominator = max(1, tokenized[j].count)
                let distance = WordAlignment.distance(tokenized[i], tokenized[j])
                let normalized = Double(distance) / Double(denominator)
                risk += normalized * candidates[j].reliabilityWeight
                weightTotal += candidates[j].reliabilityWeight
            }
            let normalizedRisk = weightTotal > 0 ? risk / weightTotal : 0
            if normalizedRisk < bestRisk {
                bestRisk = normalizedRisk
                bestIndex = i
            }
        }
        return CandidateSelectionResult(
            hypothesis: candidates[bestIndex].hypothesis,
            normalizedRisk: bestRisk
        )
    }

    public static func stablePick(
        _ candidates: [WeightedCandidate],
        fallbackToLatest: Bool = true
    ) -> CandidateSelectionResult? {
        guard let result = weightedMedoid(candidates) else { return nil }
        if fallbackToLatest, let latest = candidates.last {
            return CandidateSelectionResult(
                hypothesis: latest.hypothesis,
                normalizedRisk: 0.0
            )
        }
        return result
    }
}
