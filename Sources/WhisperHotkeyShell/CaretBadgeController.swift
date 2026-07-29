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
    static let overlayCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .canJoinAllApplications,
        .fullScreenAuxiliary,
        .ignoresCycle,
        .transient,
    ]

    private var panel: NonactivatingBadgePanel
    private let badgeView: BadgeView
    private var lastCaretFrame: CGRect?
    private var lastFieldFrame: CGRect?
    private var lastScreenFrame: CGRect?
    private var lastPointerFallback: CGPoint?
    private var sessionPanelOrigin: CGPoint?
    private var lastVisibilityAssertion = TimeInterval.zero

    public init(actions: CaretBadgeActions = .none) {
        badgeView = BadgeView(
            frame: CGRect(origin: .zero, size: BadgePlacement.defaultSize),
            actions: actions
        )
        panel = Self.makePanel(contentView: badgeView)
    }

    private static func makePanel(
        contentView: BadgeView
    ) -> NonactivatingBadgePanel {
        let panel = NonactivatingBadgePanel(
            contentRect: contentView.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = contentView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = overlayCollectionBehavior
        panel.isReleasedWhenClosed = false
        return panel
    }

    public var isVisible: Bool {
        panel.isVisible
    }

    /// Presents a non-activating badge without changing the active application
    /// or key window. A new listening session snapshots exact Accessibility
    /// geometry or the pointer fallback once, then keeps that origin for every
    /// state until the badge is hidden.
    public func present(
        _ presentation: BadgePresentation,
        caretFrame: CGRect? = nil,
        fieldFrame: CGRect? = nil,
        screenFrame: CGRect? = nil,
        pointerLocation: CGPoint? = nil
    ) {
        guard presentation != .hidden else {
            hide()
            return
        }
        let previousPresentation = badgeView.presentation
        if presentation == .listening, previousPresentation != .listening {
            // Keep one registered panel for the process lifetime. Replacing an
            // ordered-out NSPanel leaks the old window in NSApplication.windows.
            // Reassert its cross-Space behavior before ordering it back in.
            panel.collectionBehavior = Self.overlayCollectionBehavior
            lastCaretFrame = nil
            lastFieldFrame = nil
            lastScreenFrame = nil
            lastPointerFallback = nil
            sessionPanelOrigin = nil
        }

        if lastScreenFrame == nil {
            let runtimeAnchor = BadgePlacement.resolvedRuntimeAnchor(
                caretFrame: caretFrame,
                fieldFrame: fieldFrame,
                pointerLocation: pointerLocation ?? NSEvent.mouseLocation
            )
            let visibleFrame = screenFrame
                ?? screen(containing: runtimeAnchor.frame)?.visibleFrame
                ?? NSScreen.main?.visibleFrame

            guard let visibleFrame else {
                panel.orderOut(nil)
                return
            }
            switch runtimeAnchor {
            case let .accessibility(frame):
                lastCaretFrame = frame
                lastFieldFrame = nil
                lastPointerFallback = nil
            case let .pointer(location):
                lastCaretFrame = nil
                lastFieldFrame = nil
                lastPointerFallback = location
            }
            lastScreenFrame = visibleFrame
        }

        if previousPresentation != presentation {
            badgeView.presentation = presentation
        }
        panel.ignoresMouseEvents = presentation != .listening
        let size = badgeView.preferredSize
        badgeView.frame = CGRect(origin: .zero, size: size)
        badgeView.layoutSubtreeIfNeeded()
        panel.setContentSize(size)

        placePanel(size: size, display: true)
        panel.orderFrontRegardless()
        lastVisibilityAssertion = ProcessInfo.processInfo.systemUptime
    }

    private func placePanel(size: CGSize, display: Bool) {
        guard let visibleFrame = lastScreenFrame else {
            return
        }
        let frame: CGRect
        if let sessionPanelOrigin {
            frame = BadgePlacement.frame(
                preservingOrigin: sessionPanelOrigin,
                screenFrame: visibleFrame,
                badgeSize: size
            )
        } else if let lastPointerFallback {
            let sendButtonFrame = ListeningBadgeLayout().sendButtonFrame
            frame = BadgePlacement.frame(
                pointerLocation: lastPointerFallback,
                badgeHotspot: CGPoint(
                    x: sendButtonFrame.midX,
                    y: sendButtonFrame.midY
                ),
                screenFrame: visibleFrame,
                badgeSize: size
            )
            sessionPanelOrigin = frame.origin
        } else {
            frame = BadgePlacement.frame(
                caretFrame: lastCaretFrame,
                fieldFrame: lastFieldFrame,
                screenFrame: visibleFrame,
                badgeSize: size
            )
            sessionPanelOrigin = frame.origin
        }
        panel.setFrame(frame, display: display)
    }

    public func hide() {
        badgeView.presentation = .hidden
        panel.ignoresMouseEvents = true
        panel.orderOut(nil)
        lastCaretFrame = nil
        lastFieldFrame = nil
        lastScreenFrame = nil
        lastPointerFallback = nil
        sessionPanelOrigin = nil
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
        let size = badgeView.preferredSize
        if badgeView.frame.size != size {
            badgeView.frame = CGRect(origin: .zero, size: size)
            badgeView.layoutSubtreeIfNeeded()
            panel.setContentSize(size)
            placePanel(size: size, display: true)
        }

        let now = ProcessInfo.processInfo.systemUptime
        let visibility = BadgePanelVisibility(
            isVisible: panel.isVisible,
            isOnActiveSpace: panel.isOnActiveSpace
        )
        if now - lastVisibilityAssertion >= 0.5 {
            if visibility.requiresRecovery {
                panel.collectionBehavior = Self.overlayCollectionBehavior
                placePanel(size: size, display: true)
            }
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
        lastVisibilityAssertion = .zero
    }

    func invokeStopAndInsertForTesting() {
        badgeView.invokeStopAndInsert()
    }

    func invokeSendAndSubmitForTesting() {
        badgeView.invokeSendAndSubmit()
    }

    func clickBadgeForTesting(at point: CGPoint) {
        guard let button = badgeView.hitTest(point) as? NSButton else {
            return
        }
        button.performClick(nil)
    }

    var panelFrameForTesting: CGRect {
        panel.frame
    }

    static var registeredPanelCountForTesting: Int {
        NSApplication.shared.windows.reduce(into: 0) { count, window in
            if window is NonactivatingBadgePanel {
                count += 1
            }
        }
    }

    var panelCanHideForTesting: Bool {
        panel.canHide
    }

    var panelIdentifierForTesting: ObjectIdentifier {
        ObjectIdentifier(panel)
    }

    var visualStyleForTesting: BadgeVisualStyleSnapshot {
        BadgeVisualStyleSnapshot(
            borderWidth: badgeView.layer?.borderWidth ?? -1,
            hasGradientLayer: Self.hasGradientLayer(badgeView.layer),
            hasShadow: panel.hasShadow,
            usesContinuousCorners: badgeView.layer?.cornerCurve == .continuous
        )
    }

    var listeningTextForTesting: String {
        badgeView.listeningTextForTesting
    }

    var limitTrackIsVisibleForTesting: Bool {
        badgeView.limitTrackIsVisibleForTesting
    }

    var listeningTimerColorForTesting: NSColor {
        badgeView.listeningTimerColorForTesting
    }

    private static func hasGradientLayer(_ layer: CALayer?) -> Bool {
        guard let layer else {
            return false
        }
        if layer is CAGradientLayer {
            return true
        }
        return layer.sublayers?.contains(where: hasGradientLayer) ?? false
    }

    private func screen(containing frame: CGRect?) -> NSScreen? {
        let screens = NSScreen.screens
        guard let index = BadgeScreenResolver.index(
            containing: frame,
            screenFrames: screens.map(\.frame)
        ) else {
            return nil
        }
        return screens[index]
    }
}

struct BadgeVisualStyleSnapshot: Equatable {
    let borderWidth: CGFloat
    let hasGradientLayer: Bool
    let hasShadow: Bool
    let usesContinuousCorners: Bool
}

struct BadgePanelVisibility: Equatable {
    let isVisible: Bool
    let isOnActiveSpace: Bool

    var requiresRecovery: Bool {
        !isVisible || !isOnActiveSpace
    }
}

enum BadgeScreenResolver {
    static func index(
        containing frame: CGRect?,
        screenFrames: [CGRect]
    ) -> Int? {
        guard let frame, !frame.isNull, !frame.isInfinite else {
            return nil
        }
        let midpoint = CGPoint(x: frame.midX, y: frame.midY)
        return screenFrames.firstIndex {
            $0.contains(midpoint)
                || (frame.width > 0 && frame.height > 0 && $0.intersects(frame))
        }
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
    private let limitTrackLayer = CALayer()
    private let limitProgressLayer = CALayer()
    private var listeningProgress: CGFloat = 0

    var presentation: BadgePresentation = .hidden {
        didSet {
            updatePresentation()
        }
    }

    var preferredSize: CGSize {
        RuntimeBadgeLayout.size
    }

    init(frame frameRect: NSRect, actions: CaretBadgeActions) {
        self.actions = actions
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        limitTrackLayer.backgroundColor = NSColor.white
            .withAlphaComponent(0.08)
            .cgColor
        limitTrackLayer.cornerRadius = 0.75
        limitTrackLayer.isHidden = true
        layer?.addSublayer(limitTrackLayer)

        limitProgressLayer.backgroundColor = waveformColor.cgColor
        limitProgressLayer.cornerRadius = 0.75
        limitTrackLayer.addSublayer(limitProgressLayer)

        statusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        statusLabel.textColor = .white
        statusLabel.alignment = .center
        statusLabel.lineBreakMode = .byTruncatingTail
        addSubview(statusLabel)

        waveformView.isHidden = true
        addSubview(waveformView)

        timeLabel.font = .monospacedDigitSystemFont(
            ofSize: 13,
            weight: .semibold
        )
        timeLabel.textColor = .white
        timeLabel.alignment = .center
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
        statusLabel.frame = BadgeTextLayout.centeredFrame(
            in: bounds,
            horizontalInset: StatusBadgeLayout.horizontalMargin,
            contentHeight: statusLabel.intrinsicContentSize.height
        )
        let listeningLayout = ListeningBadgeLayout()
        waveformView.frame = listeningLayout.waveformFrame
        timeLabel.frame = BadgeTextLayout.centeredFrame(
            in: listeningLayout.timeFrame,
            contentHeight: timeLabel.intrinsicContentSize.height
        )
        stopButton.frame = listeningLayout.stopButtonFrame
        sendButton.frame = listeningLayout.sendButtonFrame
        limitTrackLayer.frame = listeningLayout.limitTrackFrame
        limitProgressLayer.frame = CGRect(
            x: 0,
            y: 0,
            width: listeningLayout.limitTrackFrame.width
                * listeningProgress,
            height: listeningLayout.limitTrackFrame.height
        )
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
        listeningProgress = CGFloat(metrics.warningProgress)
        timeLabel.stringValue = metrics.timeText
        timeLabel.font = .monospacedDigitSystemFont(
            ofSize: 10.5,
            weight: .semibold
        )
        waveformView.level = CGFloat(min(1, max(0, level)))
        setAccessibilityLabel("Recording \(metrics.accessibilityText)")
        needsLayout = true

        guard metrics.isWarning else {
            layer?.backgroundColor = normalBackground.cgColor
            timeLabel.textColor = .white
            limitTrackLayer.isHidden = true
            limitProgressLayer.backgroundColor = waveformColor.cgColor
            return
        }

        limitTrackLayer.isHidden = false
        let orange = NSColor(
            calibratedRed: 1,
            green: 0.62,
            blue: 0.24,
            alpha: 1
        )
        let deepRed = NSColor(
            calibratedRed: 1,
            green: 0.24,
            blue: 0.29,
            alpha: 1
        )
        let warningColor = orange.blended(
            withFraction: metrics.warningProgress,
            of: deepRed
        ) ?? deepRed
        layer?.backgroundColor = normalBackground.cgColor
        timeLabel.textColor = warningColor
        limitProgressLayer.backgroundColor = warningColor.cgColor
    }

    private func updatePresentation() {
        statusLabel.isHidden = presentation == .listening
        waveformView.isHidden = presentation != .listening
        timeLabel.isHidden = presentation != .listening
        stopButton.isHidden = presentation != .listening
        sendButton.isHidden = presentation != .listening
        limitTrackLayer.isHidden = presentation != .listening
        layer?.backgroundColor = normalBackground.cgColor

        switch presentation {
        case .listening:
            statusLabel.stringValue = ""
            listeningProgress = 0
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
        needsLayout = true
    }

    private var normalBackground: NSColor {
        NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.17, alpha: 0.95)
    }

    private var waveformColor: NSColor {
        NSColor(
            calibratedRed: 0.53,
            green: 0.76,
            blue: 1,
            alpha: 1
        )
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
        button.wantsLayer = true
        button.layer?.backgroundColor = background.cgColor
        button.layer?.cornerRadius = size / 2
        button.layer?.masksToBounds = true
    }

    var listeningTextForTesting: String {
        timeLabel.stringValue
    }

    var limitTrackIsVisibleForTesting: Bool {
        !limitTrackLayer.isHidden
    }

    var listeningTimerColorForTesting: NSColor {
        timeLabel.textColor ?? .clear
    }
}

struct ListeningBadgeLayout: Equatable {
    let size: CGSize
    let waveformFrame: CGRect
    let timeFrame: CGRect
    let stopButtonFrame: CGRect
    let sendButtonFrame: CGRect
    let limitTrackFrame: CGRect

    init() {
        let height: CGFloat = 44
        let horizontalMargin: CGFloat = 10
        let waveformWidth: CGFloat = 76
        let waveformHeight: CGFloat = 22
        let timeWidth: CGFloat = 64
        let stopDiameter: CGFloat = 32
        let sendDiameter: CGFloat = 34
        let contentGap: CGFloat = 2
        let buttonGap: CGFloat = 2

        var x = horizontalMargin
        waveformFrame = CGRect(
            x: x,
            y: (height - waveformHeight) / 2,
            width: waveformWidth,
            height: waveformHeight
        )
        x = waveformFrame.maxX + contentGap
        timeFrame = CGRect(
            x: x,
            y: 0,
            width: timeWidth,
            height: height
        )
        x = timeFrame.maxX + contentGap
        stopButtonFrame = CGRect(
            x: x,
            y: (height - stopDiameter) / 2,
            width: stopDiameter,
            height: stopDiameter
        )
        x = stopButtonFrame.maxX + buttonGap
        sendButtonFrame = CGRect(
            x: x,
            y: (height - sendDiameter) / 2,
            width: sendDiameter,
            height: sendDiameter
        )
        size = CGSize(
            width: sendButtonFrame.maxX + horizontalMargin,
            height: height
        )
        limitTrackFrame = CGRect(
            x: horizontalMargin + 3,
            y: 4,
            width: size.width - (horizontalMargin + 3) * 2,
            height: 1.5
        )
    }
}

enum RuntimeBadgeLayout {
    /// Every visible presentation uses one immutable outer frame. Keeping both
    /// dimensions fixed prevents state changes from visually jumping even when
    /// the status text is much shorter than the listening controls.
    static let size = ListeningBadgeLayout().size
}

enum StatusBadgeLayout {
    static let horizontalMargin: CGFloat = 14
    static let size = RuntimeBadgeLayout.size
}

enum BadgeTextLayout {
    static func centeredFrame(
        in container: CGRect,
        horizontalInset: CGFloat = 0,
        contentHeight: CGFloat
    ) -> CGRect {
        let inset = max(0, horizontalInset)
        let height = min(container.height, ceil(max(0, contentHeight)))
        return CGRect(
            x: container.minX + inset,
            y: container.midY - height / 2,
            width: max(0, container.width - inset * 2),
            height: height
        )
    }
}

public struct ListeningBadgeMetrics: Equatable, Sendable {
    public let timeText: String
    public let accessibilityText: String
    public let isWarning: Bool
    public let warningProgress: Double
    public let progress: Double

    public init(elapsed: TimeInterval, limit: TimeInterval) {
        let safeLimit = max(1, limit)
        let safeElapsed = min(max(0, elapsed), safeLimit)
        let remaining = max(0, safeLimit - safeElapsed)
        let warningWindow = min(60, safeLimit)
        isWarning = remaining <= warningWindow
        warningProgress = isWarning
            ? min(1, max(0, 1 - remaining / warningWindow))
            : 0
        progress = min(1, max(0, safeElapsed / safeLimit))

        let elapsedText = Self.format(safeElapsed)
        let limitText = Self.format(safeLimit)
        let remainingText = Self.formatRemaining(remaining)
        timeText = isWarning ? "\(remainingText) left" : elapsedText
        accessibilityText = "\(elapsedText) of \(limitText), \(remainingText) remaining"
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

    private static func formatRemaining(_ interval: TimeInterval) -> String {
        format(interval.rounded(.up))
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

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        layer?.masksToBounds = true
    }
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
        let barWidth = AudioWaveformStyle.barWidth
        let gap = AudioWaveformStyle.gap(
            availableWidth: bounds.width,
            sampleCount: history.samples.count
        )
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

enum AudioWaveformStyle {
    static let barWidth: CGFloat = 1.6
    static let horizontalInset: CGFloat = 4

    static func gap(
        availableWidth: CGFloat,
        sampleCount: Int
    ) -> CGFloat {
        guard sampleCount > 1 else {
            return 0
        }
        let usableWidth = max(
            0,
            availableWidth - horizontalInset * 2
                - CGFloat(sampleCount) * barWidth
        )
        return usableWidth / CGFloat(sampleCount - 1)
    }
}
