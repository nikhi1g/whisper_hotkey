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
        if let after = surroundingText?.afterSelection?.first {
            if let last = insertion.last,
               needsSpace(between: last, and: after) {
                insertion.append(" ")
            }
        } else {
            // An opaque context or an insertion at the end of a field cannot
            // expose a following character. Keep consecutive dictations and
            // subsequent typing naturally separated with exactly one space.
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
public protocol ReturnKeyPosting: AnyObject {
    func postReturn() -> Bool
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

@MainActor
public final class CGReturnKeyPoster: ReturnKeyPosting {
    public init() {}

    public func postReturn() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let events = Self.makeEvents(source: source)
        else {
            return false
        }
        events.keyDown.post(tap: .cghidEventTap)
        events.keyUp.post(tap: .cghidEventTap)
        return true
    }

    static func makeEvents(
        source: CGEventSource
    ) -> (keyDown: CGEvent, keyUp: CGEvent)? {
        guard let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(MacVirtualKey.returnKey),
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(MacVirtualKey.returnKey),
                keyDown: false
              )
        else {
            return nil
        }

        // `combinedSessionState` may contain a physically held or recently
        // latched dictation modifier. Send means plain Return regardless of
        // that source state; Chrome, for example, gives Option-Return and
        // Command-Return different navigation behavior.
        keyDown.flags = []
        keyUp.flags = []
        return (keyDown, keyUp)
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
    private let returnKeyPoster: ReturnKeyPosting

    public init(
        clipboard: ClipboardTransactionController,
        pastePoster: CommandPastePosting = CGCommandPastePoster(),
        returnKeyPoster: ReturnKeyPosting = CGReturnKeyPoster()
    ) {
        self.clipboard = clipboard
        self.pastePoster = pastePoster
        self.returnKeyPoster = returnKeyPoster
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

    /// Posts an unmodified Return after a successful insertion. The caller
    /// controls the short delay required for the destination app to process
    /// the preceding paste.
    @discardableResult
    public func pressReturn() -> Bool {
        returnKeyPoster.postReturn()
    }
}
