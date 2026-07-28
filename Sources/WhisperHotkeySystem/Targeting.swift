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

public struct CapturedTargetState: Equatable, Sendable {
    public let processIdentifier: pid_t
    public let selectionRange: NSRange?
    public let isSecure: Bool
    public let isEditable: Bool
    public let surroundingText: SurroundingText?

    public init(
        processIdentifier: pid_t,
        selectionRange: NSRange?,
        isSecure: Bool,
        isEditable: Bool,
        surroundingText: SurroundingText?
    ) {
        self.processIdentifier = processIdentifier
        self.selectionRange = selectionRange
        self.isSecure = isSecure
        self.isEditable = isEditable
        self.surroundingText = surroundingText
    }
}

public struct CurrentTargetState: Equatable, Sendable {
    public let processIdentifier: pid_t
    public let isSameElement: Bool
    public let selectionRange: NSRange?
    public let isSecure: Bool
    public let isEditable: Bool
    public let surroundingText: SurroundingText?

    public init(
        processIdentifier: pid_t,
        isSameElement: Bool,
        selectionRange: NSRange?,
        isSecure: Bool,
        isEditable: Bool,
        surroundingText: SurroundingText?
    ) {
        self.processIdentifier = processIdentifier
        self.isSameElement = isSameElement
        self.selectionRange = selectionRange
        self.isSecure = isSecure
        self.isEditable = isEditable
        self.surroundingText = surroundingText
    }
}

public enum TargetInvalidReason: String, Equatable, Sendable {
    case missing
    case focusChanged
    case secure
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
        guard current.isSameElement,
              current.processIdentifier == captured.processIdentifier
        else {
            return .invalid(.focusChanged)
        }
        guard !captured.isSecure, !current.isSecure else {
            return .invalid(.secure)
        }
        guard captured.isEditable, current.isEditable else {
            return .invalid(.notEditable)
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

@MainActor
public final class AccessibilityTargetProvider {
    public init() {}

    /// Returns current caret geometry without retaining a cross-process
    /// accessibility object. This is suitable for positioning the listening
    /// badge at press time.
    public func currentBadgeAnchorRect() -> CGRect? {
        guard let element = focusedElement() else {
            return nil
        }
        AXUIElementSetMessagingTimeout(element, 0.15)
        if let selection = copyRange(
            element,
            attribute: kAXSelectedTextRangeAttribute
        ),
        let caretRect = copyCaretRect(element, selectionRange: selection),
        let appKitRect = appKitScreenRect(caretRect)
        {
            return appKitRect
        }
        return copyElementRect(element).flatMap(appKitScreenRect)
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
                selectionRange: current.selectionRange,
                isSecure: current.isSecure,
                isEditable: current.isEditable,
                surroundingText: current.surroundingText
            )
        )
    }

    private func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.15)
        guard let value = copyAttribute(
            systemWide,
            attribute: kAXFocusedUIElementAttribute
        ),
        CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func inspect(_ element: AXUIElement) -> Inspection {
        AXUIElementSetMessagingTimeout(element, 0.15)

        var processIdentifier: pid_t = 0
        AXUIElementGetPid(element, &processIdentifier)

        let subrole = copyString(element, attribute: kAXSubroleAttribute)
        let isSecure = subrole == kAXSecureTextFieldSubrole
        let isEnabled = copyBool(element, attribute: kAXEnabledAttribute) ?? true
        let selectionRange = isSecure ? nil : copyRange(
            element,
            attribute: kAXSelectedTextRangeAttribute
        )
        let isEditable = !isSecure
            && isEnabled
            && selectionRange != nil
            && isAttributeSettable(element, attribute: kAXSelectedTextRangeAttribute)
        let surroundingText = isSecure
            ? nil
            : makeSurroundingText(element: element, selectionRange: selectionRange)
        let accessibilityFieldRect = copyElementRect(element)
        let accessibilityCaretRect = selectionRange.flatMap {
            copyCaretRect(element, selectionRange: $0)
        }
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
                selectionRange: selectionRange,
                isSecure: isSecure,
                isEditable: isEditable,
                surroundingText: surroundingText
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
        if let value = copyString(element, attribute: kAXValueAttribute),
           let selection = Range(selectionRange, in: value)
        {
            let before = value[..<selection.lowerBound].last.map(String.init)
            let selected = String(value[selection])
            let after = value[selection.upperBound...].first.map(String.init)
            return SurroundingText(
                beforeSelection: before,
                selectedText: selected,
                afterSelection: after
            )
        }

        let selected = copyString(element, attribute: kAXSelectedTextAttribute)
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
                : copyString(element, range: beforeRange),
            selectedText: selected,
            afterSelection: copyString(element, range: afterRange)
        )
    }

    private func copyCaretRect(
        _ element: AXUIElement,
        selectionRange: NSRange
    ) -> CGRect? {
        let insertionLocation = selectionRange.location + selectionRange.length
        if let rect = copyBounds(
            element,
            range: NSRange(location: insertionLocation, length: 0)
        ) {
            return rect
        }
        guard selectionRange.length > 0 else {
            return nil
        }
        return copyBounds(element, range: selectionRange)
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

private func copyBool(
    _ element: AXUIElement,
    attribute: String
) -> Bool? {
    copyAttribute(element, attribute: attribute) as? Bool
}

private func copyRange(
    _ element: AXUIElement,
    attribute: String
) -> NSRange? {
    guard let value = copyAttribute(element, attribute: attribute),
          CFGetTypeID(value) == AXValueGetTypeID()
    else {
        return nil
    }
    let axValue = unsafeDowncast(value, to: AXValue.self)
    guard AXValueGetType(axValue) == .cfRange else {
        return nil
    }
    var range = CFRange()
    guard AXValueGetValue(axValue, .cfRange, &range),
          range.location >= 0,
          range.length >= 0
    else {
        return nil
    }
    return NSRange(location: range.location, length: range.length)
}

private func copyElementRect(_ element: AXUIElement) -> CGRect? {
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

private func copyString(
    _ element: AXUIElement,
    range: NSRange
) -> String? {
    var cfRange = CFRange(location: range.location, length: range.length)
    guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
        return nil
    }
    var value: CFTypeRef?
    guard AXUIElementCopyParameterizedAttributeValue(
        element,
        kAXStringForRangeParameterizedAttribute as CFString,
        rangeValue,
        &value
    ) == .success else {
        return nil
    }
    return value as? String
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
    let value,
    CFGetTypeID(value) == AXValueGetTypeID()
    else {
        return nil
    }
    let axValue = unsafeDowncast(value, to: AXValue.self)
    guard AXValueGetType(axValue) == .cgRect else {
        return nil
    }
    var rect = CGRect.zero
    return AXValueGetValue(axValue, .cgRect, &rect) ? rect : nil
}
