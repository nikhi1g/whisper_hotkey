import CoreGraphics

/// Converts Accessibility/Quartz global screen rectangles (top-left origin,
/// positive y downward) into AppKit global screen rectangles (bottom-left
/// origin, positive y upward).
public enum AccessibilityScreenCoordinates {
    /// `primaryScreenFrame` must be the frame of `NSScreen.screens[0]`, the
    /// menu-bar display. A single global-axis flip handles every display,
    /// including displays arranged left of, above, or below the primary one.
    public static func appKitRect(
        from accessibilityRect: CGRect,
        primaryScreenFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: accessibilityRect.origin.x,
            y: primaryScreenFrame.maxY
                - accessibilityRect.origin.y
                - accessibilityRect.height,
            width: accessibilityRect.width,
            height: accessibilityRect.height
        )
    }
}
