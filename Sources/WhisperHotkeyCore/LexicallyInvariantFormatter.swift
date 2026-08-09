import Foundation

/// The bounded punctuation alphabet used by the formatting layer.
///
/// These labels are attached to an existing word.  They never contain text
/// that could be mistaken for a replacement lexical token.
public enum LexicalFormattingPunctuation: String, Codable, CaseIterable, Hashable, Sendable {
    case none
    case comma
    case period
    case question
    case exclamation
    case colon
    case semicolon

    public var symbol: String {
        switch self {
        case .none: ""
        case .comma: ","
        case .period: "."
        case .question: "?"
        case .exclamation: "!"
        case .colon: ":"
        case .semicolon: ";"
        }
    }

    public var isSentenceBoundary: Bool {
        switch self {
        case .period, .question, .exclamation:
            true
        case .none, .comma, .colon, .semicolon:
            false
        }
    }
}

/// Casing labels are applied only to the lexical surface of the existing
/// word.  In particular, `.preserve` is used for acronyms and mixed-case
/// identifiers so a formatter cannot silently turn them into ordinary words.
public enum LexicalFormattingCase: String, Codable, CaseIterable, Hashable, Sendable {
    case preserve
    case sentenceInitial
    case title
    case lower
    case upper
}

/// Boundary labels are optional in the input (`.automatic`); punctuation
/// labels that end a sentence imply `.sentence` during application.
public enum LexicalFormattingBoundary: String, Codable, CaseIterable, Hashable, Sendable {
    case automatic
    case none
    case sentence
    case paragraph
}

/// Content-free evidence consumed by the deterministic scorer.  Values are
/// normalized probabilities/scores, not model output or transcript text.
public struct LexicalFormattingEvidence: Codable, Hashable, Sendable {
    public var pauseAfterSeconds: Double?
    public var pitchContinuation: Double?
    public var energyContinuation: Double?
    public var semanticCompleteness: Double?
    public var questionLikelihood: Double?
    public var providerPunctuation: LexicalFormattingPunctuation?
    public var providerPunctuationConfidence: Double?
    public var isProperNoun: Bool
    public var isAcronym: Bool
    public var isTruncated: Bool

    public init(
        pauseAfterSeconds: Double? = nil,
        pitchContinuation: Double? = nil,
        energyContinuation: Double? = nil,
        semanticCompleteness: Double? = nil,
        questionLikelihood: Double? = nil,
        providerPunctuation: LexicalFormattingPunctuation? = nil,
        providerPunctuationConfidence: Double? = nil,
        isProperNoun: Bool = false,
        isAcronym: Bool = false,
        isTruncated: Bool = false
    ) {
        self.pauseAfterSeconds = pauseAfterSeconds
        self.pitchContinuation = pitchContinuation
        self.energyContinuation = energyContinuation
        self.semanticCompleteness = semanticCompleteness
        self.questionLikelihood = questionLikelihood
        self.providerPunctuation = providerPunctuation
        self.providerPunctuationConfidence = providerPunctuationConfidence
        self.isProperNoun = isProperNoun
        self.isAcronym = isAcronym
        self.isTruncated = isTruncated
    }

    public static let none = Self()

    /// Alias useful to callers that name the measurement as a duration.
    public var pauseDurationSeconds: Double? {
        get { pauseAfterSeconds }
        set { pauseAfterSeconds = newValue }
    }
}

/// A stable-word input to the formatter.  Evidence is keyed by the stable
/// word ID, so a reordered or replaced lexical word cannot inherit a label by
/// array position.
public struct LexicalFormattingInput: Hashable, Sendable {
    public let words: [RecognizedWord]
    public let evidence: [StableWordID: LexicalFormattingEvidence]
    public let completeness: DecodeCompleteness

    public init(
        words: [RecognizedWord],
        evidence: [StableWordID: LexicalFormattingEvidence] = [:],
        completeness: DecodeCompleteness = .finalSession
    ) {
        self.words = words
        self.evidence = evidence
        self.completeness = completeness
    }

    public init(
        result: RecognitionResult,
        evidence: [StableWordID: LexicalFormattingEvidence] = [:]
    ) {
        self.init(
            words: result.words,
            evidence: evidence,
            completeness: result.completeness
        )
    }
}

/// One label attached to one stable word ID.
public struct LexicalFormattingLabel: Codable, Hashable, Sendable {
    public let wordID: StableWordID
    public let punctuation: LexicalFormattingPunctuation
    public let casing: LexicalFormattingCase
    public let boundary: LexicalFormattingBoundary
    public let confidence: Double?

    public init(
        wordID: StableWordID,
        punctuation: LexicalFormattingPunctuation = .none,
        casing: LexicalFormattingCase = .preserve,
        boundary: LexicalFormattingBoundary = .automatic,
        confidence: Double? = nil
    ) {
        self.wordID = wordID
        self.punctuation = punctuation
        self.casing = casing
        self.boundary = boundary
        self.confidence = confidence
    }

    public static func plain(for wordID: StableWordID) -> Self {
        Self(wordID: wordID)
    }

    public var id: StableWordID { wordID }
    public var sentenceBoundaryConfidence: Double? { confidence }

    fileprivate var resolvedBoundary: LexicalFormattingBoundary {
        switch boundary {
        case .automatic:
            punctuation.isSentenceBoundary ? .sentence : .none
        case .none, .sentence, .paragraph:
            boundary
        }
    }

    fileprivate var isValid: Bool {
        guard let confidence else { return true }
        return confidence.isFinite && (0...1).contains(confidence)
    }
}

/// A rendered word retains the stable ID and the label that produced it.
/// `lexicalText` is the existing lexical token after a case-only transform;
/// punctuation is kept in a separate field to make the invariant auditable.
public struct FormattedLexicalWord: Hashable, Sendable {
    public let id: StableWordID
    public let lexicalText: String
    public let punctuation: LexicalFormattingPunctuation
    public let boundary: LexicalFormattingBoundary

    public init(
        id: StableWordID,
        lexicalText: String,
        punctuation: LexicalFormattingPunctuation = .none,
        boundary: LexicalFormattingBoundary = .none
    ) {
        self.id = id
        self.lexicalText = lexicalText
        self.punctuation = punctuation
        self.boundary = boundary
    }

    public var renderedText: String {
        lexicalText + punctuation.symbol
    }

    public var wordID: StableWordID { id }
    public var text: String { renderedText }
}

public enum LexicalFormattingFailure: Hashable, Sendable {
    case invalidInput
    case duplicateWordID(StableWordID)
    case malformedWord(StableWordID)
    case unknownEvidenceWord(StableWordID)
    case invalidEvidence(StableWordID)
    case duplicateLabel(StableWordID)
    case unknownLabel(StableWordID)
    case missingLabel(StableWordID)
    case invalidLabel(StableWordID)
    case inconsistentBoundary(StableWordID)
    case paragraphNotFinal(StableWordID)
    case lexicalMutation
}

/// Formatting output and its safety decision.  On rejection, `formattedText`
/// is the unformatted word sequence and `didFailClosed` is true.
public struct LexicallyInvariantFormattingResult: Hashable, Sendable {
    public let formattedText: String
    public let words: [FormattedLexicalWord]
    public let labels: [LexicalFormattingLabel]
    public let accepted: Bool
    public let failure: LexicalFormattingFailure?

    public var text: String { formattedText }
    public var didFailClosed: Bool { !accepted }
    public var lexicalInvariant: Bool { true }

    fileprivate init(
        formattedText: String,
        words: [FormattedLexicalWord],
        labels: [LexicalFormattingLabel],
        accepted: Bool,
        failure: LexicalFormattingFailure?
    ) {
        self.formattedText = formattedText
        self.words = words
        self.labels = labels
        self.accepted = accepted
        self.failure = failure
    }
}

/// The lexical proof used by the formatter and available to benchmark/tests.
/// It compares ordered lexical tokens and stable IDs while ignoring only case
/// and formatting punctuation.  Any count, ID, or token mismatch fails.
public enum LexicalInvariantGuard {
    public static func areLexicallyInvariant(
        originalWords: [RecognizedWord],
        formattedWords: [FormattedLexicalWord]
    ) -> Bool {
        guard originalWords.count == formattedWords.count else { return false }
        var seen = Set<StableWordID>()
        for (original, formatted) in zip(originalWords, formattedWords) {
            guard original.id == formatted.id, seen.insert(formatted.id).inserted else {
                return false
            }
            guard let expected = LexicalTokenNormalizer.singleToken(from: original.text),
                  let actual = LexicalTokenNormalizer.singleToken(from: formatted.lexicalText),
                  expected.lowercased() == actual.lowercased()
            else {
                return false
            }
        }
        return true
    }

    /// String-level proof for callers that already have a rendered candidate.
    /// This intentionally does not attempt spelling correction: case folding
    /// and formatting punctuation are the only ignored differences.
    public static func areLexicallyInvariant(
        original: String,
        formatted: String
    ) -> Bool {
        LexicalTokenNormalizer.tokens(from: original)
            == LexicalTokenNormalizer.tokens(from: formatted)
    }

    public static func validate(
        originalWords: [RecognizedWord],
        formattedWords: [FormattedLexicalWord]
    ) -> Bool {
        areLexicallyInvariant(originalWords: originalWords, formattedWords: formattedWords)
    }
}

/// Deterministic, bounded punctuation/case scorer followed by a strict label
/// application guard.  No model, network request, or free-form text
/// generation is involved.
public struct LexicallyInvariantFormatter: Sendable {
    public struct Configuration: Hashable, Sendable {
        public let maxLookaheadWords: Int
        public let commaPauseThreshold: Double
        public let sentencePauseThreshold: Double
        public let semanticCompletenessThreshold: Double
        public let questionThreshold: Double
        public let continuationThreshold: Double
        public let providerPunctuationThreshold: Double

        public init(
            maxLookaheadWords: Int = 4,
            commaPauseThreshold: Double = 0.35,
            sentencePauseThreshold: Double = 0.80,
            semanticCompletenessThreshold: Double = 0.60,
            questionThreshold: Double = 0.68,
            continuationThreshold: Double = 0.64,
            providerPunctuationThreshold: Double = 0.72
        ) {
            self.maxLookaheadWords = min(8, max(0, maxLookaheadWords))
            self.commaPauseThreshold = Self.nonNegativeFinite(
                commaPauseThreshold,
                fallback: 0.35
            )
            self.sentencePauseThreshold = Self.nonNegativeFinite(
                sentencePauseThreshold,
                fallback: 0.80
            )
            self.semanticCompletenessThreshold = Self.probability(
                semanticCompletenessThreshold,
                fallback: 0.60
            )
            self.questionThreshold = Self.probability(questionThreshold, fallback: 0.68)
            self.continuationThreshold = Self.probability(
                continuationThreshold,
                fallback: 0.64
            )
            self.providerPunctuationThreshold = Self.probability(
                providerPunctuationThreshold,
                fallback: 0.72
            )
        }

        public static let `default` = Self()

        private static func probability(_ value: Double, fallback: Double) -> Double {
            guard value.isFinite else { return fallback }
            return min(1, max(0, value))
        }

        private static func nonNegativeFinite(_ value: Double, fallback: Double) -> Double {
            guard value.isFinite, value >= 0 else { return fallback }
            return min(30, value)
        }
    }

    public let configuration: Configuration

    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    /// Produce labels without touching lexical text.  The lookahead is capped
    /// by `Configuration.maxLookaheadWords` and never scans the full tail.
    public func labels(for input: LexicalFormattingInput) -> [LexicalFormattingLabel] {
        guard input.words.allSatisfy({
            LexicalTokenNormalizer.singleToken(from: $0.text) != nil
        }) else {
            return input.words.map { .plain(for: $0.id) }
        }

        var labels: [LexicalFormattingLabel] = []
        labels.reserveCapacity(input.words.count)
        var startsSentence = true

        for index in input.words.indices {
            let word = input.words[index]
            let evidence = input.evidence[word.id] ?? .none
            let punctuation = punctuation(
                at: index,
                input: input,
                evidence: evidence
            )
            let casing = casing(
                for: word,
                evidence: evidence,
                startsSentence: startsSentence
            )
            let boundary: LexicalFormattingBoundary = punctuation.isSentenceBoundary
                ? .sentence
                : .none
            let label = LexicalFormattingLabel(
                wordID: word.id,
                punctuation: punctuation,
                casing: casing,
                boundary: boundary
            )
            labels.append(label)
            startsSentence = punctuation.isSentenceBoundary
        }
        return labels
    }

    /// Apply a complete label set to an input.  Unknown, duplicate, missing,
    /// malformed, or lexically mutating labels all return the unformatted
    /// sequence instead of attempting best-effort recovery.
    public func apply(
        _ labels: [LexicalFormattingLabel],
        to input: LexicalFormattingInput
    ) -> LexicallyInvariantFormattingResult {
        if let failure = validateInput(input) {
            return rejected(input: input, labels: labels, failure: failure)
        }

        var labelsByID: [StableWordID: LexicalFormattingLabel] = [:]
        labelsByID.reserveCapacity(labels.count)
        let wordIDs = Set(input.words.map(\.id))

        for label in labels {
            guard wordIDs.contains(label.wordID) else {
                return rejected(
                    input: input,
                    labels: labels,
                    failure: .unknownLabel(label.wordID)
                )
            }
            guard labelsByID[label.wordID] == nil else {
                return rejected(
                    input: input,
                    labels: labels,
                    failure: .duplicateLabel(label.wordID)
                )
            }
            guard label.isValid else {
                return rejected(
                    input: input,
                    labels: labels,
                    failure: .invalidLabel(label.wordID)
                )
            }
            guard validBoundary(for: label, input: input) else {
                return rejected(
                    input: input,
                    labels: labels,
                    failure: boundaryFailure(for: label, input: input)
                )
            }
            labelsByID[label.wordID] = label
        }

        for word in input.words where labelsByID[word.id] == nil {
            return rejected(
                input: input,
                labels: labels,
                failure: .missingLabel(word.id)
            )
        }

        let formattedWords = input.words.map { word in
            let label = labelsByID[word.id]!
            let surface = LexicalTokenNormalizer.singleToken(from: word.text)!
            return FormattedLexicalWord(
                id: word.id,
                lexicalText: apply(label.casing, to: surface),
                punctuation: label.punctuation,
                boundary: label.resolvedBoundary
            )
        }
        let formattedText = render(formattedWords)

        guard LexicalInvariantGuard.areLexicallyInvariant(
            originalWords: input.words,
            formattedWords: formattedWords
        ),
        LexicalInvariantGuard.areLexicallyInvariant(
            original: unformattedText(for: input.words),
            formatted: formattedText
        ) else {
            return rejected(input: input, labels: labels, failure: .lexicalMutation)
        }

        return LexicallyInvariantFormattingResult(
            formattedText: formattedText,
            words: formattedWords,
            labels: labels,
            accepted: true,
            failure: nil
        )
    }

    public func format(
        _ input: LexicalFormattingInput
    ) -> LexicallyInvariantFormattingResult {
        apply(labels(for: input), to: input)
    }

    public func format(
        _ result: RecognitionResult,
        evidence: [StableWordID: LexicalFormattingEvidence] = [:]
    ) -> LexicallyInvariantFormattingResult {
        guard !result.words.isEmpty else {
            return LexicallyInvariantFormattingResult(
                formattedText: result.text,
                words: [],
                labels: [],
                accepted: true,
                failure: nil
            )
        }
        return format(LexicalFormattingInput(result: result, evidence: evidence))
    }

    public func format(
        words: [RecognizedWord],
        evidence: [StableWordID: LexicalFormattingEvidence] = [:],
        completeness: DecodeCompleteness = .finalSession
    ) -> LexicallyInvariantFormattingResult {
        format(
            LexicalFormattingInput(
                words: words,
                evidence: evidence,
                completeness: completeness
            )
        )
    }

    private func punctuation(
        at index: Int,
        input: LexicalFormattingInput,
        evidence: LexicalFormattingEvidence
    ) -> LexicalFormattingPunctuation {
        let word = input.words[index]
        let token = LexicalTokenNormalizer.singleToken(from: word.text) ?? ""
        let lowerToken = token.lowercased()
        let nextWords = Array(
            input.words.dropFirst(index + 1).prefix(configuration.maxLookaheadWords)
        )
        let nextTokens = nextWords.compactMap {
            LexicalTokenNormalizer.singleToken(from: $0.text)?.lowercased()
        }
        let nextConnects = nextTokens.first.map(isContinuationWord) ?? false
        let continuation = continuationScore(evidence) >= configuration.continuationThreshold
            || nextConnects
        let truncated = evidence.isTruncated || input.completeness == .truncated
        let pause = evidence.pauseAfterSeconds ?? 0
        let semantic = evidence.semanticCompleteness
        let semanticEnough = semantic.map {
            $0 >= configuration.semanticCompletenessThreshold
        } ?? false
        let isTerminal = index == input.words.index(before: input.words.endIndex)
        let isFinal = input.completeness == .finalSession
            || input.completeness == .completeSentence
        let semanticAllowsFinalStop = semantic.map {
            $0 >= configuration.semanticCompletenessThreshold
        } ?? true
        let finalStopAllowed = isTerminal && isFinal && !truncated
            && !isIncompleteToken(lowerToken)
            && semanticAllowsFinalStop

        let providerConfidence = evidence.providerPunctuationConfidence ?? 0
        let trustedProviderPunctuation = providerConfidence
            >= configuration.providerPunctuationThreshold
            ? evidence.providerPunctuation
            : nil

        let inferredQuestion = isTerminal
            && isFinal
            && !truncated
            && looksLikeQuestion(input.words.first?.text, token: lowerToken)
            && !isIncompleteToken(lowerToken)
        let acousticEndpoint = pause >= configuration.sentencePauseThreshold
            && !continuation
            && !truncated
        let sentenceEndpoint = finalStopAllowed
            || (!truncated && semanticEnough && acousticEndpoint)
            || (!truncated && acousticEndpoint && trustedProviderPunctuation?.isSentenceBoundary == true)

        if sentenceEndpoint {
            if evidence.questionLikelihood ?? 0 >= configuration.questionThreshold,
               !isIncompleteToken(lowerToken) {
                return .question
            }
            if inferredQuestion {
                return .question
            }
            if let trustedProviderPunctuation,
               trustedProviderPunctuation.isSentenceBoundary {
                return trustedProviderPunctuation
            }
            return .period
        }

        // Thinking pauses are intentionally conservative: without semantic
        // completeness or an explicit provider comma, a pause is not enough
        // to add punctuation.  This prevents a period in an incomplete clause.
        if !truncated,
           let trustedProviderPunctuation,
           !trustedProviderPunctuation.isSentenceBoundary {
            return trustedProviderPunctuation
        }

        if !truncated,
           pause >= configuration.commaPauseThreshold,
           semantic.map({ $0 >= configuration.commaPauseThreshold }) == true,
           !continuation,
           !isIncompleteToken(lowerToken) {
            return .comma
        }
        return .none
    }

    private func casing(
        for word: RecognizedWord,
        evidence: LexicalFormattingEvidence,
        startsSentence: Bool
    ) -> LexicalFormattingCase {
        let token = LexicalTokenNormalizer.singleToken(from: word.text) ?? ""
        if evidence.isAcronym || LexicalTokenNormalizer.looksLikeAcronym(token) {
            return evidence.isAcronym && !LexicalTokenNormalizer.looksLikeAcronym(token)
                ? .upper
                : .preserve
        }
        if evidence.isProperNoun {
            return .title
        }
        if LexicalTokenNormalizer.hasInternalCase(token) {
            return .preserve
        }
        if startsSentence {
            return .sentenceInitial
        }
        return .preserve
    }

    private func continuationScore(_ evidence: LexicalFormattingEvidence) -> Double {
        max(evidence.pitchContinuation ?? 0, evidence.energyContinuation ?? 0)
    }

    private func isContinuationWord(_ token: String) -> Bool {
        [
            "and", "or", "but", "because", "so", "if", "when", "while", "although",
            "yet", "to", "of", "in", "on", "at", "for", "from", "with", "by", "as",
            "about", "into", "over", "after", "before", "under", "through"
        ].contains(token)
    }

    private func isIncompleteToken(_ token: String) -> Bool {
        [
            "a", "an", "the", "this", "that", "these", "those", "and", "or", "but",
            "because", "if", "when", "while", "although", "to", "of", "in", "on", "at",
            "for", "from", "with", "by", "as", "about", "into", "over", "after",
            "before", "under", "through", "is", "are", "was", "were", "be", "been",
            "being", "do", "does", "did", "can", "could", "will", "would", "should",
            "may", "might", "must", "have", "has", "had"
        ].contains(token)
    }

    private func looksLikeQuestion(_ firstWord: String?, token: String) -> Bool {
        let first = firstWord.flatMap {
            LexicalTokenNormalizer.singleToken(from: $0)?.lowercased()
        }
        guard let first else { return false }
        return [
            "am", "are", "is", "was", "were", "do", "does", "did", "can", "could",
            "will", "would", "should", "have", "has", "had", "what", "when", "where",
            "why", "how", "who", "which"
        ].contains(first) || token == "why"
    }

    private func validateInput(
        _ input: LexicalFormattingInput
    ) -> LexicalFormattingFailure? {
        var seen = Set<StableWordID>()
        for word in input.words {
            guard seen.insert(word.id).inserted else {
                return .duplicateWordID(word.id)
            }
            guard LexicalTokenNormalizer.singleToken(from: word.text) != nil else {
                return .malformedWord(word.id)
            }
            if let evidence = input.evidence[word.id], !valid(evidence) {
                return .invalidEvidence(word.id)
            }
        }
        for id in input.evidence.keys where !seen.contains(id) {
            return .unknownEvidenceWord(id)
        }
        return nil
    }

    private func valid(_ evidence: LexicalFormattingEvidence) -> Bool {
        guard finiteNonNegative(evidence.pauseAfterSeconds),
              probability(evidence.pitchContinuation),
              probability(evidence.energyContinuation),
              probability(evidence.semanticCompleteness),
              probability(evidence.questionLikelihood),
              probability(evidence.providerPunctuationConfidence)
        else {
            return false
        }
        return true
    }

    private func finiteNonNegative(_ value: Double?) -> Bool {
        guard let value else { return true }
        return value.isFinite && value >= 0
    }

    private func probability(_ value: Double?) -> Bool {
        guard let value else { return true }
        return value.isFinite && (0...1).contains(value)
    }

    private func validBoundary(
        for label: LexicalFormattingLabel,
        input: LexicalFormattingInput
    ) -> Bool {
        switch label.boundary {
        case .automatic:
            return true
        case .none:
            return !label.punctuation.isSentenceBoundary
        case .sentence:
            return label.punctuation.isSentenceBoundary
        case .paragraph:
            guard label.punctuation.isSentenceBoundary,
                  input.completeness == .finalSession,
                  input.words.last?.id == label.wordID
            else { return false }
            return true
        }
    }

    private func boundaryFailure(
        for label: LexicalFormattingLabel,
        input: LexicalFormattingInput
    ) -> LexicalFormattingFailure {
        if label.boundary == .paragraph {
            return .paragraphNotFinal(label.wordID)
        }
        return .inconsistentBoundary(label.wordID)
    }

    private func apply(
        _ casing: LexicalFormattingCase,
        to token: String
    ) -> String {
        switch casing {
        case .preserve:
            return token
        case .lower:
            return token.lowercased()
        case .upper:
            return token.uppercased()
        case .sentenceInitial, .title:
            guard let first = token.first else { return token }
            return String(first).uppercased() + token.dropFirst()
        }
    }

    private func render(_ words: [FormattedLexicalWord]) -> String {
        var result = ""
        result.reserveCapacity(words.reduce(0) { $0 + $1.renderedText.count + 1 })
        for (index, word) in words.enumerated() {
            if index > 0 {
                let separator = words[index - 1].boundary == .paragraph ? "\n\n" : " "
                result.append(separator)
            }
            result.append(word.renderedText)
        }
        return result
    }

    private func unformattedText(for words: [RecognizedWord]) -> String {
        words.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func rejected(
        input: LexicalFormattingInput,
        labels: [LexicalFormattingLabel],
        failure: LexicalFormattingFailure
    ) -> LexicallyInvariantFormattingResult {
        let fallbackWords = input.words.map { word in
            FormattedLexicalWord(
                id: word.id,
                lexicalText: word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return LexicallyInvariantFormattingResult(
            formattedText: unformattedText(for: input.words),
            words: fallbackWords,
            labels: labels,
            accepted: false,
            failure: failure
        )
    }
}

private enum LexicalTokenNormalizer {
    static func singleToken(from raw: String) -> String? {
        let tokens = tokens(from: raw)
        guard tokens.count == 1 else { return nil }

        // Keep the original case and lexical symbols for rendering while
        // removing only punctuation that belongs to the formatter alphabet.
        var surface = raw.precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let formattingMarks = CharacterSet(charactersIn: ",.!?:;")
        while let first = surface.first,
              first.isWhitespace || first.unicodeScalars.allSatisfy({
                  formattingMarks.contains($0)
              }) {
            surface.removeFirst()
        }
        while let last = surface.last,
              last.isWhitespace || last.unicodeScalars.allSatisfy({
                  formattingMarks.contains($0)
              }) {
            surface.removeLast()
        }
        guard !surface.isEmpty else { return nil }
        return surface
    }

    static func tokens(from raw: String) -> [String] {
        let normalized = raw.precomposedStringWithCompatibilityMapping
        let characters = Array(normalized)
        var tokens: [String] = []
        var current = ""

        func flush() {
            guard !current.isEmpty else { return }
            tokens.append(current.lowercased())
            current.removeAll(keepingCapacity: true)
        }

        for index in characters.indices {
            let character = characters[index]
            let next = index < characters.index(before: characters.endIndex)
                ? characters[characters.index(after: index)]
                : nil
            if character.isLetter || character.isNumber || character == "_" {
                current.append(character)
                continue
            }
            if (character == "'" || character == "’" || character == "-")
                && !current.isEmpty,
                let next,
                next.isLetter || next.isNumber {
                current.append(character == "’" ? "'" : character)
                continue
            }
            if character == ".",
               !current.isEmpty,
               let next,
               next.isNumber {
                current.append(character)
                continue
            }
            flush()
        }
        flush()
        return tokens
    }

    static func looksLikeAcronym(_ token: String) -> Bool {
        let letters = token.filter(\.isLetter)
        guard letters.count >= 2 else { return false }
        let joined = String(letters)
        return joined == joined.uppercased() && joined != joined.lowercased()
    }

    static func hasInternalCase(_ token: String) -> Bool {
        guard token.count > 1 else { return false }
        return token.dropFirst().contains(where: { $0.isUppercase })
    }
}

public typealias FormattingPunctuation = LexicalFormattingPunctuation
public typealias FormattingCase = LexicalFormattingCase
public typealias LexicalFormattingOutput = LexicallyInvariantFormattingResult
