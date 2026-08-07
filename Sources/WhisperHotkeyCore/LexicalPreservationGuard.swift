import Foundation

public enum LexicalPreservationGuard {
    public static func preservesLexicalContent(
        source: String,
        formatted: String,
        allowedEquivalentTokenSets: [Set<String>] = []
    ) -> Bool {
        let sourceTokens = LexicalNormalization.tokens(source)
        let formattedTokens = LexicalNormalization.tokens(formatted)
        guard sourceTokens.count == formattedTokens.count else {
            return false
        }
        return zip(sourceTokens, formattedTokens).allSatisfy { sourceToken, formattedToken in
            guard sourceToken != formattedToken else { return true }
            return allowedEquivalentTokenSets.contains { set in
                set.contains(sourceToken) && set.contains(formattedToken)
            }
        }
    }

    public static func chooseSafeOutput(
        source: String,
        formatted: String,
        allowedEquivalentTokenSets: [Set<String>] = []
    ) -> String {
        preservesLexicalContent(
            source: source,
            formatted: formatted,
            allowedEquivalentTokenSets: allowedEquivalentTokenSets
        ) ? formatted : source
    }
}

public enum LexicalNormalization {
    private static let apostrophes: Set<Character> = ["'", "’"]

    public static func tokens(_ text: String) -> [String] {
        var current = ""
        var tokens: [String] = []
        for character in text {
            if character.isLetter || character.isNumber || apostrophes.contains(character) {
                current.append(character.lowercased())
            } else if !current.isEmpty {
                tokens.append(current)
                current.removeAll(keepingCapacity: true)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}
