import AppKit
import WhisperHotkeyCore

@MainActor
public struct CaretBadgeActions {
    public let stopAndInsert: @MainActor () -> Void
    public let sendAndSubmit: @MainActor () -> Void

    public init(
        stopAndInsert: @escaping @MainActor () -> Void,
        sendAndSubmit: @escaping @MainActor () -> Void
    ) {
        self.stopAndInsert = stopAndInsert
        self.sendAndSubmit = sendAndSubmit
    }

    public static let none = CaretBadgeActions(
        stopAndInsert: {},
        sendAndSubmit: {}
    )
}

@MainActor
public final class CaretBadgeController {
    private let panel: NonactivatingBadgePanel
    private let badgeView: BadgeView
    private var lastCaretFrame: CGRect?
    private var lastFieldFrame: CGRect?
    private var lastScreenFrame: CGRect?
    private var lastVisibilityAssertion = TimeInterval.zero

    public init(actions: CaretBadgeActions = .none) {
        badgeView = BadgeView(
            frame: CGRect(origin: .zero, size: BadgePlacement.defaultSize),
            actions: actions
        )
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
        lastCaretFrame = caretFrame
        lastFieldFrame = fieldFrame
        lastScreenFrame = screenFrame

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
        panel.ignoresMouseEvents = presentation != .listening
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
        lastVisibilityAssertion = ProcessInfo.processInfo.systemUptime
    }

    public func hide() {
        badgeView.presentation = .hidden
        panel.ignoresMouseEvents = true
        panel.orderOut(nil)
        lastCaretFrame = nil
        lastFieldFrame = nil
        lastScreenFrame = nil
    }

    public func updateListening(
        elapsed: TimeInterval,
        limit: TimeInterval,
        level: Float
    ) {
        guard badgeView.presentation == .listening else {
            return
        }
        badgeView.updateListening(
            elapsed: elapsed,
            limit: limit,
            level: level
        )

        let now = ProcessInfo.processInfo.systemUptime
        if !panel.isVisible {
            present(
                .listening,
                caretFrame: lastCaretFrame,
                fieldFrame: lastFieldFrame,
                screenFrame: lastScreenFrame
            )
        } else if now - lastVisibilityAssertion >= 0.5 {
            // AppKit can retain `isVisible == true` while moving a
            // non-activating utility panel behind the current Space. A bounded
            // assertion while recording keeps the controller discoverable
            // without any background polling while idle.
            panel.orderFrontRegardless()
            lastVisibilityAssertion = now
        }
    }

    public func containsInteractivePoint(_ point: CGPoint) -> Bool {
        panel.isVisible
            && badgeView.presentation == .listening
            && panel.frame.contains(point)
    }

    func orderOutWithoutEndingPresentationForTesting() {
        panel.orderOut(nil)
    }

    func invokeStopAndInsertForTesting() {
        badgeView.invokeStopAndInsert()
    }

    func invokeSendAndSubmitForTesting() {
        badgeView.invokeSendAndSubmit()
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
    private let actions: CaretBadgeActions
    private let statusLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "0:00")
    private let waveformView = AudioWaveformView()
    private let stopButton = BadgeActionButton()
    private let sendButton = BadgeActionButton()
    private let warningLayer = CAGradientLayer()

    var presentation: BadgePresentation = .hidden {
        didSet {
            updatePresentation()
        }
    }

    var preferredSize: CGSize {
        if presentation == .listening {
            return CGSize(width: 300, height: 40)
        }
        let measuredWidth = ceil(statusLabel.intrinsicContentSize.width)
        return CGSize(width: min(max(116, measuredWidth + 34), 320), height: 34)
    }

    init(frame frameRect: NSRect, actions: CaretBadgeActions) {
        self.actions = actions
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 11
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

        configureActionButton(
            stopButton,
            symbol: "stop.fill",
            accessibilityLabel: "Stop and insert dictation",
            background: NSColor.white.withAlphaComponent(0.07),
            foreground: NSColor.white.withAlphaComponent(0.86),
            size: 32
        )
        stopButton.target = self
        stopButton.action = #selector(stopAndInsert)
        addSubview(stopButton)

        configureActionButton(
            sendButton,
            symbol: "arrow.up",
            accessibilityLabel: "Insert dictation and press Return",
            background: NSColor(
                calibratedRed: 0.91,
                green: 0.94,
                blue: 0.98,
                alpha: 1
            ),
            foreground: NSColor(
                calibratedRed: 0.10,
                green: 0.12,
                blue: 0.15,
                alpha: 1
            ),
            size: 34
        )
        sendButton.target = self
        sendButton.action = #selector(sendAndSubmit)
        addSubview(sendButton)

        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            waveformView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            waveformView.centerYAnchor.constraint(equalTo: centerYAnchor),
            waveformView.widthAnchor.constraint(equalToConstant: 104),
            waveformView.heightAnchor.constraint(equalToConstant: 24),
            timeLabel.leadingAnchor.constraint(
                equalTo: waveformView.trailingAnchor,
                constant: 6
            ),
            timeLabel.widthAnchor.constraint(equalToConstant: 86),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            stopButton.leadingAnchor.constraint(
                equalTo: timeLabel.trailingAnchor,
                constant: 7
            ),
            stopButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            stopButton.widthAnchor.constraint(equalToConstant: 32),
            stopButton.heightAnchor.constraint(equalToConstant: 32),
            sendButton.leadingAnchor.constraint(
                equalTo: stopButton.trailingAnchor,
                constant: 7
            ),
            sendButton.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -8
            ),
            sendButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 34),
            sendButton.heightAnchor.constraint(equalToConstant: 34),
        ])
        updatePresentation()
    }

    required init?(coder: NSCoder) {
        nil
    }

    @objc private func stopAndInsert() {
        actions.stopAndInsert()
    }

    @objc private func sendAndSubmit() {
        actions.sendAndSubmit()
    }

    func invokeStopAndInsert() {
        stopAndInsert()
    }

    func invokeSendAndSubmit() {
        sendAndSubmit()
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
        stopButton.isHidden = presentation != .listening
        sendButton.isHidden = presentation != .listening
        warningLayer.isHidden = true
        layer?.backgroundColor = normalBackground.cgColor

        switch presentation {
        case .listening:
            statusLabel.stringValue = ""
            waveformView.reset()
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

    private func configureActionButton(
        _ button: NSButton,
        symbol: String,
        accessibilityLabel: String,
        background: NSColor,
        foreground: NSColor,
        size: CGFloat
    ) {
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: accessibilityLabel
        )
        button.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: symbol == "arrow.up" ? 17 : 10,
            weight: symbol == "arrow.up" ? .medium : .semibold
        )
        button.contentTintColor = foreground
        button.toolTip = accessibilityLabel
        button.setAccessibilityLabel(accessibilityLabel)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.wantsLayer = true
        button.layer?.backgroundColor = background.cgColor
        button.layer?.cornerRadius = size / 2
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

struct AudioWaveformHistory: Equatable {
    private(set) var samples: [CGFloat]

    init(capacity: Int = 23) {
        samples = Array(repeating: 0, count: max(1, capacity))
    }

    mutating func append(_ level: CGFloat) {
        let clamped = min(1, max(0, level))
        // A sub-linear curve makes normal speech visibly responsive while
        // preserving the top of the range for genuinely loud input.
        let sensitive = pow(clamped, 0.62)
        samples.removeFirst()
        samples.append(sensitive)
    }

    mutating func reset() {
        samples = Array(repeating: 0, count: samples.count)
    }
}

private final class BadgeActionButton: NSButton {
    override var acceptsFirstResponder: Bool { false }
}

@MainActor
private final class AudioWaveformView: NSView {
    private var history = AudioWaveformHistory()

    var level: CGFloat = 0 {
        didSet {
            history.append(level)
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }

    func reset() {
        history.reset()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let barWidth: CGFloat = 2.4
        let gap: CGFloat = 2
        let totalWidth = CGFloat(history.samples.count) * barWidth
            + CGFloat(history.samples.count - 1) * gap
        var x = (bounds.width - totalWidth) / 2
        let activeColor = NSColor(
            calibratedRed: 0.53,
            green: 0.76,
            blue: 1,
            alpha: 1
        )

        for sample in history.samples {
            let isQuiet = sample < 0.015
            let height = isQuiet
                ? 1.5
                : max(3, 3 + sample * (bounds.height - 3))
            let rect = CGRect(
                x: x,
                y: (bounds.height - height) / 2,
                width: barWidth,
                height: height
            )
            (isQuiet
                ? activeColor.withAlphaComponent(0.38)
                : activeColor
            ).setFill()
            NSBezierPath(
                roundedRect: rect,
                xRadius: barWidth / 2,
                yRadius: barWidth / 2
            ).fill()
            x += barWidth + gap
        }
    }
}
