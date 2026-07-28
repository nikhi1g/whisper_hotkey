@preconcurrency import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

public struct SurroundingText: Equatable, Sendable {
    public let beforeSelection: String?
    public let selectedText: String?
    public let afterSelection: String?

    public init(
        beforeSelection: String?,
        selectedText: String?,
        afterSelection: String?
    ) {
        self.beforeSelection = beforeSelection
        self.selectedText = selectedText
        self.afterSelection = afterSelection
    }
}

enum BoundedTextRead: Equatable {
    case value(String)
    case noValue
    case unavailable
}

enum SurroundingTextReader {
    static func read(
        selectionRange: NSRange,
        boundedText: (NSRange) -> BoundedTextRead,
        fullText: () -> String?,
        selectedText: () -> String?
    ) -> SurroundingText {
        if let bounded = readBounded(
            selectionRange: selectionRange,
            boundedText: boundedText
        ) {
            return bounded
        }

        if let value = fullText(),
           let selection = Range(selectionRange, in: value)
        {
            return SurroundingText(
                beforeSelection: value[..<selection.lowerBound].last.map(String.init),
                selectedText: String(value[selection]),
                afterSelection: value[selection.upperBound...].first.map(String.init)
            )
        }

        let beforeRange = NSRange(
            location: max(0, selectionRange.location - 1),
            length: selectionRange.location > 0 ? 1 : 0
        )
        let afterRange = NSRange(
            location: selectionRange.location + selectionRange.length,
            length: 1
        )
        return SurroundingText(
            beforeSelection: beforeRange.length == 0
                ? nil
                : boundedText(beforeRange).value,
            selectedText: selectedText(),
            afterSelection: boundedText(afterRange).value
        )
    }

    private static func readBounded(
        selectionRange: NSRange,
        boundedText: (NSRange) -> BoundedTextRead
    ) -> SurroundingText? {
        guard case let .value(selected) = boundedText(selectionRange) else {
            return nil
        }

        let before: String?
        if selectionRange.location == 0 {
            before = nil
        } else {
            let beforeRange = NSRange(
                location: selectionRange.location - 1,
                length: 1
            )
            guard case let .value(value) = boundedText(beforeRange) else {
                return nil
            }
            before = value
        }

        let afterRange = NSRange(
            location: selectionRange.location + selectionRange.length,
            length: 1
        )
        let after: String?
        switch boundedText(afterRange) {
        case .value(let value):
            after = value
        case .noValue:
            after = nil
        case .unavailable:
            return nil
        }

        return SurroundingText(
            beforeSelection: before,
            selectedText: selected,
            afterSelection: after
        )
    }
}

private extension BoundedTextRead {
    var value: String? {
        guard case let .value(value) = self else {
            return nil
        }
        return value
    }
}

public enum TargetTextMode: String, Equatable, Sendable {
    /// The element exposes a selection range, which must remain unchanged.
    case selectionAware
    /// A known editable text role accepts keyboard input but exposes no range.
    case opaque
    case unavailable
}

enum TargetEditabilityPolicy {
    /// Classifies an AX target without relying on application identity or
    /// localized descriptions. Opaque fallback is deliberately limited to the
    /// two standard text-entry roles.
    static func textMode(
        role: String?,
        subrole: String?,
        subroleIsReliable: Bool,
        isEnabled: Bool,
        selectionRange: NSRange?,
        selectionRangeIsReliable: Bool,
        selectionRangeIsSettable: Bool
    ) -> TargetTextMode {
        guard subroleIsReliable,
              selectionRangeIsReliable,
              isEnabled,
              let role,
              subrole != kAXSecureTextFieldSubrole
        else {
            return .unavailable
        }

        if selectionRange != nil,
           opaqueTextRoles.contains(role) || selectionRangeIsSettable
        {
            return .selectionAware
        }

        guard selectionRange == nil, opaqueTextRoles.contains(role) else {
            return .unavailable
        }
        return .opaque
    }

    private static let opaqueTextRoles: Set<String> = [
        kAXTextFieldRole,
        kAXTextAreaRole,
    ]
}

public struct CapturedTargetState: Equatable, Sendable {
    public let processIdentifier: pid_t
    public let role: String?
    public let subrole: String?
    public let textMode: TargetTextMode
    public let selectionRange: NSRange?
    public let isSecure: Bool
    public let surroundingText: SurroundingText?

    public init(
        processIdentifier: pid_t,
        role: String?,
        subrole: String?,
        textMode: TargetTextMode,
        selectionRange: NSRange?,
        isSecure: Bool,
        surroundingText: SurroundingText?
    ) {
        self.processIdentifier = processIdentifier
        self.role = role
        self.subrole = subrole
        self.textMode = textMode
        self.selectionRange = selectionRange
        self.isSecure = isSecure
        self.surroundingText = surroundingText
    }

    public init(
        processIdentifier: pid_t,
        selectionRange: NSRange?,
        isSecure: Bool,
        isEditable: Bool,
        surroundingText: SurroundingText?
    ) {
        self.init(
            processIdentifier: processIdentifier,
            role: nil,
            subrole: nil,
            textMode: isEditable ? .selectionAware : .unavailable,
            selectionRange: selectionRange,
            isSecure: isSecure,
            surroundingText: surroundingText
        )
    }

    public var isEditable: Bool {
        textMode != .unavailable
    }
}

public struct CurrentTargetState: Equatable, Sendable {
    public let processIdentifier: pid_t
    public let isSameElement: Bool
    public let role: String?
    public let subrole: String?
    public let textMode: TargetTextMode
    public let selectionRange: NSRange?
    public let isSecure: Bool
    public let surroundingText: SurroundingText?

    public init(
        processIdentifier: pid_t,
        isSameElement: Bool,
        role: String?,
        subrole: String?,
        textMode: TargetTextMode,
        selectionRange: NSRange?,
        isSecure: Bool,
        surroundingText: SurroundingText?
    ) {
        self.processIdentifier = processIdentifier
        self.isSameElement = isSameElement
        self.role = role
        self.subrole = subrole
        self.textMode = textMode
        self.selectionRange = selectionRange
        self.isSecure = isSecure
        self.surroundingText = surroundingText
    }

    public init(
        processIdentifier: pid_t,
        isSameElement: Bool,
        selectionRange: NSRange?,
        isSecure: Bool,
        isEditable: Bool,
        surroundingText: SurroundingText?
    ) {
        self.init(
            processIdentifier: processIdentifier,
            isSameElement: isSameElement,
            role: nil,
            subrole: nil,
            textMode: isEditable ? .selectionAware : .unavailable,
            selectionRange: selectionRange,
            isSecure: isSecure,
            surroundingText: surroundingText
        )
    }

    public var isEditable: Bool {
        textMode != .unavailable
    }
}

public enum TargetInvalidReason: String, Equatable, Sendable {
    case missing
    case focusChanged
    case secure
    case targetAttributesChanged
    case notEditable
    case selectionUnavailable
    case selectionChanged
    case surroundingTextChanged
}

public enum TargetValidationResult: Equatable, Sendable {
    case valid
    case invalid(TargetInvalidReason)
}

public enum TargetValidator {
    public static func validate(
        captured: CapturedTargetState,
        current: CurrentTargetState?
    ) -> TargetValidationResult {
        guard let current else {
            return .invalid(.missing)
        }
        guard captured.processIdentifier > 0,
              current.processIdentifier > 0,
              current.isSameElement,
              current.processIdentifier == captured.processIdentifier
        else {
            return .invalid(.focusChanged)
        }
        guard !captured.isSecure, !current.isSecure else {
            return .invalid(.secure)
        }
        guard captured.role == current.role,
              captured.subrole == current.subrole
        else {
            return .invalid(.targetAttributesChanged)
        }
        guard captured.textMode != .unavailable,
              current.textMode != .unavailable
        else {
            return .invalid(.notEditable)
        }
        guard captured.textMode == current.textMode else {
            return .invalid(.targetAttributesChanged)
        }
        guard captured.textMode == .selectionAware else {
            guard captured.selectionRange == nil,
                  current.selectionRange == nil,
                  TargetEditabilityPolicy.textMode(
                    role: captured.role,
                    subrole: captured.subrole,
                    subroleIsReliable: true,
                    isEnabled: true,
                    selectionRange: nil,
                    selectionRangeIsReliable: true,
                    selectionRangeIsSettable: false
                  ) == .opaque,
                  TargetEditabilityPolicy.textMode(
                    role: current.role,
                    subrole: current.subrole,
                    subroleIsReliable: true,
                    isEnabled: true,
                    selectionRange: nil,
                    selectionRangeIsReliable: true,
                    selectionRangeIsSettable: false
                  ) == .opaque
            else {
                return .invalid(.targetAttributesChanged)
            }
            return .valid
        }
        guard let capturedRange = captured.selectionRange,
              let currentRange = current.selectionRange
        else {
            return .invalid(.selectionUnavailable)
        }
        guard capturedRange == currentRange else {
            return .invalid(.selectionChanged)
        }
        if let capturedText = captured.surroundingText {
            guard let currentText = current.surroundingText,
                  capturedText == currentText
            else {
                return .invalid(.surroundingTextChanged)
            }
        }
        return .valid
    }
}

/// A release-time target contains a live AXUIElement and therefore remains
/// main-actor isolated. It is intentionally not wrapped in unchecked Sendable.
@MainActor
public final class ReleaseTarget {
    public let state: CapturedTargetState
    /// AppKit global screen coordinates.
    public let caretRect: CGRect?
    /// AppKit global screen coordinates.
    public let fieldRect: CGRect?

    fileprivate let element: AXUIElement

    fileprivate init(
        element: AXUIElement,
        state: CapturedTargetState,
        caretRect: CGRect?,
        fieldRect: CGRect?
    ) {
        self.element = element
        self.state = state
        self.caretRect = caretRect
        self.fieldRect = fieldRect
    }

    public var badgeAnchorRect: CGRect? {
        caretRect ?? fieldRect
    }
}

public struct BadgeAnchorGeometry: Equatable, Sendable {
    public let caretRect: CGRect?
    public let fieldRect: CGRect?

    public init(caretRect: CGRect?, fieldRect: CGRect?) {
        self.caretRect = caretRect
        self.fieldRect = fieldRect
    }
}

enum BadgeAnchorResolver {
    static func resolve(caretRect: CGRect?) -> BadgeAnchorGeometry {
        if let caret = usable(caretRect) {
            return BadgeAnchorGeometry(caretRect: caret, fieldRect: nil)
        }
        return BadgeAnchorGeometry(caretRect: nil, fieldRect: nil)
    }

    private static func usable(_ rect: CGRect?) -> CGRect? {
        guard let rect,
              !rect.isNull,
              !rect.isInfinite,
              rect.width >= 0,
              rect.height >= 0,
              rect.width > 0 || rect.height > 0
        else {
            return nil
        }
        return rect.standardized
    }
}

@MainActor
public final class AccessibilityTargetProvider {
    public init() {}

    /// Returns current caret and field geometry without retaining a
    /// cross-process accessibility object. Chromium-family editors commonly
    /// expose caret bounds through text markers rather than AXSelectedTextRange,
    /// so both representations are tried. No approximate field, pointer, or
    /// screen-corner anchor is returned.
    public func currentBadgeAnchor() -> BadgeAnchorGeometry {
        guard let element = focusedElement() else {
            return BadgeAnchorResolver.resolve(caretRect: nil)
        }
        AXUIElementSetMessagingTimeout(element, 0.15)
        let selection = copyRange(
            element,
            attribute: kAXSelectedTextRangeAttribute
        )
        let caretRect = copyCaretRect(
            element,
            selectionRange: selection
        ).flatMap(appKitScreenRect)
        return BadgeAnchorResolver.resolve(caretRect: caretRect)
    }

    public func captureFocusedTarget() -> ReleaseTarget? {
        guard let element = focusedElement() else {
            return nil
        }
        let captured = inspect(element)
        return ReleaseTarget(
            element: element,
            state: captured.state,
            caretRect: captured.caretRect,
            fieldRect: captured.fieldRect
        )
    }

    public func validate(_ target: ReleaseTarget) -> TargetValidationResult {
        guard let focused = focusedElement() else {
            return .invalid(.missing)
        }
        let current = inspect(focused).state
        return TargetValidator.validate(
            captured: target.state,
            current: CurrentTargetState(
                processIdentifier: current.processIdentifier,
                isSameElement: CFEqual(target.element, focused),
                role: current.role,
                subrole: current.subrole,
                textMode: current.textMode,
                selectionRange: current.selectionRange,
                isSecure: current.isSecure,
                surroundingText: current.surroundingText
            )
        )
    }

    private func focusedElement() -> AXUIElement? {
        if let processIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           processIdentifier > 0
        {
            let application = AXUIElementCreateApplication(processIdentifier)
            AXUIElementSetMessagingTimeout(application, 0.15)
            if let focused = copyFocusedElement(application) {
                return focused
            }
        }

        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.15)
        return copyFocusedElement(systemWide)
    }

    private func inspect(_ element: AXUIElement) -> Inspection {
        AXUIElementSetMessagingTimeout(element, 0.15)

        var processIdentifier: pid_t = 0
        let hasValidProcess = AXUIElementGetPid(element, &processIdentifier) == .success
            && processIdentifier > 0

        let role = copyString(element, attribute: kAXRoleAttribute)
        let subroleRead = copyOptionalString(
            element,
            attribute: kAXSubroleAttribute
        )
        let subrole = subroleRead.value
        let isSecure = subrole == kAXSecureTextFieldSubrole
        let enabledRead = copyOptionalBool(element, attribute: kAXEnabledAttribute)
        let isEnabled = enabledRead.isReliable
            ? enabledRead.value ?? true
            : false
        let selectionRangeRead = isSecure
            ? (value: nil, isReliable: true)
            : copyOptionalRange(element, attribute: kAXSelectedTextRangeAttribute)
        let selectionRange = selectionRangeRead.value
        let selectionRangeIsSettable = selectionRange != nil
            && isAttributeSettable(element, attribute: kAXSelectedTextRangeAttribute)
        let textMode = hasValidProcess
            ? TargetEditabilityPolicy.textMode(
                role: role,
                subrole: subrole,
                subroleIsReliable: subroleRead.isReliable,
                isEnabled: isEnabled,
                selectionRange: selectionRange,
                selectionRangeIsReliable: selectionRangeRead.isReliable,
                selectionRangeIsSettable: selectionRangeIsSettable
            )
            : .unavailable
        let selectionContext = textMode == .selectionAware
            ? makeSurroundingText(element: element, selectionRange: selectionRange)
            : nil
        let accessibilityFieldRect = copyElementRect(element)
        let accessibilityCaretRect = isSecure
            ? nil
            : copyCaretRect(element, selectionRange: selectionRange)
        let primaryScreenFrame = NSScreen.screens.first?.frame
        let fieldRect = accessibilityFieldRect.flatMap {
            appKitScreenRect($0, primaryScreenFrame: primaryScreenFrame)
        }
        let caretRect = accessibilityCaretRect.flatMap {
            appKitScreenRect($0, primaryScreenFrame: primaryScreenFrame)
        }

        return Inspection(
            state: CapturedTargetState(
                processIdentifier: processIdentifier,
                role: role,
                subrole: subrole,
                textMode: textMode,
                selectionRange: selectionRange,
                isSecure: isSecure,
                surroundingText: selectionContext
            ),
            caretRect: caretRect,
            fieldRect: fieldRect
        )
    }

    private func makeSurroundingText(
        element: AXUIElement,
        selectionRange: NSRange?
    ) -> SurroundingText? {
        guard let selectionRange else {
            return nil
        }
        return SurroundingTextReader.read(
            selectionRange: selectionRange,
            boundedText: {
                copyBoundedString(element, range: $0)
            },
            fullText: {
                copyString(element, attribute: kAXValueAttribute)
            },
            selectedText: {
                copyString(element, attribute: kAXSelectedTextAttribute)
            }
        )
    }

    private func copyCaretRect(
        _ element: AXUIElement,
        selectionRange: NSRange?
    ) -> CGRect? {
        if let selectionRange {
            let insertionLocation = selectionRange.location + selectionRange.length
            if let rect = copyBounds(
                element,
                range: NSRange(location: insertionLocation, length: 0)
            ) {
                return rect
            }
            if selectionRange.length > 0,
               let rect = copyBounds(element, range: selectionRange)
            {
                return rect
            }
        }
        return copyTextMarkerCaretRect(element)
    }

    private func appKitScreenRect(_ accessibilityRect: CGRect) -> CGRect? {
        appKitScreenRect(
            accessibilityRect,
            primaryScreenFrame: NSScreen.screens.first?.frame
        )
    }

    private func appKitScreenRect(
        _ accessibilityRect: CGRect,
        primaryScreenFrame: CGRect?
    ) -> CGRect? {
        guard let primaryScreenFrame else {
            return nil
        }
        return AccessibilityScreenCoordinates.appKitRect(
            from: accessibilityRect,
            primaryScreenFrame: primaryScreenFrame
        )
    }
}

private struct Inspection {
    let state: CapturedTargetState
    let caretRect: CGRect?
    let fieldRect: CGRect?
}

private let axFrameAttribute = "AXFrame"
private let axSelectedTextMarkerRangeAttribute = "AXSelectedTextMarkerRange"
private let axBoundsForTextMarkerRangeAttribute = "AXBoundsForTextMarkerRange"

private func copyFocusedElement(_ root: AXUIElement) -> AXUIElement? {
    guard let value = copyAttribute(
        root,
        attribute: kAXFocusedUIElementAttribute
    ),
    CFGetTypeID(value) == AXUIElementGetTypeID()
    else {
        return nil
    }
    return unsafeDowncast(value, to: AXUIElement.self)
}

private func copyAttribute(
    _ element: AXUIElement,
    attribute: String
) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
        element,
        attribute as CFString,
        &value
    ) == .success else {
        return nil
    }
    return value
}

private func copyString(
    _ element: AXUIElement,
    attribute: String
) -> String? {
    copyAttribute(element, attribute: attribute) as? String
}

private func copyOptionalString(
    _ element: AXUIElement,
    attribute: String
) -> (value: String?, isReliable: Bool) {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(
        element,
        attribute as CFString,
        &value
    )
    switch error {
    case .success:
        guard let string = value as? String else {
            return (nil, false)
        }
        return (string, true)
    case .noValue, .attributeUnsupported:
        return (nil, true)
    default:
        return (nil, false)
    }
}

private func copyOptionalBool(
    _ element: AXUIElement,
    attribute: String
) -> (value: Bool?, isReliable: Bool) {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(
        element,
        attribute as CFString,
        &value
    )
    switch error {
    case .success:
        guard let bool = value as? Bool else {
            return (nil, false)
        }
        return (bool, true)
    case .noValue, .attributeUnsupported:
        return (nil, true)
    default:
        return (nil, false)
    }
}

private func copyRange(
    _ element: AXUIElement,
    attribute: String
) -> NSRange? {
    copyOptionalRange(element, attribute: attribute).value
}

private func copyOptionalRange(
    _ element: AXUIElement,
    attribute: String
) -> (value: NSRange?, isReliable: Bool) {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(
        element,
        attribute as CFString,
        &value
    )
    switch error {
    case .noValue, .attributeUnsupported:
        return (nil, true)
    case .success:
        break
    default:
        return (nil, false)
    }
    guard let value,
          CFGetTypeID(value) == AXValueGetTypeID()
    else {
        return (nil, false)
    }
    let axValue = unsafeDowncast(value, to: AXValue.self)
    guard AXValueGetType(axValue) == .cfRange else {
        return (nil, false)
    }
    var range = CFRange()
    guard AXValueGetValue(axValue, .cfRange, &range),
          range.location >= 0,
          range.length >= 0
    else {
        return (nil, false)
    }
    return (
        NSRange(location: range.location, length: range.length),
        true
    )
}

private func copyElementRect(_ element: AXUIElement) -> CGRect? {
    if let value = copyAttribute(element, attribute: axFrameAttribute),
       let frame = copyRect(from: value)
    {
        return frame
    }
    guard let position = copyPoint(element, attribute: kAXPositionAttribute),
          let size = copySize(element, attribute: kAXSizeAttribute)
    else {
        return nil
    }
    return CGRect(origin: position, size: size)
}

private func copyPoint(
    _ element: AXUIElement,
    attribute: String
) -> CGPoint? {
    guard let value = copyAttribute(element, attribute: attribute),
          CFGetTypeID(value) == AXValueGetTypeID()
    else {
        return nil
    }
    let axValue = unsafeDowncast(value, to: AXValue.self)
    guard AXValueGetType(axValue) == .cgPoint else {
        return nil
    }
    var point = CGPoint.zero
    return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
}

private func copySize(
    _ element: AXUIElement,
    attribute: String
) -> CGSize? {
    guard let value = copyAttribute(element, attribute: attribute),
          CFGetTypeID(value) == AXValueGetTypeID()
    else {
        return nil
    }
    let axValue = unsafeDowncast(value, to: AXValue.self)
    guard AXValueGetType(axValue) == .cgSize else {
        return nil
    }
    var size = CGSize.zero
    return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
}

private func copyTextMarkerCaretRect(_ element: AXUIElement) -> CGRect? {
    var candidate: AXUIElement? = element
    for _ in 0..<6 {
        guard let current = candidate else {
            break
        }
        AXUIElementSetMessagingTimeout(current, 0.08)
        if let markerRange = copyAttribute(
            current,
            attribute: axSelectedTextMarkerRangeAttribute
        ),
        let rect = copyParameterizedRect(
            current,
            attribute: axBoundsForTextMarkerRangeAttribute,
            parameter: markerRange
        ) {
            return rect
        }

        guard let parentValue = copyAttribute(
            current,
            attribute: kAXParentAttribute
        ),
        CFGetTypeID(parentValue) == AXUIElementGetTypeID()
        else {
            break
        }
        let parent = unsafeDowncast(parentValue, to: AXUIElement.self)
        guard !CFEqual(parent, current) else {
            break
        }
        candidate = parent
    }
    return nil
}

private func isAttributeSettable(
    _ element: AXUIElement,
    attribute: String
) -> Bool {
    var settable = DarwinBoolean(false)
    guard AXUIElementIsAttributeSettable(
        element,
        attribute as CFString,
        &settable
    ) == .success else {
        return false
    }
    return settable.boolValue
}

private func copyBoundedString(
    _ element: AXUIElement,
    range: NSRange
) -> BoundedTextRead {
    var cfRange = CFRange(location: range.location, length: range.length)
    guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
        return .unavailable
    }
    var value: CFTypeRef?
    let error = AXUIElementCopyParameterizedAttributeValue(
        element,
        kAXStringForRangeParameterizedAttribute as CFString,
        rangeValue,
        &value
    )
    switch error {
    case .success:
        guard let string = value as? String else {
            return .unavailable
        }
        return .value(string)
    case .noValue:
        return .noValue
    default:
        return .unavailable
    }
}

private func copyBounds(
    _ element: AXUIElement,
    range: NSRange
) -> CGRect? {
    var cfRange = CFRange(location: range.location, length: range.length)
    guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
        return nil
    }
    var value: CFTypeRef?
    guard AXUIElementCopyParameterizedAttributeValue(
        element,
        kAXBoundsForRangeParameterizedAttribute as CFString,
        rangeValue,
        &value
    ) == .success,
    let value
    else {
        return nil
    }
    return copyRect(from: value)
}

private func copyParameterizedRect(
    _ element: AXUIElement,
    attribute: String,
    parameter: CFTypeRef
) -> CGRect? {
    var value: CFTypeRef?
    guard AXUIElementCopyParameterizedAttributeValue(
        element,
        attribute as CFString,
        parameter,
        &value
    ) == .success,
    let value
    else {
        return nil
    }
    return copyRect(from: value)
}

private func copyRect(from value: CFTypeRef) -> CGRect? {
    guard CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }
    let axValue = unsafeDowncast(value, to: AXValue.self)
    guard AXValueGetType(axValue) == .cgRect else {
        return nil
    }
    var rect = CGRect.zero
    return AXValueGetValue(axValue, .cgRect, &rect) ? rect : nil
}
