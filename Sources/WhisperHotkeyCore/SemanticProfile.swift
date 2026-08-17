import Foundation

public enum SemanticProfileID: String, Codable, CaseIterable, Equatable, Sendable {
    case verbatim
    case clarity
    case coding
    /// User-authored profile: its objective is the prompt the owner typed in
    /// Settings, so the rewrite instructions are theirs rather than built in.
    case custom
}

public struct SemanticProfile: Codable, Equatable, Sendable {
    public var id: SemanticProfileID
    public var name: String
    public var objective: String
    public var structure: [String]
    public var allowed: [String]
    public var forbidden: [String]

    public init(
        id: SemanticProfileID,
        name: String,
        objective: String,
        structure: [String],
        allowed: [String],
        forbidden: [String]
    ) {
        self.id = id
        self.name = name
        self.objective = objective
        self.structure = structure
        self.allowed = allowed
        self.forbidden = forbidden
    }
}

/// The built-in profile data.  Profiles are data, not control flow: prompt
/// assembly consumes these fields and never branches on profile identity.
public enum SemanticProfileCatalog {
    public static let builtIn: [SemanticProfile] = [
        verbatim, clarity, coding, custom,
    ]

    /// The default instructions the custom profile carries until the owner
    /// edits them in Settings.
    public static let defaultCustomObjective =
        "Clean up the dictated text and return it ready to paste."

    /// `customObjective` replaces the custom profile's objective only; every
    /// other profile ignores it, so prompt assembly still never branches on
    /// profile identity.
    public static func profile(
        _ id: SemanticProfileID,
        customObjective: String? = nil
    ) -> SemanticProfile {
        switch id {
        case .verbatim:
            return verbatim
        case .clarity:
            return clarity
        case .coding:
            return coding
        case .custom:
            var profile = custom
            let objective = customObjective?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ) ?? ""
            if !objective.isEmpty {
                profile.objective = objective
            }
            return profile
        }
    }

    private static let verbatim = SemanticProfile(
        id: .verbatim,
        name: "Verbatim",
        objective: "Preserve the dictated text with minimal cleanup: fix only obvious "
            + "recognition artifacts such as capitalization, punctuation, and disfluency, "
            + "without changing wording, order, or meaning.",
        structure: [],
        allowed: [
            "Correct obvious mis-transcriptions",
            "Normalize capitalization and punctuation",
            "Remove filler words and false starts",
        ],
        forbidden: [
            "Rewording or paraphrasing",
            "Restructuring or reordering sentences",
            "Adding, omitting, or summarizing information",
        ]
    )

    private static let clarity = SemanticProfile(
        id: .clarity,
        name: "Clarity",
        objective: "Rewrite the dictated text as readable prose: repair grammar and "
            + "disfluency, restructure sentences for flow, and resolve repetitions while "
            + "preserving every fact, name, and technical detail exactly.",
        structure: [],
        allowed: [
            "Fix grammar, punctuation, and capitalization",
            "Merge and reorder sentences for flow",
            "Expand telegraphic dictation into complete sentences",
        ],
        forbidden: [
            "Changing meaning or intent",
            "Inventing facts or details not dictated",
            "Altering numbers, percentages, URLs, identifiers, or code",
        ]
    )

    /// The owner's own profile. Only the objective is theirs; the transducer
    /// constraints and the JSON contract still apply, so a custom prompt can
    /// change how the text is rewritten but not what the app receives back.
    private static let custom = SemanticProfile(
        id: .custom,
        name: "Custom",
        objective: defaultCustomObjective,
        structure: [],
        allowed: [],
        forbidden: []
    )

    private static let coding = SemanticProfile(
        id: .coding,
        name: "Coding",
        objective: "Restructure the dictated text into a structured technical brief with "
            + "one section per structure entry; record information that was not dictated "
            + "as an open question instead of inventing it.",
        structure: [
            "Goal",
            "Context",
            "Requirements",
            "Constraints",
            "Acceptance criteria",
            "Open questions",
        ],
        allowed: [
            "Group dictated statements under the matching section",
            "Convert instructions into requirement phrasing",
            "Record missing information as open questions",
        ],
        forbidden: [
            "Inventing requirements, constraints, or acceptance criteria",
            "Discarding dictated technical details",
            "Answering open questions from outside the dictation",
        ]
    )
}
