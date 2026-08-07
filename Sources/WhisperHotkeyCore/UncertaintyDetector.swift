import Foundation

public struct UncertaintyAssessment: Equatable, Sendable {
    public let reasons: [String]
    public let score: Double

    public init(reasons: [String], score: Double) {
        self.reasons = reasons
        self.score = score
    }

    public var isUncertain: Bool {
        !reasons.isEmpty
    }
}

public struct UncertainSpanSelection: Equatable, Sendable {
    public let span: UncertainSpan
    public let reason: String

    public init(span: UncertainSpan, reason: String) {
        self.span = span
        self.reason = reason
    }
}

public enum UncertaintyBudget {
    public static func merged(_ spans: [UncertainSpan], maximumGapSamples: Int64) -> [UncertainSpan] {
        precondition(maximumGapSamples >= 0)
        let ordered = spans.sorted {
            if $0.startSample != $1.startSample {
                return $0.startSample < $1.startSample
            }
            if $0.endSample != $1.endSample {
                return $0.endSample < $1.endSample
            }
            return $0.score > $1.score
        }

        guard var current = ordered.first else { return [] }
        var merged: [UncertainSpan] = []
        for span in ordered.dropFirst() {
            if span.startSample <= current.endSample + maximumGapSamples {
                current = UncertainSpan(
                    startSample: current.startSample,
                    endSample: max(current.endSample, span.endSample),
                    sampleRate: current.sampleRate,
                    score: max(current.score, span.score)
                )
            } else {
                merged.append(current)
                current = span
            }
        }
        merged.append(current)
        return merged
    }

    public static func selected(
        _ spans: [UncertainSpan],
        maximumTotalSamples: Int64
    ) -> [UncertainSpan] {
        precondition(maximumTotalSamples >= 0)
        var remaining = maximumTotalSamples
        var selected: [UncertainSpan] = []
        let ranked = spans.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if ($0.endSample - $0.startSample) != ($1.endSample - $1.startSample) {
                return ($0.endSample - $0.startSample) < ($1.endSample - $1.startSample)
            }
            return $0.startSample < $1.startSample
        }

        for span in ranked where remaining > 0 {
            let spanLength = span.endSample - span.startSample
            if spanLength <= remaining {
                selected.append(span)
                remaining -= spanLength
            }
        }

        return selected.sorted { $0.startSample < $1.startSample }
    }
}

public enum UncertaintyDetector {
    public static func assess(
        hypothesis: RecognitionHypothesis,
        policy: AccuracyPolicy = .defaultPolicy
    ) -> UncertaintyAssessment {
        var reasons: [String] = []
        var score: Double = 0.0

        if hypothesis.adaptiveFallback {
            reasons.append("adaptive fallback was already performed")
            return .init(reasons: reasons, score: 1.0)
        }

        if let average = hypothesis.averageLogProbability {
            let confidence = (average - policy.minimumAverageLogProbability) / 2.0
            score = max(0.0, min(1.0, 1.0 - confidence))
            if average < policy.minimumAverageLogProbability {
                reasons.append(
                    String(
                        format:
                            "averageLogProbability(%.3f) < %.3f",
                        average,
                        policy.minimumAverageLogProbability
                    )
                )
            }
        } else if policy.missingMetadataPenalty > 0 {
            score = max(score, policy.missingMetadataPenalty)
            reasons.append(
                "averageLogProbability missing: requires full metadata"
            )
        }

        if let noSpeech = hypothesis.noSpeechProbability {
            if noSpeech > policy.maximumNoSpeechProbability {
                reasons.append(
                    String(
                        format:
                            "noSpeechProbability(%.3f) > %.3f",
                        noSpeech,
                        policy.maximumNoSpeechProbability
                    )
                )
                score = max(score, 1.0)
            }
        } else if policy.missingMetadataPenalty > 0 {
            score = max(score, policy.missingMetadataPenalty)
        }

        if let weak = hypothesis.weakTokenFraction {
            if weak > policy.maximumWeakTokenFraction {
                reasons.append(
                    String(
                        format:
                            "weakTokenFraction(%.3f) > %.3f",
                        weak,
                        policy.maximumWeakTokenFraction
                    )
                )
                score = max(score, 1.0)
            }
        } else if policy.missingMetadataPenalty > 0 {
            score = max(score, policy.missingMetadataPenalty)
        }

        if policy.repeatPenaltyEnabled && hypothesis.repetitionDetected {
            reasons.append("repeated phrase detected")
            score = max(score, 1.0)
        }

        if reasons.isEmpty {
            return .init(reasons: [], score: 0.0)
        }

        if score <= 0 {
            score = 1.0
        }
        return .init(reasons: reasons, score: min(1.0, score))
    }

    public static func isUncertain(
        _ hypothesis: RecognitionHypothesis,
        policy: AccuracyPolicy = .defaultPolicy
    ) -> Bool {
        assess(hypothesis: hypothesis, policy: policy).isUncertain
    }
}
