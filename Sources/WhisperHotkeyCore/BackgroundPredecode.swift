import Foundation

public enum BackgroundPredecodePolicy {
    public static let minimumSegmentDuration: TimeInterval = 5
    public static let preferredBoundarySilence: TimeInterval = 0.3
    public static let maximumSegmentDuration: TimeInterval = 8

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

public struct PredecodedTranscriptAccumulator: Equatable, Sendable {
    public private(set) var chunks: [String] = []

    public init() {}

    public var transcript: String {
        chunks.joined(separator: " ")
    }

    public mutating func append(_ transcript: String) {
        let normalized = transcript.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalized.isEmpty else {
            return
        }
        chunks.append(normalized)
    }

    public mutating func reset() {
        chunks.removeAll(keepingCapacity: true)
    }
}
