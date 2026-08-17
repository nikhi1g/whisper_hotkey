import Foundation

/// One user-authored system prompt for the custom post-processing profile.
public struct CustomPrompt: Codable, Equatable, Sendable {
    public var name: String
    public var prompt: String

    public init(name: String, prompt: String) {
        self.name = name
        self.prompt = prompt
    }
}

/// The owner's library of custom system prompts. The three built-in profiles
/// stay data in `SemanticProfileCatalog`; everything here is authored in
/// Settings, so the owner can keep as many rewriting instructions as they
/// like and switch between them per dictation.
public enum CustomPromptLibrary {
    public static let maximumPrompts = 24
    public static let maximumNameLength = 40
    public static let maximumPromptLength = 2_000

    /// The seed entry a fresh install starts from, so the Custom chip always
    /// has something to send.
    public static var defaultPrompt: CustomPrompt {
        CustomPrompt(
            name: "My prompt",
            prompt: SemanticProfileCatalog.defaultCustomObjective
        )
    }

    public static func prompts(
        defaults: UserDefaults = .standard
    ) -> [CustomPrompt] {
        guard let data = defaults.data(
            forKey: WhisperHotkeyPreferenceKeys.postProcessingCustomPrompts
        ),
            let decoded = try? JSONDecoder().decode(
                [CustomPrompt].self,
                from: data
            ),
            !decoded.isEmpty
        else {
            return [defaultPrompt]
        }
        return decoded
    }

    public static func setPrompts(
        _ prompts: [CustomPrompt],
        defaults: UserDefaults = .standard
    ) {
        let sanitized = prompts
            .prefix(maximumPrompts)
            .map(sanitize)
            .filter { !$0.prompt.isEmpty }
        guard !sanitized.isEmpty else {
            defaults.removeObject(
                forKey: WhisperHotkeyPreferenceKeys.postProcessingCustomPrompts
            )
            setSelectedIndex(0, defaults: defaults)
            return
        }
        guard let data = try? JSONEncoder().encode(Array(sanitized)) else {
            return
        }
        defaults.set(
            data,
            forKey: WhisperHotkeyPreferenceKeys.postProcessingCustomPrompts
        )
        if selectedIndex(defaults: defaults) >= sanitized.count {
            setSelectedIndex(sanitized.count - 1, defaults: defaults)
        }
    }

    /// Always in range for the stored library, so callers never guard.
    public static func selectedIndex(
        defaults: UserDefaults = .standard
    ) -> Int {
        let stored = defaults.integer(
            forKey: WhisperHotkeyPreferenceKeys
                .postProcessingSelectedCustomPrompt
        )
        let count = prompts(defaults: defaults).count
        return min(max(stored, 0), count - 1)
    }

    public static func setSelectedIndex(
        _ index: Int,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(
            max(index, 0),
            forKey: WhisperHotkeyPreferenceKeys
                .postProcessingSelectedCustomPrompt
        )
    }

    public static func selectedPrompt(
        defaults: UserDefaults = .standard
    ) -> CustomPrompt {
        let library = prompts(defaults: defaults)
        return library[min(selectedIndex(defaults: defaults), library.count - 1)]
    }

    /// Appends a prompt and selects it, which is what "Add" means in Settings.
    @discardableResult
    public static func add(
        _ prompt: CustomPrompt,
        defaults: UserDefaults = .standard
    ) -> Bool {
        var library = prompts(defaults: defaults)
        guard library.count < maximumPrompts else { return false }
        let sanitized = sanitize(prompt)
        guard !sanitized.prompt.isEmpty else { return false }
        library.append(sanitized)
        setPrompts(library, defaults: defaults)
        setSelectedIndex(library.count - 1, defaults: defaults)
        return true
    }

    public static func updateSelected(
        _ prompt: CustomPrompt,
        defaults: UserDefaults = .standard
    ) {
        var library = prompts(defaults: defaults)
        let index = selectedIndex(defaults: defaults)
        let sanitized = sanitize(prompt)
        guard !sanitized.prompt.isEmpty else { return }
        library[index] = sanitized
        setPrompts(library, defaults: defaults)
    }

    /// Removing the last remaining prompt restores the seed entry rather than
    /// leaving the Custom chip with nothing to send.
    public static func removeSelected(defaults: UserDefaults = .standard) {
        var library = prompts(defaults: defaults)
        let index = selectedIndex(defaults: defaults)
        guard library.count > 1 else {
            setPrompts([defaultPrompt], defaults: defaults)
            setSelectedIndex(0, defaults: defaults)
            return
        }
        library.remove(at: index)
        setPrompts(library, defaults: defaults)
        setSelectedIndex(min(index, library.count - 1), defaults: defaults)
    }

    private static func sanitize(_ prompt: CustomPrompt) -> CustomPrompt {
        let name = prompt.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(maximumNameLength)
        let text = prompt.prompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(maximumPromptLength)
        return CustomPrompt(
            name: name.isEmpty ? "Custom" : String(name),
            prompt: String(text)
        )
    }
}
