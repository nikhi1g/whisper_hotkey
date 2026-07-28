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
            event.setIntegerValueField(
                .eventSourceUserData,
                value: GlobalHotkeyMonitor.syntheticEventMarker
            )
            event.post(tap: .cghidEventTap)
        }
        return true
    }
}

public enum SystemDeliveryResult: Equatable, Sendable {
    case inserted
    case clipboardLease(TargetInvalidReason)
    case clipboardLeaseAfterPasteFailure
    case clipboardUnavailable(TargetInvalidReason?)
    case emptyTranscript

    public var disposition: DeliveryDisposition? {
        switch self {
        case .inserted:
            .inserted
        case .clipboardLease, .clipboardLeaseAfterPasteFailure:
            .clipboardLease
        case .clipboardUnavailable, .emptyTranscript:
            nil
        }
    }
}

@MainActor
public final class TextDeliveryService {
    private let targetProvider: AccessibilityTargetProvider
    private let clipboard: ClipboardTransactionController
    private let pastePoster: CommandPastePosting

    public init(
        targetProvider: AccessibilityTargetProvider,
        clipboard: ClipboardTransactionController,
        pastePoster: CommandPastePosting = CGCommandPastePoster()
    ) {
        self.targetProvider = targetProvider
        self.clipboard = clipboard
        self.pastePoster = pastePoster
    }

    public func deliver(
        transcript: String,
        to target: ReleaseTarget?
    ) -> SystemDeliveryResult {
        let plainTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plainTranscript.isEmpty else {
            return .emptyTranscript
        }
        guard let target else {
            return clipboard.installLease(plainTranscript)
                ? .clipboardLease(.missing)
                : .clipboardUnavailable(.missing)
        }

        let validation = targetProvider.validate(target)
        guard validation == .valid else {
            let reason: TargetInvalidReason
            if case let .invalid(invalidReason) = validation {
                reason = invalidReason
            } else {
                reason = .missing
            }
            return clipboard.installLease(plainTranscript)
                ? .clipboardLease(reason)
                : .clipboardUnavailable(reason)
        }

        let insertion = TextInsertionFormatter.insertionText(
            transcript: plainTranscript,
            surroundingText: target.state.surroundingText
        )
        guard !insertion.isEmpty else {
            return .emptyTranscript
        }
        var validationBeforePost: TargetValidationResult = .valid
        guard clipboard.pasteTemporarily(
            insertion,
            postingPasteWith: {
                validationBeforePost = targetProvider.validate(target)
                guard validationBeforePost == .valid else {
                    return false
                }
                return pastePoster.postCommandV()
            }
        ) else {
            if case let .invalid(reason) = validationBeforePost {
                return clipboard.installLease(plainTranscript)
                    ? .clipboardLease(reason)
                    : .clipboardUnavailable(reason)
            }
            return clipboard.installLease(plainTranscript)
                ? .clipboardLeaseAfterPasteFailure
                : .clipboardUnavailable(nil)
        }
        return .inserted
    }

    public var clipboardLeaseActive: Bool {
        clipboard.isLeaseActive
    }

    public func cancelClipboardLease() {
        clipboard.cancelLease()
    }
}
