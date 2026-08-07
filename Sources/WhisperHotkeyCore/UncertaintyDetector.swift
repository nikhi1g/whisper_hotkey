import Foundation

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
