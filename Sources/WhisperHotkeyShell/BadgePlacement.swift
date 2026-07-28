import CoreGraphics

public enum BadgePlacement {
    public static let defaultSize = CGSize(width: 132, height: 34)

    /// Prefers exact Accessibility geometry and otherwise snapshots the pointer
    /// as a one-point anchor. The caller decides when pointer fallback is
    /// appropriate; this function performs no polling or target validation.
    public static func runtimeAnchor(
        caretFrame: CGRect?,
        fieldFrame: CGRect?,
        pointerLocation: CGPoint
    ) -> CGRect {
        usable(caretFrame)
            ?? usable(fieldFrame)
            ?? CGRect(
                origin: pointerLocation,
                size: CGSize(width: 1, height: 1)
            )
    }

    /// Computes placement for an available anchor while keeping the badge
    /// inside the supplied visible screen frame. Runtime status presentations
    /// pass either exact caret geometry or a one-point pointer fallback.
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

        let anchor = usable(caretFrame) ?? usable(fieldFrame)
        var origin: CGPoint

        if let anchor {
            origin = CGPoint(
                x: anchor.maxX + gap,
                y: anchor.midY - (size.height / 2)
            )

            if origin.x + size.width > visibleFrame.maxX - screenInset {
                origin.x = anchor.minX - gap - size.width
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

    private static func usable(_ frame: CGRect?) -> CGRect? {
        guard let frame, !frame.isNull, !frame.isInfinite, frame.width >= 0, frame.height >= 0 else {
            return nil
        }
        return frame.standardized
    }
}
