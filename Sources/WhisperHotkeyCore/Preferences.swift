import Foundation

public enum WhisperHotkeyPreferenceKeys {
    public static let dictationModel = "dictationModel"
    /// Parakeet ships its own checkpoints, so it keeps its own selection rather
    /// than borrowing a whisper model slot. Switching engines then never
    /// overwrites the other engine's choice.
    public static let parakeetModel = "parakeetModel"
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
    public static let automaticallyChecksForUpdates =
        "automaticallyChecksForUpdates"
    public static let firstRunDefaultsVersion = "firstRunDefaultsVersion"
    public static let hasPresentedFirstRunSettings =
        "hasPresentedFirstRunSettings"
}

public struct FirstRunPerformanceProfile: Equatable, Sendable {
    public static let responsiveMemoryThreshold: UInt64 = 8 * 1_024 * 1_024 * 1_024
    public static let highQualityMemoryThreshold: UInt64 = 16 * 1_024 * 1_024 * 1_024

    public let model: DictationModel
    public let engine: RecognitionEngine
    public let decodingProfile: DecodingProfile
    public let processingMode: ModelProcessingMode

    public static func recommended(
        physicalMemory: UInt64,
        availableModels: Set<DictationModel>
    ) -> Self {
        let preferredModels: [DictationModel]
        if physicalMemory >= responsiveMemoryThreshold {
            preferredModels = [.largeV3TurboQ5, .baseEnglish]
        } else {
            preferredModels = [.baseEnglish]
        }
        let model = preferredModels.first(where: availableModels.contains)
            ?? DictationModel.allCases.first(where: availableModels.contains)
            ?? .baseEnglish
        let processingMode: ModelProcessingMode =
            physicalMemory >= responsiveMemoryThreshold
                ? .decodeWhileSpeaking
                : .afterRecording
        return Self(
            model: model,
            engine: .whisperCppMetal,
            decodingProfile: .precision,
            processingMode: processingMode
        )
    }
}

public enum FirstRunPreferenceBootstrap {
    public static func applyIfNeeded(
        defaults: UserDefaults = .standard,
        bundleIdentifier: String = WhisperHotkeyPaths.bundleIdentifier,
        version: Int,
        apply: () -> Void
    ) {
        guard defaults.object(
            forKey: WhisperHotkeyPreferenceKeys.firstRunDefaultsVersion
        ) == nil else {
            return
        }
        let existingDomain = defaults.persistentDomain(
            forName: bundleIdentifier
        ) ?? [:]
        if existingDomain.isEmpty {
            apply()
        }
        defaults.set(
            version,
            forKey: WhisperHotkeyPreferenceKeys.firstRunDefaultsVersion
        )
    }
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

    public func adding(_ candidates: [String]) -> Self {
        Self(entries: entries + candidates)
    }

    public func removing(_ entry: String) -> Self {
        let removedIdentity = Self.identity(for: entry)
        return Self(
            entries: entries.filter {
                Self.identity(for: $0) != removedIdentity
            }
        )
    }

    public static func identity(for entry: String) -> String {
        entry.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
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
            let identity = Self.identity(for: value)
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

public enum InternalDictionaryDraftRejectionReason: Equatable, Sendable {
    case tooLong
    case capacity
}

public struct InternalDictionaryDraftRejection: Equatable, Sendable {
    public let value: String
    public let reason: InternalDictionaryDraftRejectionReason

    public init(
        value: String,
        reason: InternalDictionaryDraftRejectionReason
    ) {
        self.value = value
        self.reason = reason
    }
}

public struct InternalDictionaryDraftParseResult: Equatable, Sendable {
    public let candidates: [String]
    public let duplicates: [String]
    public let rejected: [InternalDictionaryDraftRejection]

    public init(
        candidates: [String],
        duplicates: [String],
        rejected: [InternalDictionaryDraftRejection]
    ) {
        self.candidates = candidates
        self.duplicates = duplicates
        self.rejected = rejected
    }
}

/// Parses explicitly entered or dictated dictionary drafts without using a
/// model, network request, or background worker. Saved entries are never
/// changed by parsing alone.
public enum InternalDictionaryDraftParser {
    private static let commandPrefixes = ["add", "include", "save"]

    public static func parse(
        _ draft: String,
        existingEntries: [String]
    ) -> InternalDictionaryDraftParseResult {
        let rawValues = splitPreservingQuotedDelimiters(draft)
        var existingIdentities = Set(
            existingEntries.map(InternalDictionary.identity(for:))
        )
        var candidates: [String] = []
        var duplicates: [String] = []
        var rejected: [InternalDictionaryDraftRejection] = []

        for (index, rawValue) in rawValues.enumerated() {
            let value = cleaned(
                rawValue,
                isFirst: index == rawValues.startIndex,
                isLastInList: rawValues.count > 1
                    && index == rawValues.index(before: rawValues.endIndex)
            )
            guard !value.isEmpty else {
                continue
            }
            guard value.count <= InternalDictionary.maximumEntryCharacters
            else {
                rejected.append(
                    InternalDictionaryDraftRejection(
                        value: value,
                        reason: .tooLong
                    )
                )
                continue
            }

            let identity = InternalDictionary.identity(for: value)
            guard existingIdentities.insert(identity).inserted else {
                duplicates.append(value)
                continue
            }

            let merged = InternalDictionary(
                entries: existingEntries + candidates + [value]
            )
            guard merged.entries.contains(where: {
                InternalDictionary.identity(for: $0) == identity
            }) else {
                existingIdentities.remove(identity)
                rejected.append(
                    InternalDictionaryDraftRejection(
                        value: value,
                        reason: .capacity
                    )
                )
                continue
            }
            candidates.append(value)
        }

        return InternalDictionaryDraftParseResult(
            candidates: candidates,
            duplicates: duplicates,
            rejected: rejected
        )
    }

    private static func splitPreservingQuotedDelimiters(
        _ draft: String
    ) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?

        for character in draft {
            if character == "\"" || character == "'"
                || character == "“" || character == "”"
                || character == "‘" || character == "’"
            {
                if quote == nil {
                    quote = character
                } else if quoteMatches(opening: quote, closing: character) {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }
            if quote == nil,
               character == "," || character == ";" || character == "\n"
            {
                result.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        result.append(current)
        return result
    }

    private static func quoteMatches(
        opening: Character?,
        closing: Character
    ) -> Bool {
        switch (opening, closing) {
        case ("\"", "\""), ("'", "'"), ("“", "”"), ("‘", "’"):
            true
        default:
            false
        }
    }

    private static func cleaned(
        _ rawValue: String,
        isFirst: Bool,
        isLastInList: Bool
    ) -> String {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = value.first,
              first == "-" || first == "•"
        {
            value.removeFirst()
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if isFirst {
            let lowercase = value.lowercased()
            for prefix in commandPrefixes {
                let command = prefix + " "
                if lowercase.hasPrefix(command) {
                    value.removeFirst(command.count)
                    break
                }
            }
        }
        if isLastInList {
            let lowercase = value.lowercased()
            for connector in ["and ", "or "] where lowercase.hasPrefix(connector) {
                value.removeFirst(connector.count)
                break
            }
        }
        return value.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(
                CharacterSet(charactersIn: ".")
            )
        )
    }
}

public enum RecognitionEngine: String, CaseIterable, Codable, Sendable {
    case whisperCppMetal
    case whisperCppCoreML
    case whisperKitCoreML
    case parakeetCoreML

    public static let defaultEngine: Self = .whisperCppMetal

    public var displayName: String {
        switch self {
        case .whisperCppMetal:
            "Metal"
        case .whisperCppCoreML:
            "Core ML Encoder"
        case .whisperKitCoreML:
            "WhisperKit"
        case .parakeetCoreML:
            "Parakeet"
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
        case .parakeetCoreML:
            "Parakeet Neural Engine"
        }
    }

    /// Whether the engine decodes with whisper.cpp's beam/greedy machinery.
    /// The Decoding row only has meaning for these engines: WhisperKit owns its
    /// own decoder, and Parakeet is a transducer with no beam search at all.
    public var usesWhisperDecoding: Bool {
        switch self {
        case .whisperCppMetal, .whisperCppCoreML:
            true
        case .whisperKitCoreML, .parakeetCoreML:
            false
        }
    }

    /// Whether recognition runs in the owned helper subprocess. In-process
    /// engines skip helper discovery, leases, and the command-line fallback.
    public var usesLocalHelper: Bool {
        switch self {
        case .whisperCppMetal, .whisperCppCoreML:
            true
        case .whisperKitCoreML, .parakeetCoreML:
            false
        }
    }

    /// Whether a text prompt can bias the decode. Parakeet transducers accept
    /// no prompt, so the dictionary and Pause Mode context are dropped.
    public var supportsPromptConditioning: Bool {
        self != .parakeetCoreML
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

/// The two Parakeet checkpoints the app can run, both English and both served
/// from the Neural Engine. Measured on LibriSpeech test-clean plus test-other
/// (100 utterances, Apple M5 Pro): `.fast` 3.88% WER at 34 ms mean latency,
/// `.accurate` 2.62% WER at 56 ms. The whisper Large-v3 Turbo Q5 baseline on
/// the same set is 4.32% WER at 321 ms.
public enum ParakeetVariant: String, CaseIterable, Codable, Sendable {
    /// `parakeet-tdt-ctc-110m` — 219 MB on disk.
    case fast
    /// `parakeet-tdt-0.6b-v2` — 443 MB on disk.
    case accurate

    public static let defaultVariant: Self = .accurate

    /// Chip label. These are the only two Parakeet offers, so they describe the
    /// tradeoff directly instead of borrowing whisper's size names.
    public var displayName: String {
        switch self {
        case .fast:
            "Fast"
        case .accurate:
            "Accurate"
        }
    }

    /// Long form used in the settings summary and the guide.
    public var menuTitle: String {
        switch self {
        case .fast:
            "Fast (110M, 219 MB, lowest latency)"
        case .accurate:
            "Accurate (0.6B, 443 MB, lowest error rate)"
        }
    }

    /// Size quoted before a first-use download. Approximate because the
    /// checkpoint is several files and is compiled after the transfer.
    public var approximateDownloadDescription: String {
        switch self {
        case .fast:
            "220 MB"
        case .accurate:
            "440 MB"
        }
    }

    /// Directory FluidAudio caches this checkpoint under.
    public var cacheFolderName: String {
        switch self {
        case .fast:
            "parakeet-tdt-ctc-110m"
        case .accurate:
            "parakeet-tdt-0.6b-v2"
        }
    }

    public static func selected(
        defaults: UserDefaults = .standard
    ) -> Self {
        guard let rawValue = defaults.string(
            forKey: WhisperHotkeyPreferenceKeys.parakeetModel
        ) else {
            return .defaultVariant
        }
        return Self(rawValue: rawValue) ?? .defaultVariant
    }
}

public enum DictationModel: String, CaseIterable, Codable, Sendable {
    case baseEnglish
    case largeV3TurboQ5

    public static let defaultModel: Self = .baseEnglish

    /// Models retired in 3.4.0, kept only so a saved preference can be read
    /// and migrated. Small sat 82 MB below Turbo while being far less
    /// accurate, and Parakeet Fast beats it on size, speed, and accuracy at
    /// once. Medium was the largest and slowest model in the app and was not
    /// more accurate than Turbo.
    static let retiredRawValues: [String: Self] = [
        "smallEnglish": .largeV3TurboQ5,
        "mediumEnglish": .largeV3TurboQ5,
    ]

    public var displayName: String {
        switch self {
        case .baseEnglish:
            "Base English"
        case .largeV3TurboQ5:
            "Large-v3 Turbo Q5"
        }
    }

    public var menuTitle: String {
        switch self {
        case .baseEnglish:
            "Base English (Fast, 141 MB)"
        case .largeV3TurboQ5:
            "Large-v3 Turbo Q5 (Best Balance, 547 MB)"
        }
    }

    public var fileName: String {
        switch self {
        case .baseEnglish:
            "ggml-base.en.bin"
        case .largeV3TurboQ5:
            "ggml-large-v3-turbo-q5_0.bin"
        }
    }

    public var whisperKitFolderName: String {
        switch self {
        case .baseEnglish:
            "openai_whisper-base.en"
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
        if let model = Self(rawValue: rawValue) {
            return model
        }
        // A saved Small or Medium selection resolves to Turbo, which is more
        // accurate than either and is bundled, rather than silently dropping
        // the user to the default.
        return retiredRawValues[rawValue] ?? .defaultModel
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
