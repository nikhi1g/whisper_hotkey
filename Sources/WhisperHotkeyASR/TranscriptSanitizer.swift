import Foundation

public enum WhisperTranscriptSanitizer {
    private static let nonSpeechOnly = try! NSRegularExpression(
        pattern: #"(?i)^[\[(]\s*(?:blank[ _-]?audio|silence|music|inaudible|no speech|applause|laughter)\s*[\])]$"#
    )

    public static func clean(_ output: String) -> String {
        var text = replacing(
            pattern: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]",
            in: output,
            with: ""
        )
        text = replacing(
            pattern: #"(?m)^\s*\[[0-9:.]+\s*-->\s*[0-9:.]+\]\s*"#,
            in: text,
            with: ""
        )
        text = replacing(pattern: #"<\|[^|>]+\|>"#, in: text, with: " ")
        text = replacing(
            pattern: #"(?i)[\[(]\s*(?:blank[ _-]?audio|silence|music|inaudible|no speech|applause|laughter)\s*[\])]"#,
            in: text,
            with: " "
        )

        let lines = text.components(separatedBy: .newlines).compactMap { rawLine -> String? in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return nil }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard nonSpeechOnly.firstMatch(in: line, range: range) == nil else {
                return nil
            }
            return line
        }
        return normalizedWhitespace(lines.joined(separator: " "))
    }

    static func normalizedWhitespace(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replacing(
        pattern: String,
        in text: String,
        with replacement: String
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: replacement
        )
    }
}
