import Foundation

public protocol TranscriptFormatter: Sendable {
    func format(_ transcript: String) async -> String
}

public struct DeterministicTranscriptFormatter: TranscriptFormatter {
    public init() {}

    public func format(_ transcript: String) async -> String {
        return transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
