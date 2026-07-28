import CoreGraphics
import Foundation
import WhisperHotkeyCore

public enum TextInsertionFormatter {
    public static func insertionText(
        transcript: String,
        surroundingText: SurroundingText?
    ) -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        var insertion = trimmed
        if let before = surroundingText?.beforeSelection?.last,
           let first = insertion.first,
           needsSpace(between: before, and: first)
        {
            insertion.insert(" ", at: insertion.startIndex)
        }
        if let last = insertion.last,
           let after = surroundingText?.afterSelection?.first,
           needsSpace(between: last, and: after)
        {
            insertion.append(" ")
        }
        return insertion
    }

    private static func needsSpace(between left: Character, and right: Character) -> Bool {
        guard !left.isWhitespace, !right.isWhitespace else {
            return false
        }
        guard !openingPunctuation.contains(left),
              !closingPunctuation.contains(right),
              !joiners.contains(left),
              !joiners.contains(right)
        else {
            return false
        }
        return true
    }

    private static let openingPunctuation: Set<Character> = [
        "(", "[", "{", "<", "“", "‘",
    ]
    private static let closingPunctuation: Set<Character> = [
        ".", ",", "!", "?", ";", ":", "%", ")", "]", "}", ">", "”", "’",
    ]
    private static let joiners: Set<Character> = [
        "'", "-", "/", "\\", "_", "@",
    ]
}

@MainActor
public protocol CommandPastePosting: AnyObject {
    func postCommandV() -> Bool
}

@MainActor
public final class CGCommandPastePoster: CommandPastePosting {
    public init() {}

    public func postCommandV() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(MacVirtualKey.v),
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(MacVirtualKey.v),
                keyDown: false
              )
        else {
            return false
        }

        for event in [keyDown, keyUp] {
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
        }
        return true
    }
}

public enum SystemDeliveryResult: Equatable, Sendable {
    case inserted
    case clipboardUnavailable
    case emptyTranscript
}

@MainActor
public final class TextDeliveryService {
    private let clipboard: ClipboardTransactionController
    private let pastePoster: CommandPastePosting

    public init(
        clipboard: ClipboardTransactionController,
        pastePoster: CommandPastePosting = CGCommandPastePoster()
    ) {
        self.clipboard = clipboard
        self.pastePoster = pastePoster
    }

    public func deliver(
        transcript: String,
        context: DictationInsertionContext?
    ) -> SystemDeliveryResult {
        let plainTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plainTranscript.isEmpty else {
            return .emptyTranscript
        }

        let insertion = TextInsertionFormatter.insertionText(
            transcript: plainTranscript,
            surroundingText: context?.surroundingText
        )
        guard !insertion.isEmpty else {
            return .emptyTranscript
        }
        guard clipboard.pasteTemporarily(
            insertion,
            postingPasteWith: {
                return pastePoster.postCommandV()
            }
        ) else {
            return .clipboardUnavailable
        }
        return .inserted
    }

    @discardableResult
    public func copyToClipboard(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        return clipboard.copy(trimmed)
    }
}
