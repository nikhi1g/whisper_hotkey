import Foundation

public struct LastDictationBuffer: Equatable, Sendable {
    public private(set) var isEnabled: Bool
    public private(set) var transcript: String?

    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    public mutating func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            transcript = nil
        }
    }

    public mutating func retainSuccessful(_ value: String) {
        guard isEnabled else {
            transcript = nil
            return
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            transcript = trimmed
        }
    }
}
