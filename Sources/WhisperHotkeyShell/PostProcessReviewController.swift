@preconcurrency import CoreGraphics
import AppKit
import WhisperHotkeyCore

/// The user's decision on a presented review.  The only callback the review
/// controller delivers; the App integration owns every consequence of it.
public enum ReviewChoice: Equatable, Sendable {
    case acceptProcessed
    case restoreRaw
    case cancel
}

/// The four key gestures the review surface responds to, mapped from
/// physical key codes before any processing-state logic applies.
enum PostProcessReviewKeyAction: Equatable {
    case acceptProcessed
    case restoreRaw
    case cancel
    case cycleProfile
}

enum PostProcessReviewKeyMapping {
    static func action(
        forKeyCode keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> PostProcessReviewKeyAction? {
        let independent = modifiers.intersection(.deviceIndependentFlagsMask)
        switch keyCode {
        case 36, 76:
            // Return and keypad Enter.
            return .acceptProcessed
        case 53:
            // Escape.
            return .cancel
        case 48 where !independent.contains(.command):
            // Tab.  Command-Tab stays the system application switcher.
            return .cycleProfile
        case 6 where independent.contains(.command)
            && !independent.contains(.shift):
            // Command-Z.  Command-Shift-Z stays the destination's redo.
            return .restoreRaw
        default:
            return nil
        }
    }
}

enum PostProcessReviewProfileCycle {
    /// Declaration order: verbatim, clarity, coding.  Cycling walks this
    /// order, so clarity → coding → verbatim → clarity.
    static let order: [SemanticProfileID] = SemanticProfileID.allCases

    static func next(after profile: SemanticProfileID) -> SemanticProfileID {
        guard let index = order.firstIndex(of: profile) else {
            return order[0]
        }
        return order[(index + 1) % order.count]
    }
}

/// Everything the badge needs to render one review, derived from the preview
/// without touching the processor or the network.
struct PostProcessReviewContent: Equatable {
    let rawText: String
    let processedText: String?
    let riskText: String?
    let risk: MeaningChangeRisk?
    let footerText: String?
    let unavailable: Bool
}

enum PostProcessReviewRendering {
    static func content(
        for preview: PostProcessPreview
    ) -> PostProcessReviewContent {
        guard let processed = preview.processed else {
            return PostProcessReviewContent(
                rawText: preview.rawText,
                processedText: nil,
                riskText: nil,
                risk: nil,
                footerText: nil,
                unavailable: true
            )
        }
        var footerParts: [String] = []
        if !preview.report.issues.isEmpty {
            footerParts.append(
                "Not preserved: \(preview.report.issues.joined(separator: ", "))"
            )
        }
        if !processed.explicitCorrections.isEmpty {
            footerParts.append(
                "Corrected: \(processed.explicitCorrections.joined(separator: "; "))"
            )
        }
        return PostProcessReviewContent(
            rawText: preview.rawText,
            processedText: processed.finalText,
            riskText: "Meaning change risk: \(processed.meaningChangeRisk.displayName)",
            risk: processed.meaningChangeRisk,
            footerText: footerParts.isEmpty
                ? nil
                : footerParts.joined(separator: " · "),
            unavailable: false
        )
    }
}

private extension MeaningChangeRisk {
    var displayName: String {
        switch self {
        case .low:
            "Low"
        case .medium:
            "Medium"
        case .high:
            "High"
        }
    }
}

/// Drives the review presentation on the existing badge.  Owns no processing
/// logic and no network access: it renders previews, maps the review keys,
/// and delivers exactly one `ReviewChoice` through the accept closure.
@MainActor
public final class PostProcessReviewController {
    private let badge: CaretBadgeController
    private var currentPreview: PostProcessPreview?
    private var currentProfile: SemanticProfileID = .clarity
    private var acceptHandler: ((PostProcessPreview, ReviewChoice) -> Void)?
    private var profileChangeHandler: ((SemanticProfileID) -> Void)?
    private var keyTap: ReviewKeyTap?

    public init(badge: CaretBadgeController) {
        self.badge = badge
    }

    var isPresenting: Bool {
        currentPreview != nil
    }

    /// Presents the review on the existing badge panel and intercepts the
    /// review keys until a choice is delivered or `dismiss()` is called.
    ///
    /// Re-presenting (a Tab-driven profile change reprocess) updates the
    /// content in place without replacing the panel or the key interception;
    /// the panel size is fixed for the whole review session.
    public func present(
        _ preview: PostProcessPreview,
        accept: @escaping (PostProcessPreview, ReviewChoice) -> Void,
        onProfileChange: @escaping (SemanticProfileID) -> Void
    ) {
        currentPreview = preview
        currentProfile = preview.profile
        acceptHandler = accept
        profileChangeHandler = onProfileChange
        badge.presentReview(preview)
        if keyTap == nil {
            let tap = ReviewKeyTap { [weak self] keyCode, modifiers in
                self?.handleKeyDown(
                    keyCode: keyCode,
                    modifiers: modifiers
                ) ?? false
            }
            tap.start()
            keyTap = tap
        }
    }

    /// Hides the review without delivering a choice.
    public func dismiss() {
        tearDown()
        badge.hide()
    }

    /// Consumes a key-down when it maps to a review gesture while a review is
    /// presented.  Called from the key tap and directly by tests.
    func handleKeyDown(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        guard isPresenting,
              let action = PostProcessReviewKeyMapping.action(
                  forKeyCode: keyCode,
                  modifiers: modifiers
              )
        else {
            return false
        }
        switch action {
        case .acceptProcessed:
            deliver(.acceptProcessed)
        case .restoreRaw:
            deliver(.restoreRaw)
        case .cancel:
            deliver(.cancel)
        case .cycleProfile:
            cycleProfile()
        }
        return true
    }

    private func cycleProfile() {
        let next = PostProcessReviewProfileCycle.next(after: currentProfile)
        currentProfile = next
        profileChangeHandler?(next)
    }

    private func deliver(_ choice: ReviewChoice) {
        guard let preview = currentPreview else {
            return
        }
        // Raw is the only honest acceptance when there is nothing processed.
        let resolved = choice == .acceptProcessed && preview.processed == nil
            ? .restoreRaw
            : choice
        let handler = acceptHandler
        tearDown()
        badge.hide()
        handler?(preview, resolved)
    }

    private func tearDown() {
        keyTap?.stop()
        keyTap = nil
        currentPreview = nil
        acceptHandler = nil
        profileChangeHandler = nil
    }
}

/// System-wide key-down interception that exists only while a review is
/// presented.  A disabled feature never creates one.  The tap runs on the
/// main run loop thread, so consumption is decided synchronously against
/// controller state.
@MainActor
private final class ReviewKeyTap {
    typealias Handler = (UInt16, NSEvent.ModifierFlags) -> Bool

    private let handler: Handler
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func start() {
        guard eventTap == nil else {
            return
        }
        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: reviewKeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            // Missing listen-event permission or a competing tap: the review
            // still renders and can still be dismissed; keys pass through.
            return
        }
        guard let source = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            tap,
            0
        ) else {
            CFMachPortInvalidate(tap)
            return
        }
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
    }

    func shouldConsumeEvent(
        type: CGEventType,
        event: CGEvent
    ) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return false
        }
        guard type == .keyDown,
              event.getIntegerValueField(.keyboardEventAutorepeat) == 0
        else {
            return false
        }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        // CGEventFlags and NSEvent.ModifierFlags share bit positions for the
        // device-independent modifiers; only the low coalescing bit differs.
        let modifiers = NSEvent.ModifierFlags(
            rawValue: UInt(event.flags.rawValue)
        )
        return handler(keyCode, modifiers)
    }

    deinit {
        if let source = runLoopSource {
            CFRunLoopSourceInvalidate(source)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
    }
}

private func reviewKeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let ownerAddress = UInt(bitPattern: userInfo)
    let shouldConsume = MainActor.assumeIsolated {
        guard let ownerPointer = UnsafeMutableRawPointer(
            bitPattern: ownerAddress
        ) else {
            return false
        }
        let owner = Unmanaged<ReviewKeyTap>
            .fromOpaque(ownerPointer)
            .takeUnretainedValue()
        return owner.shouldConsumeEvent(
            type: type,
            event: event
        )
    }
    return shouldConsume ? nil : Unmanaged.passUnretained(event)
}
