import Foundation

public enum WhisperHotkeyPreferenceKeys {
    public static let dictationModel = "dictationModel"
    public static let keepModelReady = "keepModelReady"
    public static let dictationMode = "dictationMode"
    public static let recordingLimit = "recordingLimit"
    public static let badgeTheme = "badgeTheme"
}

public enum WhisperModelReadinessPreference {
    public static func keepsModelReady(
        defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.bool(forKey: WhisperHotkeyPreferenceKeys.keepModelReady)
    }
}

public enum BadgeTheme: String, CaseIterable, Codable, Sendable {
    case githubDarkDimmed
    case midnightIndigo
    case graphite
    case nord
    case dracula
    case solarizedDark
    case forest
    case ocean
    case rosePine
    case lightFrost
    case highContrast

    public static let defaultTheme: Self = .githubDarkDimmed

    public var displayName: String {
        switch self {
        case .githubDarkDimmed: "GitHub Dark Dimmed"
        case .midnightIndigo: "Midnight Indigo"
        case .graphite: "Graphite"
        case .nord: "Nord"
        case .dracula: "Dracula"
        case .solarizedDark: "Solarized Dark"
        case .forest: "Forest"
        case .ocean: "Ocean"
        case .rosePine: "Rosé Pine"
        case .lightFrost: "Light Frost"
        case .highContrast: "High Contrast"
        }
    }

    public var summaryName: String {
        switch self {
        case .githubDarkDimmed: "Dimmed"
        case .midnightIndigo: "Indigo"
        case .graphite: "Graphite"
        case .nord: "Nord"
        case .dracula: "Dracula"
        case .solarizedDark: "Solarized"
        case .forest: "Forest"
        case .ocean: "Ocean"
        case .rosePine: "Rosé Pine"
        case .lightFrost: "Frost"
        case .highContrast: "Contrast"
        }
    }

    public static func selected(
        defaults: UserDefaults = .standard
    ) -> Self {
        guard let rawValue = defaults.string(
            forKey: WhisperHotkeyPreferenceKeys.badgeTheme
        ) else {
            return .defaultTheme
        }
        return Self(rawValue: rawValue) ?? .defaultTheme
    }
}

public enum DictationModel: String, CaseIterable, Codable, Sendable {
    case baseEnglish
    case smallEnglish
    case mediumEnglish
    case largeV3TurboQ5

    public static let defaultModel: Self = .baseEnglish

    public var displayName: String {
        switch self {
        case .baseEnglish:
            "Base English"
        case .smallEnglish:
            "Small English"
        case .mediumEnglish:
            "Medium English"
        case .largeV3TurboQ5:
            "Large-v3 Turbo Q5"
        }
    }

    public var menuTitle: String {
        switch self {
        case .baseEnglish:
            "Base English (Fast, 141 MB)"
        case .smallEnglish:
            "Small English (More Accurate, 465 MB)"
        case .mediumEnglish:
            "Medium English (High Accuracy, 1.5 GB)"
        case .largeV3TurboQ5:
            "Large-v3 Turbo Q5 (Best Balance, 547 MB)"
        }
    }

    public var fileName: String {
        switch self {
        case .baseEnglish:
            "ggml-base.en.bin"
        case .smallEnglish:
            "ggml-small.en.bin"
        case .mediumEnglish:
            "ggml-medium.en.bin"
        case .largeV3TurboQ5:
            "ggml-large-v3-turbo-q5_0.bin"
        }
    }

    public static func selected(
        defaults: UserDefaults = .standard
    ) -> Self {
        guard let rawValue = defaults.string(
            forKey: WhisperHotkeyPreferenceKeys.dictationModel
        ) else {
            return .defaultModel
        }
        return Self(rawValue: rawValue) ?? .defaultModel
    }
}

public enum RecordingLimit: String, CaseIterable, Codable, Sendable {
    case seconds30
    case minute1
    case minutes2
    case minutes5
    case minutes10
    case minutes15
    case minutes30
    case hour1

    public static let defaultLimit: Self = .minutes10

    public var seconds: Int {
        switch self {
        case .seconds30:
            30
        case .minute1:
            60
        case .minutes2:
            120
        case .minutes5:
            300
        case .minutes10:
            600
        case .minutes15:
            900
        case .minutes30:
            1_800
        case .hour1:
            3_600
        }
    }

    public var displayName: String {
        switch self {
        case .seconds30:
            "30 Seconds"
        case .minute1:
            "1 Minute"
        case .minutes2:
            "2 Minutes"
        case .minutes5:
            "5 Minutes"
        case .minutes10:
            "10 Minutes"
        case .minutes15:
            "15 Minutes"
        case .minutes30:
            "30 Minutes"
        case .hour1:
            "1 Hour"
        }
    }

    public static func selected(
        defaults: UserDefaults = .standard
    ) -> Self {
        guard let rawValue = defaults.string(
            forKey: WhisperHotkeyPreferenceKeys.recordingLimit
        ) else {
            return .defaultLimit
        }
        return Self(rawValue: rawValue) ?? .defaultLimit
    }
}
