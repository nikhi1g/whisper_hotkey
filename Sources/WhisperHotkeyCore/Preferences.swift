import Foundation

public enum WhisperHotkeyPreferenceKeys {
    public static let dictationModel = "dictationModel"
    public static let recognitionEngine = "recognitionEngine"
    public static let decodingProfile = "decodingProfile"
    public static let modelProcessingMode = "modelProcessingMode"
    public static let keepModelReady = "keepModelReady"
    public static let internalDictionary = "internalDictionary"
    public static let dictationMode = "dictationMode"
    public static let recordingLimit = "recordingLimit"
    public static let badgeTheme = "badgeTheme"
    public static let customBadgeThemes = "customBadgeThemes"
    public static let keepLatestDictation = "keepLatestDictation"
}

public enum LastDictationRetentionPreference {
    public static let defaultValue = true

    public static func isEnabled(
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard defaults.object(
            forKey: WhisperHotkeyPreferenceKeys.keepLatestDictation
        ) != nil else {
            return defaultValue
        }
        return defaults.bool(
            forKey: WhisperHotkeyPreferenceKeys.keepLatestDictation
        )
    }

    public static func setEnabled(
        _ enabled: Bool,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(
            enabled,
            forKey: WhisperHotkeyPreferenceKeys.keepLatestDictation
        )
    }
}

public enum DecodingProfile: String, CaseIterable, Codable, Sendable {
    case precision
    case adaptive

    public static let defaultProfile: Self = .precision

    public var displayName: String {
        switch self {
        case .precision:
            "Precision"
        case .adaptive:
            "Smart Decode"
        }
    }

    public var description: String {
        switch self {
        case .precision:
            "Always uses five-beam decoding for consistent accuracy."
        case .adaptive:
            "Accepts a confident fast pass and retries uncertain speech with five-beam decoding."
        }
    }

    public static func selected(
        defaults: UserDefaults = .standard
    ) -> Self {
        guard let rawValue = defaults.string(
            forKey: WhisperHotkeyPreferenceKeys.decodingProfile
        ) else {
            return .defaultProfile
        }
        return Self(rawValue: rawValue) ?? .defaultProfile
    }
}

/// User-supplied words and phrases that bias local Whisper decoding.
///
/// Entries are persisted as an array so phrases retain their spaces and case.
/// The generated prompt is deliberately bounded to keep its recognition cost
/// effectively constant even if preferences are edited outside the app.
public struct InternalDictionary: Equatable, Sendable {
    public static let maximumEntries = 64
    public static let maximumEntryCharacters = 80
    public static let maximumPromptCharacters = 320

    public let entries: [String]
    public let prompt: String?

    public init(entries: [String]) {
        let normalized = Self.normalized(entries)
        self.entries = normalized
        self.prompt = Self.makePrompt(from: normalized)
    }

    public static func selected(
        defaults: UserDefaults = .standard
    ) -> Self {
        Self(
            entries: defaults.stringArray(
                forKey: WhisperHotkeyPreferenceKeys.internalDictionary
            ) ?? []
        )
    }

    public func persist(defaults: UserDefaults = .standard) {
        defaults.set(
            entries,
            forKey: WhisperHotkeyPreferenceKeys.internalDictionary
        )
    }

    private static func normalized(_ entries: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        var promptCharacterCount = 0
        result.reserveCapacity(min(entries.count, maximumEntries))

        for rawEntry in entries {
            let entry = rawEntry
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(maximumEntryCharacters)
            guard !entry.isEmpty else {
                continue
            }
            let value = String(entry)
            let identity = value.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            guard seen.insert(identity).inserted else {
                continue
            }
            let separatorCount = result.isEmpty ? 0 : 2
            guard promptCharacterCount + separatorCount + value.count
                    <= maximumPromptCharacters
            else {
                continue
            }
            result.append(value)
            promptCharacterCount += separatorCount + value.count
            if result.count == maximumEntries {
                break
            }
        }
        return result
    }

    private static func makePrompt(from entries: [String]) -> String? {
        guard !entries.isEmpty else {
            return nil
        }

        var included: [String] = []
        var characterCount = 0
        for entry in entries {
            let separatorCount = included.isEmpty ? 0 : 2
            guard characterCount + separatorCount + entry.count
                    <= maximumPromptCharacters
            else {
                break
            }
            included.append(entry)
            characterCount += separatorCount + entry.count
        }
        return included.isEmpty ? nil : included.joined(separator: ", ")
    }
}

public enum RecognitionEngine: String, CaseIterable, Codable, Sendable {
    case whisperCppMetal
    case whisperCppCoreML
    case whisperKitCoreML

    public static let defaultEngine: Self = .whisperCppMetal

    public var displayName: String {
        switch self {
        case .whisperCppMetal:
            "Metal"
        case .whisperCppCoreML:
            "Core ML Encoder"
        case .whisperKitCoreML:
            "WhisperKit"
        }
    }

    public var menuTitle: String {
        switch self {
        case .whisperCppMetal:
            "whisper.cpp Metal (Current)"
        case .whisperCppCoreML:
            "whisper.cpp Core ML Encoder"
        case .whisperKitCoreML:
            "WhisperKit Core ML and Neural Engine"
        }
    }

    public static func selected(
        defaults: UserDefaults = .standard
    ) -> Self {
        guard let rawValue = defaults.string(
            forKey: WhisperHotkeyPreferenceKeys.recognitionEngine
        ) else {
            return .defaultEngine
        }
        return Self(rawValue: rawValue) ?? .defaultEngine
    }
}

public enum ModelProcessingMode: String, CaseIterable, Codable, Sendable {
    case afterRecording
    case modelReady
    case decodeWhileSpeaking

    public static let defaultMode: Self = .afterRecording

    public var displayName: String {
        switch self {
        case .afterRecording:
            "After Recording"
        case .modelReady:
            "Model Ready"
        case .decodeWhileSpeaking:
            "Decode While Speaking"
        }
    }

    public var description: String {
        switch self {
        case .afterRecording:
            "Loads and decodes after recording for full-context accuracy and the lowest idle memory."
        case .modelReady:
            "Keeps the selected model loaded for full-context decoding without model startup."
        case .decodeWhileSpeaking:
            "Privately decodes long chunks while you speak for the shortest finish time, with slightly less cross-chunk context."
        }
    }

    public var keepsModelReady: Bool {
        self != .afterRecording
    }

    public var decodesWhileSpeaking: Bool {
        self == .decodeWhileSpeaking
    }

    public static func selected(
        defaults: UserDefaults = .standard
    ) -> Self {
        if let rawValue = defaults.string(
            forKey: WhisperHotkeyPreferenceKeys.modelProcessingMode
        ), let mode = Self(rawValue: rawValue) {
            return mode
        }
        return defaults.bool(
            forKey: WhisperHotkeyPreferenceKeys.keepModelReady
        ) ? .modelReady : .defaultMode
    }

    public func persist(defaults: UserDefaults = .standard) {
        defaults.set(
            rawValue,
            forKey: WhisperHotkeyPreferenceKeys.modelProcessingMode
        )
        // Preserve downgrade compatibility with the former two-state switch.
        defaults.set(
            keepsModelReady,
            forKey: WhisperHotkeyPreferenceKeys.keepModelReady
        )
    }
}

public enum BadgeThemeMode: String, CaseIterable, Codable, Sendable {
    case dark
    case light

    public var displayName: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        }
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
    case highContrast
    case tokyoNight
    case catppuccinMocha
    case gruvboxDark
    case monokai
    case lightFrost
    case githubLight
    case solarizedLight
    case nordSnow
    case rosePineDawn
    case paper
    case mint
    case sky
    case lavender
    case highContrastLight

    public static let defaultTheme: Self = .githubDarkDimmed

    public var mode: BadgeThemeMode {
        switch self {
        case .lightFrost, .githubLight, .solarizedLight, .nordSnow,
             .rosePineDawn, .paper, .mint, .sky, .lavender,
             .highContrastLight:
            .light
        default:
            .dark
        }
    }

    public var isLight: Bool {
        mode == .light
    }

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
        case .highContrast: "High Contrast"
        case .tokyoNight: "Tokyo Night"
        case .catppuccinMocha: "Catppuccin Mocha"
        case .gruvboxDark: "Gruvbox Dark"
        case .monokai: "Monokai"
        case .lightFrost: "Light Frost"
        case .githubLight: "GitHub Light"
        case .solarizedLight: "Solarized Light"
        case .nordSnow: "Nord Snow"
        case .rosePineDawn: "Rosé Pine Dawn"
        case .paper: "Paper"
        case .mint: "Mint"
        case .sky: "Sky"
        case .lavender: "Lavender"
        case .highContrastLight: "High Contrast Light"
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
        case .highContrast: "Contrast"
        case .tokyoNight: "Tokyo"
        case .catppuccinMocha: "Mocha"
        case .gruvboxDark: "Gruvbox"
        case .monokai: "Monokai"
        case .lightFrost: "Frost"
        case .githubLight: "GitHub Light"
        case .solarizedLight: "Solarized Light"
        case .nordSnow: "Nord Snow"
        case .rosePineDawn: "Rosé Dawn"
        case .paper: "Paper"
        case .mint: "Mint"
        case .sky: "Sky"
        case .lavender: "Lavender"
        case .highContrastLight: "Light Contrast"
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

public struct CustomBadgeTheme: Codable, Equatable, Identifiable, Sendable {
    public static let maximumCount = 32
    public static let maximumNameLength = 40

    public let id: UUID
    public let name: String
    public let mode: BadgeThemeMode
    public let backgroundHex: String
    public let textHex: String
    public let accentHex: String

    public init?(
        id: UUID = UUID(),
        name: String,
        mode: BadgeThemeMode,
        backgroundHex: String,
        textHex: String,
        accentHex: String
    ) {
        let normalizedName = String(
            name.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(Self.maximumNameLength)
        )
        guard !normalizedName.isEmpty,
              let background = Self.normalizeHex(backgroundHex),
              let text = Self.normalizeHex(textHex),
              let accent = Self.normalizeHex(accentHex)
        else {
            return nil
        }
        self.id = id
        self.name = normalizedName
        self.mode = mode
        self.backgroundHex = background
        self.textHex = text
        self.accentHex = accent
    }

    public static func normalizeHex(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard digits.count == 6,
              digits.allSatisfy(\.isHexDigit)
        else {
            return nil
        }
        return "#\(digits.uppercased())"
    }

    public static func load(
        defaults: UserDefaults = .standard
    ) -> [Self] {
        guard let data = defaults.data(
            forKey: WhisperHotkeyPreferenceKeys.customBadgeThemes
        ), let decoded = try? JSONDecoder().decode([Self].self, from: data)
        else {
            return []
        }
        var seen = Set<UUID>()
        return decoded.prefix(maximumCount).compactMap { theme in
            guard seen.insert(theme.id).inserted else {
                return nil
            }
            return Self(
                id: theme.id,
                name: theme.name,
                mode: theme.mode,
                backgroundHex: theme.backgroundHex,
                textHex: theme.textHex,
                accentHex: theme.accentHex
            )
        }
    }

    public static func persist(
        _ themes: [Self],
        defaults: UserDefaults = .standard
    ) {
        let bounded = Array(themes.prefix(maximumCount))
        guard let data = try? JSONEncoder().encode(bounded) else {
            return
        }
        defaults.set(
            data,
            forKey: WhisperHotkeyPreferenceKeys.customBadgeThemes
        )
    }
}

public enum BadgeThemeSelection: Equatable, Sendable {
    case builtIn(BadgeTheme)
    case custom(CustomBadgeTheme)

    public static let defaultSelection: Self = .builtIn(.defaultTheme)

    public var identifier: String {
        switch self {
        case .builtIn(let theme):
            theme.rawValue
        case .custom(let theme):
            "custom:\(theme.id.uuidString.lowercased())"
        }
    }

    public var displayName: String {
        switch self {
        case .builtIn(let theme): theme.displayName
        case .custom(let theme): theme.name
        }
    }

    public var summaryName: String {
        switch self {
        case .builtIn(let theme): theme.summaryName
        case .custom(let theme): theme.name
        }
    }

    public var mode: BadgeThemeMode {
        switch self {
        case .builtIn(let theme): theme.mode
        case .custom(let theme): theme.mode
        }
    }

    public var customTheme: CustomBadgeTheme? {
        guard case .custom(let theme) = self else {
            return nil
        }
        return theme
    }

    public static func selected(
        defaults: UserDefaults = .standard,
        customThemes: [CustomBadgeTheme]? = nil
    ) -> Self {
        let value = defaults.string(
            forKey: WhisperHotkeyPreferenceKeys.badgeTheme
        )
        if let value, let builtIn = BadgeTheme(rawValue: value) {
            return .builtIn(builtIn)
        }
        let themes = customThemes ?? CustomBadgeTheme.load(defaults: defaults)
        if let value,
           value.hasPrefix("custom:"),
           let id = UUID(uuidString: String(value.dropFirst("custom:".count))),
           let custom = themes.first(where: { $0.id == id })
        {
            return .custom(custom)
        }
        return .defaultSelection
    }

    public func persist(defaults: UserDefaults = .standard) {
        defaults.set(
            identifier,
            forKey: WhisperHotkeyPreferenceKeys.badgeTheme
        )
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

    public var whisperKitFolderName: String {
        switch self {
        case .baseEnglish:
            "openai_whisper-base.en"
        case .smallEnglish:
            "openai_whisper-small.en"
        case .mediumEnglish:
            "openai_whisper-medium.en"
        case .largeV3TurboQ5:
            "openai_whisper-large-v3-v20240930_626MB"
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
