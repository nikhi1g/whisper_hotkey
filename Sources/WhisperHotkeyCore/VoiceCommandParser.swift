import Foundation

public enum VoiceCommand: Equatable, Sendable {
    case setProfile(SemanticProfileID)
    case scratchLastSegment
    case send
    case cancel
    case showOriginal
}

/// Local, deterministic command table.  Matches run before any network call;
/// everything that is not an exact command is treated as content.
public enum VoiceCommandParser {
    public static func parse(_ text: String) -> VoiceCommand? {
        switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "mode clarity":
            return .setProfile(.clarity)
        case "mode verbatim", "verbatim mode":
            return .setProfile(.verbatim)
        case "mode coding":
            return .setProfile(.coding)
        case "scratch that":
            return .scratchLastSegment
        case "send":
            return .send
        case "cancel":
            return .cancel
        case "show original":
            return .showOriginal
        default:
            return nil
        }
    }
}
