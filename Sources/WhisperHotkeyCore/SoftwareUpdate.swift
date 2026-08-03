import Foundation

public struct SemanticVersion: Comparable, Equatable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(_ rawValue: String) {
        var normalized = rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if normalized.lowercased().hasPrefix("v") {
            normalized.removeFirst()
        }
        normalized = String(normalized.split(separator: "-", maxSplits: 1)[0])
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) })
        else {
            return nil
        }
        let values = parts.compactMap { Int($0) }
        guard values.count == parts.count else {
            return nil
        }
        major = values[0]
        minor = values.count > 1 ? values[1] : 0
        patch = values.count > 2 ? values[2] : 0
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) <
            (rhs.major, rhs.minor, rhs.patch)
    }
}

public enum AutomaticUpdateCheckPreference {
    public static let defaultValue = false

    public static func isEnabled(
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard defaults.object(
            forKey: WhisperHotkeyPreferenceKeys.automaticallyChecksForUpdates
        ) != nil else {
            return defaultValue
        }
        return defaults.bool(
            forKey: WhisperHotkeyPreferenceKeys.automaticallyChecksForUpdates
        )
    }

    public static func setEnabled(
        _ enabled: Bool,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(
            enabled,
            forKey: WhisperHotkeyPreferenceKeys.automaticallyChecksForUpdates
        )
    }
}
