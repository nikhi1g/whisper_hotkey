import Foundation

/// Combines a persistent vocabulary hint with the bounded Pause Mode context.
public enum RecognitionPrompt {
    public static func combined(
        dictionaryPrompt: String?,
        contextPrompt: String?
    ) -> String? {
        let parts = [dictionaryPrompt, contextPrompt].compactMap { value in
            value?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        }
        return parts.isEmpty ? nil : parts.joined(separator: ". ")
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
