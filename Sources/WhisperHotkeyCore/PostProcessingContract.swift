import Foundation

/// Applies semantic post-processing to a dictated utterance.
///
/// Implementations are expected to call `PostProcessLimits.validateRequest`
/// before processing and to return results that pass
/// `PostProcessLimits.validateResult`.
public protocol TranscriptProcessor: Sendable {
    func process(_ request: PostProcessRequest) async throws -> PostProcessResult
}

public struct PostProcessRequest: Codable, Equatable, Sendable {
    public var rawText: String
    public var profile: SemanticProfileID
    public var locale: String
    public var context: PostProcessContext
    public var alternatives: [String]
    public var uncertainSpans: [String]
    public var protectedTerms: [String]

    public init(
        rawText: String,
        profile: SemanticProfileID,
        locale: String,
        context: PostProcessContext,
        alternatives: [String] = [],
        uncertainSpans: [String] = [],
        protectedTerms: [String] = []
    ) {
        self.rawText = rawText
        self.profile = profile
        self.locale = locale
        self.context = context
        self.alternatives = alternatives
        self.uncertainSpans = uncertainSpans
        self.protectedTerms = protectedTerms
    }
}

public struct PostProcessContext: Codable, Equatable, Sendable {
    public var domain: String?
    public var language: String?
    public var framework: String?
    public var activeTask: String?
    public var frontmostApp: String?
    public var glossary: [String]

    public init(
        domain: String? = nil,
        language: String? = nil,
        framework: String? = nil,
        activeTask: String? = nil,
        frontmostApp: String? = nil,
        glossary: [String] = []
    ) {
        self.domain = domain
        self.language = language
        self.framework = framework
        self.activeTask = activeTask
        self.frontmostApp = frontmostApp
        self.glossary = glossary
    }
}

public enum MeaningChangeRisk: String, Codable, Equatable, Sendable {
    case low
    case medium
    case high
}

public struct PostProcessResult: Codable, Equatable, Sendable {
    public var finalText: String
    public var intent: String
    public var unresolvedSpans: [String]
    public var explicitCorrections: [String]
    public var meaningChangeRisk: MeaningChangeRisk

    public init(
        finalText: String,
        intent: String,
        unresolvedSpans: [String],
        explicitCorrections: [String],
        meaningChangeRisk: MeaningChangeRisk
    ) {
        self.finalText = finalText
        self.intent = intent
        self.unresolvedSpans = unresolvedSpans
        self.explicitCorrections = explicitCorrections
        self.meaningChangeRisk = meaningChangeRisk
    }
}

/// Hand-written bounded validators for the post-processing wire contracts,
/// mirroring the `RecognitionDecodingLimits` pattern.
///
/// rawText ≤ 4000 chars; alternatives ≤ 8 × 200; uncertainSpans ≤ 32 × 80;
/// protectedTerms ≤ 128 × 80; glossary ≤ 64 × 80; finalText ≤ 8000 chars;
/// intent ≤ 400; corrections ≤ 32 × 160; unresolved ≤ 32 × 160.
public enum PostProcessLimits {
    public static let maxRawTextLength = 4_000
    public static let maxFinalTextLength = 8_000
    public static let maxAlternatives = 8
    public static let maxUncertainSpans = 32
    public static let maxProtectedTerms = 128
    public static let maxGlossaryTerms = 64
    public static let maxCorrections = 32

    private static let maxAlternativeLength = 200
    private static let maxUncertainSpanLength = 80
    private static let maxProtectedTermLength = 80
    private static let maxGlossaryTermLength = 80
    private static let maxIntentLength = 400
    private static let maxCorrectionLength = 160
    private static let maxUnresolvedSpans = 32
    private static let maxUnresolvedSpanLength = 160

    public static func validateRequest(_ request: PostProcessRequest) throws {
        try validateString(request.rawText, field: "request.raw_text", maximum: maxRawTextLength)
        try validateStringList(
            request.alternatives,
            field: "request.alternatives",
            maximumCount: maxAlternatives,
            maximumItemLength: maxAlternativeLength
        )
        try validateStringList(
            request.uncertainSpans,
            field: "request.uncertain_spans",
            maximumCount: maxUncertainSpans,
            maximumItemLength: maxUncertainSpanLength
        )
        try validateStringList(
            request.protectedTerms,
            field: "request.protected_terms",
            maximumCount: maxProtectedTerms,
            maximumItemLength: maxProtectedTermLength
        )
        try validateStringList(
            request.context.glossary,
            field: "context.glossary",
            maximumCount: maxGlossaryTerms,
            maximumItemLength: maxGlossaryTermLength
        )
    }

    public static func validateResult(_ result: PostProcessResult) throws {
        try validateString(result.finalText, field: "result.final_text", maximum: maxFinalTextLength)
        try validateString(result.intent, field: "result.intent", maximum: maxIntentLength)
        try validateStringList(
            result.unresolvedSpans,
            field: "result.unresolved_spans",
            maximumCount: maxUnresolvedSpans,
            maximumItemLength: maxUnresolvedSpanLength
        )
        try validateStringList(
            result.explicitCorrections,
            field: "result.explicit_corrections",
            maximumCount: maxCorrections,
            maximumItemLength: maxCorrectionLength
        )
    }

    private static func validateString(_ value: String, field: String, maximum: Int) throws {
        guard value.count <= maximum else {
            throw PostProcessContractError.limitExceeded(field: field, actual: value.count, maximum: maximum)
        }
    }

    private static func validateStringList(
        _ values: [String],
        field: String,
        maximumCount: Int,
        maximumItemLength: Int
    ) throws {
        guard values.count <= maximumCount else {
            throw PostProcessContractError.limitExceeded(
                field: field,
                actual: values.count,
                maximum: maximumCount
            )
        }
        for (index, value) in values.enumerated() {
            guard value.count <= maximumItemLength else {
                throw PostProcessContractError.limitExceeded(
                    field: "\(field)[\(index)]",
                    actual: value.count,
                    maximum: maximumItemLength
                )
            }
        }
    }
}

public enum PostProcessContractError: Error, Equatable, Sendable {
    case limitExceeded(field: String, actual: Int, maximum: Int)
}
