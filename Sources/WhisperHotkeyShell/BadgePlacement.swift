import CoreGraphics

enum BadgeRuntimeAnchor: Equatable {
    case accessibility(CGRect)
    case pointer(CGPoint)

    var frame: CGRect {
        switch self {
        case let .accessibility(frame):
            frame
        case let .pointer(location):
            CGRect(origin: location, size: CGSize(width: 1, height: 1))
        }
    }
}

public enum BadgePlacement {
    public static let defaultSize = CGSize(width: 132, height: 34)
    static let maximumCaretToFieldTopDistance: CGFloat = 120
    static let maximumStandaloneFieldHeight: CGFloat = 320

    /// Prefers exact Accessibility geometry and otherwise snapshots the pointer
    /// as a one-point anchor. The caller decides when pointer fallback is
    /// appropriate; this function performs no polling or target validation.
    public static func runtimeAnchor(
        caretFrame: CGRect?,
        fieldFrame: CGRect?,
        pointerLocation: CGPoint
    ) -> CGRect {
        resolvedRuntimeAnchor(
            caretFrame: caretFrame,
            fieldFrame: fieldFrame,
            pointerLocation: pointerLocation
        ).frame
    }

    static func resolvedRuntimeAnchor(
        caretFrame: CGRect?,
        fieldFrame: CGRect?,
        pointerLocation: CGPoint
    ) -> BadgeRuntimeAnchor {
        if let caret = usable(caretFrame) {
            return .accessibility(caret)
        }
        if let field = usable(fieldFrame),
           field.height <= maximumStandaloneFieldHeight
        {
            return .accessibility(field)
        }
        return .pointer(pointerLocation)
    }

    /// Uses a focused field only when its top edge remains local to the caret.
    /// Terminal apps often expose the entire terminal surface as the focused
    /// field; treating that as a text box would strand the badge at the top of
    /// the window, far from the active prompt.
    public static func frame(
        caretFrame: CGRect?,
        fieldFrame: CGRect?,
        screenFrame: CGRect,
        badgeSize: CGSize = defaultSize,
        gap: CGFloat = 8,
        screenInset: CGFloat = 8
    ) -> CGRect {
        let visibleFrame = screenFrame.standardized
        let size = CGSize(
            width: min(max(0, badgeSize.width), max(0, visibleFrame.width - (screenInset * 2))),
            height: min(max(0, badgeSize.height), max(0, visibleFrame.height - (screenInset * 2)))
        )

        guard size.width > 0, size.height > 0 else {
            return CGRect(origin: visibleFrame.origin, size: .zero)
        }

        let anchor = placementAnchor(
            caretFrame: caretFrame,
            fieldFrame: fieldFrame
        )
        var origin: CGPoint

        if let anchor {
            origin = CGPoint(
                x: anchor.minX,
                y: anchor.maxY + gap
            )

            if origin.y + size.height > visibleFrame.maxY - screenInset {
                origin.y = anchor.minY - gap - size.height
            }
        } else {
            origin = CGPoint(
                x: visibleFrame.maxX - screenInset - size.width,
                y: visibleFrame.minY + screenInset
            )
        }

        let minimumX = visibleFrame.minX + screenInset
        let maximumX = max(minimumX, visibleFrame.maxX - screenInset - size.width)
        let minimumY = visibleFrame.minY + screenInset
        let maximumY = max(minimumY, visibleFrame.maxY - screenInset - size.height)

        origin.x = min(max(origin.x, minimumX), maximumX)
        origin.y = min(max(origin.y, minimumY), maximumY)
        return CGRect(origin: origin, size: size)
    }

    private static func placementAnchor(
        caretFrame: CGRect?,
        fieldFrame: CGRect?
    ) -> CGRect? {
        let caret = usable(caretFrame)
        guard let field = usable(fieldFrame) else {
            return caret
        }
        guard let caret else {
            return field.height <= maximumStandaloneFieldHeight
                ? field
                : nil
        }

        let caretMidpoint = CGPoint(x: caret.midX, y: caret.midY)
        let containsCaret = field.insetBy(dx: -2, dy: -2)
            .contains(caretMidpoint)
        let caretToFieldTop = field.maxY - caret.maxY
        guard
            containsCaret,
            caretToFieldTop >= -2,
            caretToFieldTop <= maximumCaretToFieldTopDistance
        else {
            return caret
        }
        return field
    }

    /// Reuses a session's initial panel origin while adapting to a new badge
    /// size. Clamping is retained so a status-size change cannot cross the
    /// visible screen bounds.
    public static func frame(
        preservingOrigin origin: CGPoint,
        screenFrame: CGRect,
        badgeSize: CGSize,
        screenInset: CGFloat = 8
    ) -> CGRect {
        let visibleFrame = screenFrame.standardized
        let size = CGSize(
            width: min(max(0, badgeSize.width), max(0, visibleFrame.width - (screenInset * 2))),
            height: min(max(0, badgeSize.height), max(0, visibleFrame.height - (screenInset * 2)))
        )

        guard size.width > 0, size.height > 0 else {
            return CGRect(origin: visibleFrame.origin, size: .zero)
        }

        let minimumX = visibleFrame.minX + screenInset
        let maximumX = max(minimumX, visibleFrame.maxX - screenInset - size.width)
        let minimumY = visibleFrame.minY + screenInset
        let maximumY = max(minimumY, visibleFrame.maxY - screenInset - size.height)
        return CGRect(
            x: min(max(origin.x, minimumX), maximumX),
            y: min(max(origin.y, minimumY), maximumY),
            width: size.width,
            height: size.height
        )
    }

    /// Places a chosen point inside the badge directly beneath the pointer.
    /// The caller supplies the interactive hotspot, such as the center of the
    /// Send button. Screen clamping remains authoritative at display edges.
    public static func frame(
        pointerLocation: CGPoint,
        badgeHotspot: CGPoint,
        screenFrame: CGRect,
        badgeSize: CGSize,
        screenInset: CGFloat = 8
    ) -> CGRect {
        let visibleFrame = screenFrame.standardized
        let size = CGSize(
            width: min(
                max(0, badgeSize.width),
                max(0, visibleFrame.width - (screenInset * 2))
            ),
            height: min(
                max(0, badgeSize.height),
                max(0, visibleFrame.height - (screenInset * 2))
            )
        )
        guard size.width > 0, size.height > 0 else {
            return CGRect(origin: visibleFrame.origin, size: .zero)
        }

        let hotspot = CGPoint(
            x: min(max(0, badgeHotspot.x), size.width),
            y: min(max(0, badgeHotspot.y), size.height)
        )
        let proposedOrigin = CGPoint(
            x: pointerLocation.x - hotspot.x,
            y: pointerLocation.y - hotspot.y
        )
        return frame(
            preservingOrigin: proposedOrigin,
            screenFrame: visibleFrame,
            badgeSize: size,
            screenInset: screenInset
        )
    }

    private static func usable(_ frame: CGRect?) -> CGRect? {
        guard let frame, !frame.isNull, !frame.isInfinite, frame.width >= 0, frame.height >= 0 else {
            return nil
        }
        return frame.standardized
    }
}
