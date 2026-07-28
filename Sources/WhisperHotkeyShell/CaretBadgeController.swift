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
    /// or key window. Runtime states prefer exact Accessibility geometry and
    /// snapshot the pointer when the destination does not expose a caret.
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

        let runtimeAnchor: CGRect?
        switch presentation {
        case .listening, .transcribing, .busy:
            runtimeAnchor = BadgePlacement.runtimeAnchor(
                caretFrame: caretFrame,
                fieldFrame: fieldFrame,
                pointerLocation: NSEvent.mouseLocation
            )
        case .error, .hidden:
            runtimeAnchor = nil
        }

        badgeView.presentation = presentation
        let size = badgeView.preferredSize
        badgeView.frame = CGRect(origin: .zero, size: size)
        panel.setContentSize(size)
        let resolvedCaretFrame = runtimeAnchor ?? caretFrame
        let resolvedFieldFrame = runtimeAnchor == nil ? fieldFrame : nil
        let anchor = resolvedCaretFrame ?? resolvedFieldFrame
        let visibleFrame = screenFrame
            ?? screen(containing: anchor)?.visibleFrame
            ?? NSScreen.main?.visibleFrame

        guard let visibleFrame else {
            panel.orderOut(nil)
            return
        }

        panel.setFrame(
            BadgePlacement.frame(
                caretFrame: resolvedCaretFrame,
                fieldFrame: resolvedFieldFrame,
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

    public func updateListening(
        elapsed: TimeInterval,
        limit: TimeInterval,
        level: Float
    ) {
        guard panel.isVisible, badgeView.presentation == .listening else {
            return
        }
        badgeView.updateListening(
            elapsed: elapsed,
            limit: limit,
            level: level
        )
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
    private let timeLabel = NSTextField(labelWithString: "0:00")
    private let waveformView = AudioWaveformView()
    private let warningLayer = CAGradientLayer()

    var presentation: BadgePresentation = .hidden {
        didSet {
            updatePresentation()
        }
    }

    var preferredSize: CGSize {
        if presentation == .listening {
            return CGSize(width: 176, height: 32)
        }
        let measuredWidth = ceil(statusLabel.intrinsicContentSize.width)
        return CGSize(width: min(max(116, measuredWidth + 34), 320), height: 34)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        warningLayer.isHidden = true
        warningLayer.startPoint = CGPoint(x: 0, y: 0.5)
        warningLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.insertSublayer(warningLayer, at: 0)

        statusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        statusLabel.textColor = .white
        statusLabel.alignment = .center
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)

        waveformView.translatesAutoresizingMaskIntoConstraints = false
        waveformView.isHidden = true
        addSubview(waveformView)

        timeLabel.font = .monospacedDigitSystemFont(
            ofSize: 13,
            weight: .semibold
        )
        timeLabel.textColor = .white
        timeLabel.alignment = .right
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.isHidden = true
        addSubview(timeLabel)

        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            waveformView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            waveformView.centerYAnchor.constraint(equalTo: centerYAnchor),
            waveformView.widthAnchor.constraint(equalToConstant: 36),
            waveformView.heightAnchor.constraint(equalToConstant: 18),
            timeLabel.leadingAnchor.constraint(
                equalTo: waveformView.trailingAnchor,
                constant: 8
            ),
            timeLabel.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -12
            ),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updatePresentation()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        warningLayer.frame = bounds
        warningLayer.cornerRadius = layer?.cornerRadius ?? 0
    }

    func updateListening(
        elapsed: TimeInterval,
        limit: TimeInterval,
        level: Float
    ) {
        guard presentation == .listening else {
            return
        }
        let metrics = ListeningBadgeMetrics(
            elapsed: elapsed,
            limit: limit
        )
        timeLabel.stringValue = metrics.timeText
        timeLabel.font = .monospacedDigitSystemFont(
            ofSize: metrics.isWarning ? 10.5 : 12.5,
            weight: .semibold
        )
        waveformView.level = CGFloat(min(1, max(0, level)))
        setAccessibilityLabel("Recording \(metrics.accessibilityText)")

        guard metrics.isWarning else {
            warningLayer.isHidden = true
            layer?.backgroundColor = normalBackground.cgColor
            return
        }

        let pulse = (sin(elapsed * .pi * 3) + 1) / 2
        let intensity = min(
            1,
            metrics.warningProgress * 0.75 + pulse * 0.25
        )
        let orange = NSColor.systemOrange.blended(
            withFraction: intensity * 0.28,
            of: .systemRed
        ) ?? .systemOrange
        let red = NSColor.systemRed.blended(
            withFraction: 0.18 + intensity * 0.32,
            of: NSColor(calibratedRed: 0.35, green: 0.01, blue: 0.03, alpha: 1)
        ) ?? .systemRed
        layer?.backgroundColor = NSColor.clear.cgColor
        warningLayer.colors = [
            orange.withAlphaComponent(0.96).cgColor,
            red.withAlphaComponent(0.97).cgColor,
        ]
        warningLayer.isHidden = false
    }

    private func updatePresentation() {
        statusLabel.isHidden = presentation == .listening
        waveformView.isHidden = presentation != .listening
        timeLabel.isHidden = presentation != .listening
        warningLayer.isHidden = true
        layer?.backgroundColor = normalBackground.cgColor

        switch presentation {
        case .listening:
            statusLabel.stringValue = ""
            updateListening(elapsed: 0, limit: 600, level: 0)
        case .transcribing:
            statusLabel.stringValue = "Transcribing…"
        case .busy:
            statusLabel.stringValue = "Busy"
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

    private var normalBackground: NSColor {
        NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.17, alpha: 0.95)
    }
}

public struct ListeningBadgeMetrics: Equatable, Sendable {
    public let timeText: String
    public let accessibilityText: String
    public let isWarning: Bool
    public let warningProgress: Double

    public init(elapsed: TimeInterval, limit: TimeInterval) {
        let safeLimit = max(1, limit)
        let safeElapsed = min(max(0, elapsed), safeLimit)
        let remaining = max(0, safeLimit - safeElapsed)
        isWarning = remaining <= 30
        warningProgress = isWarning ? min(1, max(0, 1 - remaining / 30)) : 0

        let elapsedText = Self.format(safeElapsed)
        let limitText = Self.format(safeLimit)
        timeText = isWarning
            ? "\(elapsedText) / \(limitText)"
            : elapsedText
        accessibilityText = isWarning
            ? "\(elapsedText) of \(limitText)"
            : elapsedText
    }

    private static func format(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(
                format: "%d:%02d:%02d",
                hours,
                minutes,
                seconds
            )
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

@MainActor
private final class AudioWaveformView: NSView {
    var level: CGFloat = 0 {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let weights: [CGFloat] = [0.45, 0.72, 1, 0.72, 0.45]
        let barWidth: CGFloat = 3.5
        let gap: CGFloat = 3
        let totalWidth = CGFloat(weights.count) * barWidth
            + CGFloat(weights.count - 1) * gap
        var x = (bounds.width - totalWidth) / 2
        NSColor(calibratedRed: 0.48, green: 0.73, blue: 1, alpha: 1).setFill()

        for weight in weights {
            let height = max(4, 5 + level * weight * (bounds.height - 5))
            let rect = CGRect(
                x: x,
                y: (bounds.height - height) / 2,
                width: barWidth,
                height: height
            )
            NSBezierPath(
                roundedRect: rect,
                xRadius: barWidth / 2,
                yRadius: barWidth / 2
            ).fill()
            x += barWidth + gap
        }
    }
}
