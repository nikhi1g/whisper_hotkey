import AppKit
import WhisperHotkeyCore

@MainActor
public final class CaretBadgeController {
    private let panel: NonactivatingBadgePanel
    private let badgeView: BadgeView

    public init() {
        badgeView = BadgeView(frame: CGRect(origin: .zero, size: BadgePlacement.defaultSize))
        panel = NonactivatingBadgePanel(
            contentRect: badgeView.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = badgeView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .transient,
        ]
        panel.isReleasedWhenClosed = false
    }

    public var isVisible: Bool {
        panel.isVisible
    }

    /// Presents a non-activating badge without changing the active application
    /// or key window. `screenFrame` should be an `NSScreen.visibleFrame` when
    /// the caller already knows which screen owns the Accessibility target.
    public func present(
        _ presentation: BadgePresentation,
        caretFrame: CGRect? = nil,
        fieldFrame: CGRect? = nil,
        screenFrame: CGRect? = nil
    ) {
        guard presentation != .hidden else {
            hide()
            return
        }

        badgeView.presentation = presentation
        let size = badgeView.preferredSize
        let anchor = caretFrame ?? fieldFrame
        let visibleFrame = screenFrame
            ?? screen(containing: anchor)?.visibleFrame
            ?? NSScreen.main?.visibleFrame

        guard let visibleFrame else {
            panel.orderOut(nil)
            return
        }

        panel.setFrame(
            BadgePlacement.frame(
                caretFrame: caretFrame,
                fieldFrame: fieldFrame,
                screenFrame: visibleFrame,
                badgeSize: size
            ),
            display: true
        )
        panel.orderFrontRegardless()
    }

    public func hide() {
        panel.orderOut(nil)
    }

    private func screen(containing frame: CGRect?) -> NSScreen? {
        guard let frame else {
            return nil
        }
        return NSScreen.screens.first(where: { $0.frame.intersects(frame) })
    }
}

private final class NonactivatingBadgePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class BadgeView: NSView {
    private let statusLabel = NSTextField(labelWithString: "")

    var presentation: BadgePresentation = .hidden {
        didSet {
            updatePresentation()
        }
    }

    var preferredSize: CGSize {
        let measuredWidth = ceil(statusLabel.intrinsicContentSize.width)
        return CGSize(width: min(max(116, measuredWidth + 34), 320), height: 34)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor

        statusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        statusLabel.textColor = .white
        statusLabel.alignment = .center
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updatePresentation()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func updatePresentation() {
        switch presentation {
        case .listening:
            statusLabel.stringValue = "●  Listening"
            layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.94).cgColor
        case .transcribing:
            statusLabel.stringValue = "Transcribing…"
            layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.94).cgColor
        case .busy:
            statusLabel.stringValue = "Busy"
            layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.94).cgColor
        case let .error(message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            statusLabel.stringValue = trimmed.isEmpty ? "Dictation error" : trimmed
            layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.94).cgColor
        case .hidden:
            statusLabel.stringValue = ""
            layer?.backgroundColor = NSColor.clear.cgColor
        }
        invalidateIntrinsicContentSize()
    }
}
