import Foundation

/// A small, private text tail used to condition the next Pause Mode decode.
/// Bounding this value prevents a long continuous session from increasing
/// recognition work or memory without limit.
public enum DictationContextPrompt {
    public static let maximumCharacters = 240

    public static func boundedTail(of transcript: String) -> String? {
        let tail = transcript.suffix(maximumCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return tail.isEmpty ? nil : String(tail)
    }
}
