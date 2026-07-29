@preconcurrency import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

public struct SurroundingText: Equatable, Sendable {
    public let beforeSelection: String?
    public let afterSelection: String?

    public init(
        beforeSelection: String?,
        afterSelection: String?
    ) {
        self.beforeSelection = beforeSelection
        self.afterSelection = afterSelection
    }
}

/// Optional information used only for spacing and exact badge placement.
/// It contains no retained Accessibility object and is never validated.
public struct DictationInsertionContext: Equatable, Sendable {
    public let surroundingText: SurroundingText?
    public let caretRect: CGRect?

    public init(
        surroundingText: SurroundingText?,
        caretRect: CGRect?
    ) {
        self.surroundingText = surroundingText
        self.caretRect = caretRect
    }
}

public struct BadgeAnchorGeometry: Equatable, Sendable {
    public let caretRect: CGRect?
    public let fieldRect: CGRect?

    public init(caretRect: CGRect?, fieldRect: CGRect? = nil) {
        self.caretRect = caretRect
        self.fieldRect = fieldRect
    }
}

enum BadgeAnchorResolver {
    static func resolve(
        caretRect: CGRect?,
        fieldRect: CGRect? = nil
    ) -> BadgeAnchorGeometry {
        BadgeAnchorGeometry(
            caretRect: usable(caretRect),
            fieldRect: usable(fieldRect)
        )
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
public final class AccessibilityContextProvider {
    public init() {}

    /// Returns exact caret geometry only. Chromium-family editors commonly use
    /// text markers rather than AXSelectedTextRange, so both are attempted.
    public func currentBadgeAnchor() -> BadgeAnchorGeometry {
        guard let element = focusedElement() else {
            return BadgeAnchorResolver.resolve(caretRect: nil)
        }
        AXUIElementSetMessagingTimeout(element, 0.15)
        let selectionRange = copyRange(
            element,
            attribute: kAXSelectedTextRangeAttribute
        )
        let fieldRect = copyElementFrame(element)
        return BadgeAnchorResolver.resolve(
            caretRect: copyCaretRect(
                element,
                selectionRange: selectionRange
            ).flatMap(appKitScreenRect),
            fieldRect: fieldRect.flatMap(appKitScreenRect)
        )
    }

    /// Captures optional one-character boundaries and caret geometry. Missing
    /// or opaque Accessibility data never prevents the later Command-V.
    public func captureInsertionContext() -> DictationInsertionContext? {
        guard let element = focusedElement() else {
            return nil
        }
        return insertionContext(for: element)
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

    private func insertionContext(
        for element: AXUIElement
    ) -> DictationInsertionContext {
        AXUIElementSetMessagingTimeout(element, 0.15)
        let selectionRange = copyRange(
            element,
            attribute: kAXSelectedTextRangeAttribute
        )
        let surroundingText = selectionRange.map {
            boundaryText(element: element, selectionRange: $0)
        }
        let accessibilityCaretRect = copyCaretRect(
            element,
            selectionRange: selectionRange
        )
        return DictationInsertionContext(
            surroundingText: surroundingText,
            caretRect: accessibilityCaretRect.flatMap(appKitScreenRect)
        )
    }

    /// Reads at most one character on each side. It never fetches the control's
    /// entire value or the selected body.
    private func boundaryText(
        element: AXUIElement,
        selectionRange: NSRange
    ) -> SurroundingText {
        let before: String?
        if selectionRange.location == 0 {
            before = nil
        } else {
            before = copyBoundedString(
                element,
                range: NSRange(location: selectionRange.location - 1, length: 1)
            )
        }

        let after = copyBoundedString(
            element,
            range: NSRange(
                location: selectionRange.location + selectionRange.length,
                length: 1
            )
        )
        return SurroundingText(
            beforeSelection: before,
            afterSelection: after
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
        guard let primaryScreenFrame = NSScreen.screens.first?.frame else {
            return nil
        }
        return AccessibilityScreenCoordinates.appKitRect(
            from: accessibilityRect,
            primaryScreenFrame: primaryScreenFrame
        )
    }
}

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

private func copyBoundedString(
    _ element: AXUIElement,
    range: NSRange
) -> String? {
    var cfRange = CFRange(location: range.location, length: range.length)
    guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
        return nil
    }
    var value: CFTypeRef?
    let error = AXUIElementCopyParameterizedAttributeValue(
        element,
        kAXStringForRangeParameterizedAttribute as CFString,
        rangeValue,
        &value
    )
    guard error == .success else {
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

private func copyElementFrame(_ element: AXUIElement) -> CGRect? {
    guard
        let positionValue = copyAttribute(
            element,
            attribute: kAXPositionAttribute
        ),
        let sizeValue = copyAttribute(
            element,
            attribute: kAXSizeAttribute
        ),
        CFGetTypeID(positionValue) == AXValueGetTypeID(),
        CFGetTypeID(sizeValue) == AXValueGetTypeID()
    else {
        return nil
    }
    let positionAXValue = unsafeDowncast(positionValue, to: AXValue.self)
    let sizeAXValue = unsafeDowncast(sizeValue, to: AXValue.self)
    guard
        AXValueGetType(positionAXValue) == .cgPoint,
        AXValueGetType(sizeAXValue) == .cgSize
    else {
        return nil
    }
    var origin = CGPoint.zero
    var size = CGSize.zero
    guard
        AXValueGetValue(positionAXValue, .cgPoint, &origin),
        AXValueGetValue(sizeAXValue, .cgSize, &size)
    else {
        return nil
    }
    return CGRect(origin: origin, size: size)
}
