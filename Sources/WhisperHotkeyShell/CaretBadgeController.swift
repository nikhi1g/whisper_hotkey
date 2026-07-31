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
    private var sessionPositionWasDragged = false
    private var lastVisibilityAssertion = TimeInterval.zero

    public init(
        actions: CaretBadgeActions = .none,
        theme: BadgeThemeSelection = .defaultSelection
    ) {
        badgeView = BadgeView(
            frame: CGRect(origin: .zero, size: BadgePlacement.defaultSize),
            actions: actions,
            theme: theme
        )
        panel = Self.makePanel(contentView: badgeView)
        badgeView.dragHandler = { [weak self] proposedOrigin in
            self?.movePanel(to: proposedOrigin)
        }
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
        panel.hasShadow = false
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

    public func applyTheme(_ theme: BadgeThemeSelection) {
        badgeView.applyTheme(theme)
    }

    public func applyTheme(_ theme: BadgeTheme) {
        applyTheme(.builtIn(theme))
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
            sessionPositionWasDragged = false
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
                lastCaretFrame = caretFrame
                lastFieldFrame = fieldFrame ?? (
                    caretFrame == nil ? frame : nil
                )
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

    private func movePanel(to proposedOrigin: CGPoint) {
        guard
            badgeView.presentation == .listening,
            let visibleFrame = lastScreenFrame
        else {
            return
        }
        let frame = BadgePlacement.frame(
            preservingOrigin: proposedOrigin,
            screenFrame: visibleFrame,
            badgeSize: badgeView.preferredSize
        )
        sessionPositionWasDragged = true
        sessionPanelOrigin = frame.origin
        panel.setFrameOrigin(frame.origin)
    }

    public var acceptsAutomaticAnchorUpdates: Bool {
        badgeView.presentation == .listening
            && !sessionPositionWasDragged
    }

    @discardableResult
    public func updateAutomaticAnchor(
        caretFrame: CGRect?,
        fieldFrame: CGRect?,
        screenFrame: CGRect? = nil
    ) -> Bool {
        guard acceptsAutomaticAnchorUpdates else {
            return false
        }
        let anchor = BadgePlacement.resolvedRuntimeAnchor(
            caretFrame: caretFrame,
            fieldFrame: fieldFrame,
            pointerLocation: NSEvent.mouseLocation
        )
        guard case let .accessibility(anchorFrame) = anchor else {
            return false
        }
        let visibleFrame = screenFrame
            ?? screen(containing: anchorFrame)?.visibleFrame
            ?? lastScreenFrame
        guard let visibleFrame else {
            return false
        }
        guard
            lastCaretFrame != caretFrame
                || lastFieldFrame != fieldFrame
                || lastScreenFrame != visibleFrame
        else {
            return false
        }

        lastCaretFrame = caretFrame
        lastFieldFrame = fieldFrame
        lastPointerFallback = nil
        lastScreenFrame = visibleFrame
        sessionPanelOrigin = nil
        placePanel(size: badgeView.preferredSize, display: true)
        panel.orderFrontRegardless()
        lastVisibilityAssertion = ProcessInfo.processInfo.systemUptime
        return true
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
        sessionPositionWasDragged = false
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

    func dragBadgeForTesting(to proposedOrigin: CGPoint) {
        movePanel(to: proposedOrigin)
    }

    func badgeBackgroundIsDraggableForTesting(at point: CGPoint) -> Bool {
        badgeView.hitTest(point) === badgeView
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

    var statusTextForTesting: String {
        badgeView.statusTextForTesting
    }

    var transcribingIndicatorSnapshotForTesting:
        CapsuleActivityIndicatorSnapshot
    {
        badgeView.transcribingIndicatorSnapshotForTesting
    }

    var listeningContentIsVisibleForTesting: Bool {
        badgeView.listeningContentIsVisibleForTesting
    }

    var activityOriginSnapshotForTesting: ActivityOriginSnapshot {
        badgeView.activityOriginSnapshotForTesting
    }

    var badgeAccessibilityLabelForTesting: String? {
        badgeView.accessibilityLabel()
    }

    var appliedThemeForTesting: BadgeThemeSelection {
        badgeView.themeForTesting
    }

    var badgeBackgroundColorForTesting: NSColor {
        badgeView.backgroundColorForTesting
    }

    var renderedBadgeBackgroundColorForTesting: NSColor {
        badgeView.renderedBackgroundColorForTesting
    }

    var statusTextColorForTesting: NSColor {
        badgeView.statusTextColorForTesting
    }

    var transcribingColorForTesting: NSColor {
        badgeView.transcribingColorForTesting
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
    private var theme: BadgeThemeSelection
    private var palette: BadgeThemePalette
    private let statusLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "0:00")
    private let waveformView = AudioWaveformView()
    private let stopButton = BadgeActionButton()
    private let sendButton = BadgeActionButton()
    private let limitTrackLayer = CALayer()
    private let limitProgressLayer = CALayer()
    private let activityOriginLayer = CALayer()
    private let transcribingIndicatorLayer =
        CapsuleActivityIndicatorLayer()
    private var listeningProgress: CGFloat = 0
    private var dragStart: (pointer: CGPoint, windowOrigin: CGPoint)?
    var dragHandler: (@MainActor (CGPoint) -> Void)?

    var presentation: BadgePresentation = .hidden {
        didSet {
            updatePresentation()
        }
    }

    var preferredSize: CGSize {
        RuntimeBadgeLayout.size
    }

    init(
        frame frameRect: NSRect,
        actions: CaretBadgeActions,
        theme: BadgeThemeSelection
    ) {
        self.actions = actions
        self.theme = theme
        palette = BadgeThemePalette.palette(for: theme)
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = RuntimeBadgeLayout.size.height / 2
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        limitTrackLayer.backgroundColor = palette.limitTrack.cgColor
        limitTrackLayer.cornerRadius = 0.75
        limitTrackLayer.isHidden = true
        layer?.addSublayer(limitTrackLayer)

        limitProgressLayer.backgroundColor = waveformColor.cgColor
        limitProgressLayer.cornerRadius = 0.75
        limitTrackLayer.addSublayer(limitProgressLayer)

        activityOriginLayer.backgroundColor = palette.waveform.cgColor
        activityOriginLayer.isHidden = true
        layer?.addSublayer(activityOriginLayer)

        transcribingIndicatorLayer.color = palette.waveform
        layer?.addSublayer(transcribingIndicatorLayer)

        statusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        statusLabel.textColor = palette.primaryText
        statusLabel.alignment = .center
        statusLabel.lineBreakMode = .byTruncatingTail
        addSubview(statusLabel)

        waveformView.isHidden = true
        waveformView.color = palette.waveform
        addSubview(waveformView)

        timeLabel.font = .monospacedDigitSystemFont(
            ofSize: 13,
            weight: .semibold
        )
        timeLabel.textColor = palette.primaryText
        timeLabel.alignment = .center
        timeLabel.isHidden = true
        addSubview(timeLabel)

        configureActionButton(
            stopButton,
            symbol: "stop.fill",
            accessibilityLabel: "Stop and insert dictation",
            background: palette.stopBackground,
            foreground: palette.stopForeground,
            size: 32
        )
        stopButton.target = self
        stopButton.action = #selector(stopAndInsert)
        addSubview(stopButton)

        configureActionButton(
            sendButton,
            symbol: "arrow.up",
            accessibilityLabel: "Insert dictation and press Return",
            background: palette.sendBackground,
            foreground: palette.sendForeground,
            size: 32
        )
        sendButton.target = self
        sendButton.action = #selector(sendAndSubmit)
        addSubview(sendButton)

        updatePresentation()
    }

    func applyTheme(_ theme: BadgeThemeSelection) {
        guard self.theme != theme else {
            return
        }
        self.theme = theme
        palette = BadgeThemePalette.palette(for: theme)
        statusLabel.textColor = palette.primaryText
        timeLabel.textColor = palette.primaryText
        waveformView.color = palette.waveform
        limitTrackLayer.backgroundColor = palette.limitTrack.cgColor
        limitProgressLayer.backgroundColor = palette.waveform.cgColor
        activityOriginLayer.backgroundColor = palette.waveform.cgColor
        transcribingIndicatorLayer.color = palette.waveform
        applyActionButtonStyle(
            stopButton,
            background: palette.stopBackground,
            foreground: palette.stopForeground
        )
        applyActionButtonStyle(
            sendButton,
            background: palette.sendBackground,
            foreground: palette.sendForeground
        )
        updatePresentation()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, bounds.contains(point) else {
            return nil
        }
        for button in [stopButton, sendButton]
        where !button.isHidden && button.frame.contains(point) {
            return button
        }
        return presentation == .listening ? self : super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        guard presentation == .listening, let window else {
            return
        }
        dragStart = (
            pointer: NSEvent.mouseLocation,
            windowOrigin: window.frame.origin
        )
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else {
            return
        }
        let pointer = NSEvent.mouseLocation
        dragHandler?(
            CGPoint(
                x: dragStart.windowOrigin.x + pointer.x - dragStart.pointer.x,
                y: dragStart.windowOrigin.y + pointer.y - dragStart.pointer.y
            )
        )
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
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
        layer?.cornerRadius = bounds.height / 2
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
        let activityOrigin = CapsuleActivityIndicatorStyle.geometry(
            in: bounds
        ).startPoint
        activityOriginLayer.frame = CGRect(
            x: activityOrigin.x - ActivityOriginStyle.size / 2,
            y: activityOrigin.y - ActivityOriginStyle.size / 2,
            width: ActivityOriginStyle.size,
            height: ActivityOriginStyle.size
        )
        transcribingIndicatorLayer.frame = bounds
        transcribingIndicatorLayer.updatePath()
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
            timeLabel.textColor = palette.primaryText
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
        let showsListeningContent =
            presentation == .listening || presentation == .transcribing
        statusLabel.isHidden =
            presentation == .listening || presentation == .transcribing
        waveformView.isHidden = !showsListeningContent
        timeLabel.isHidden = !showsListeningContent
        stopButton.isHidden = !showsListeningContent
        sendButton.isHidden = !showsListeningContent
        if !showsListeningContent {
            limitTrackLayer.isHidden = true
        }
        activityOriginLayer.isHidden = presentation != .listening
        if presentation == .transcribing {
            transcribingIndicatorLayer.startAnimating()
        } else {
            transcribingIndicatorLayer.stopAnimating()
        }
        layer?.backgroundColor = normalBackground.cgColor
        statusLabel.textColor = palette.primaryText

        switch presentation {
        case .listening:
            statusLabel.stringValue = ""
            listeningProgress = 0
            waveformView.reset()
            updateListening(elapsed: 0, limit: 600, level: 0)
        case .transcribing:
            statusLabel.stringValue = ""
            setAccessibilityLabel("Transcribing")
        case .busy:
            statusLabel.stringValue = "Busy"
        case let .error(message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            statusLabel.stringValue = trimmed.isEmpty ? "Dictation error" : trimmed
            if !BadgeMessageStyle.usesTheme(message: trimmed) {
                statusLabel.textColor = .white
                layer?.backgroundColor =
                    NSColor.systemRed.withAlphaComponent(0.94).cgColor
            }
        case .hidden:
            statusLabel.stringValue = ""
            layer?.backgroundColor = NSColor.clear.cgColor
        }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    private var normalBackground: NSColor {
        palette.background
    }

    private var waveformColor: NSColor {
        palette.waveform
    }

    private func configureActionButton(
        _ button: BadgeActionButton,
        symbol: String,
        accessibilityLabel: String,
        background: NSColor,
        foreground: NSColor,
        size: CGFloat
    ) {
        button.isBordered = false
        button.image = nil
        button.badgeSymbol = symbol == "arrow.up" ? .send : .stop
        button.symbolColor = foreground
        button.toolTip = accessibilityLabel
        button.setAccessibilityLabel(accessibilityLabel)
        button.wantsLayer = true
        button.layer?.backgroundColor = background.cgColor
        button.layer?.cornerRadius = size / 2
        button.layer?.masksToBounds = true
    }

    private func applyActionButtonStyle(
        _ button: BadgeActionButton,
        background: NSColor,
        foreground: NSColor
    ) {
        button.symbolColor = foreground
        button.layer?.backgroundColor = background.cgColor
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

    var themeForTesting: BadgeThemeSelection {
        theme
    }

    var backgroundColorForTesting: NSColor {
        palette.background
    }

    var renderedBackgroundColorForTesting: NSColor {
        guard let color = layer?.backgroundColor else {
            return .clear
        }
        return NSColor(cgColor: color) ?? .clear
    }

    var statusTextColorForTesting: NSColor {
        statusLabel.textColor ?? .clear
    }

    var transcribingColorForTesting: NSColor {
        transcribingIndicatorLayer.color
    }

    var statusTextForTesting: String {
        statusLabel.stringValue
    }

    var transcribingIndicatorSnapshotForTesting:
        CapsuleActivityIndicatorSnapshot
    {
        transcribingIndicatorLayer.snapshot
    }

    var listeningContentIsVisibleForTesting: Bool {
        !waveformView.isHidden
            && !timeLabel.isHidden
            && !stopButton.isHidden
            && !sendButton.isHidden
    }

    var activityOriginSnapshotForTesting: ActivityOriginSnapshot {
        ActivityOriginSnapshot(
            isVisible: !activityOriginLayer.isHidden,
            frame: activityOriginLayer.frame
        )
    }
}

struct ActivityOriginSnapshot: Equatable {
    let isVisible: Bool
    let frame: CGRect
}

enum ActivityOriginStyle {
    static let size: CGFloat = 3
}

enum BadgeMessageStyle {
    static func usesTheme(message: String) -> Bool {
        message
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .caseInsensitiveCompare("No speech detected") == .orderedSame
    }
}

struct CapsuleActivityIndicatorStyle {
    static let inset: CGFloat = 1.25
    static let lineWidth: CGFloat = 1.5
    static let segmentCount = 7
    static let segmentLength: CGFloat = 7
    static let segmentSpacing: CGFloat = 1.5
    static let animationDuration: CFTimeInterval = 0.92

    static func geometry(in bounds: CGRect) -> CapsuleActivityIndicatorGeometry {
        let insetBounds = bounds.insetBy(dx: inset, dy: inset)
        let radius = insetBounds.height / 2
        return CapsuleActivityIndicatorGeometry(
            startPoint: CGPoint(x: insetBounds.midX, y: insetBounds.maxY),
            leftCenter: CGPoint(
                x: insetBounds.minX + radius,
                y: insetBounds.midY
            ),
            rightCenter: CGPoint(
                x: insetBounds.maxX - radius,
                y: insetBounds.midY
            ),
            radius: radius,
            perimeter: 2 * (insetBounds.width - 2 * radius)
                + 2 * .pi * radius
        )
    }

    static func path(in bounds: CGRect) -> CGPath {
        let geometry = geometry(in: bounds)
        let path = CGMutablePath()
        path.move(to: geometry.startPoint)
        path.addLine(
            to: CGPoint(
                x: geometry.rightCenter.x,
                y: geometry.startPoint.y
            )
        )
        path.addArc(
            center: geometry.rightCenter,
            radius: geometry.radius,
            startAngle: .pi / 2,
            endAngle: -.pi / 2,
            clockwise: true
        )
        path.addLine(
            to: CGPoint(
                x: geometry.leftCenter.x,
                y: geometry.leftCenter.y - geometry.radius
            )
        )
        path.addArc(
            center: geometry.leftCenter,
            radius: geometry.radius,
            startAngle: -.pi / 2,
            endAngle: -.pi * 1.5,
            clockwise: true
        )
        path.addLine(to: geometry.startPoint)
        path.closeSubpath()
        return path
    }
}

struct CapsuleActivityIndicatorGeometry: Equatable {
    let startPoint: CGPoint
    let leftCenter: CGPoint
    let rightCenter: CGPoint
    let radius: CGFloat
    let perimeter: CGFloat
}

struct CapsuleActivityIndicatorSnapshot: Equatable {
    let isVisible: Bool
    let segmentCount: Int
    let animatedSegmentCount: Int
    let opacities: [Float]
    let geometry: CapsuleActivityIndicatorGeometry
    let animationDuration: CFTimeInterval
}

private final class CapsuleActivityIndicatorLayer: CALayer {
    private static let animationKey = "capsuleTraversal"
    private let segmentLayers: [CAShapeLayer]

    var color = NSColor.controlAccentColor {
        didSet {
            segmentLayers.forEach { $0.strokeColor = color.cgColor }
        }
    }

    override init() {
        segmentLayers = (0..<CapsuleActivityIndicatorStyle.segmentCount).map {
            index in
            let layer = CAShapeLayer()
            layer.fillColor = NSColor.clear.cgColor
            layer.lineCap = .round
            layer.lineJoin = .round
            layer.lineWidth = CapsuleActivityIndicatorStyle.lineWidth
            layer.opacity = pow(0.62, Float(index))
            return layer
        }
        super.init()
        isHidden = true
        masksToBounds = false
        segmentLayers.forEach(addSublayer)
    }

    override init(layer: Any) {
        segmentLayers = (0..<CapsuleActivityIndicatorStyle.segmentCount).map {
            index in
            let layer = CAShapeLayer()
            layer.fillColor = NSColor.clear.cgColor
            layer.lineCap = .round
            layer.lineJoin = .round
            layer.lineWidth = CapsuleActivityIndicatorStyle.lineWidth
            layer.opacity = pow(0.62, Float(index))
            return layer
        }
        super.init(layer: layer)
        segmentLayers.forEach(addSublayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func updatePath() {
        let geometry = CapsuleActivityIndicatorStyle.geometry(in: bounds)
        let path = CapsuleActivityIndicatorStyle.path(in: bounds)
        let gap = max(
            1,
            geometry.perimeter - CapsuleActivityIndicatorStyle.segmentLength
        )
        for segment in segmentLayers {
            segment.frame = bounds
            segment.path = path
            segment.lineDashPattern = [
                NSNumber(value: CapsuleActivityIndicatorStyle.segmentLength),
                NSNumber(value: gap),
            ]
        }
    }

    func startAnimating() {
        isHidden = false
        updatePath()
        guard segmentLayers.first?.animation(
            forKey: Self.animationKey
        ) == nil else {
            return
        }
        let perimeter = CapsuleActivityIndicatorStyle.geometry(
            in: bounds
        ).perimeter
        for (index, segment) in segmentLayers.enumerated() {
            let initialPhase = CGFloat(index)
                * (
                    CapsuleActivityIndicatorStyle.segmentLength
                        + CapsuleActivityIndicatorStyle.segmentSpacing
                )
            segment.lineDashPhase = initialPhase
            let animation = CABasicAnimation(keyPath: "lineDashPhase")
            animation.fromValue = initialPhase
            animation.toValue = initialPhase - perimeter
            animation.duration =
                CapsuleActivityIndicatorStyle.animationDuration
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(
                name: .linear
            )
            animation.isRemovedOnCompletion = false
            segment.add(animation, forKey: Self.animationKey)
        }
    }

    func stopAnimating() {
        segmentLayers.forEach {
            $0.removeAnimation(forKey: Self.animationKey)
        }
        isHidden = true
    }

    var snapshot: CapsuleActivityIndicatorSnapshot {
        CapsuleActivityIndicatorSnapshot(
            isVisible: !isHidden,
            segmentCount: segmentLayers.count,
            animatedSegmentCount: segmentLayers.filter {
                $0.animation(forKey: Self.animationKey) != nil
            }.count,
            opacities: segmentLayers.map(\.opacity),
            geometry: CapsuleActivityIndicatorStyle.geometry(in: bounds),
            animationDuration: CapsuleActivityIndicatorStyle.animationDuration
        )
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
        let height: CGFloat = 42
        let horizontalMargin: CGFloat = 8
        let waveformWidth: CGFloat = 68
        let waveformHeight: CGFloat = 20
        let timeWidth: CGFloat = 46
        let stopDiameter: CGFloat = 32
        let sendDiameter: CGFloat = 32
        let contentGap: CGFloat = 3
        let buttonGap: CGFloat = 3

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
            x: horizontalMargin + 2,
            y: 3.5,
            width: size.width - (horizontalMargin + 2) * 2,
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

enum BadgeActionSymbol {
    case stop
    case send
}

struct BadgeActionSymbolGeometry: Equatable {
    let center: CGPoint
    let stopRect: CGRect
    let arrowBottom: CGPoint
    let arrowTip: CGPoint
    let arrowLeft: CGPoint
    let arrowRight: CGPoint
    let arrowLineWidth: CGFloat

    init(in bounds: CGRect, isFlipped: Bool = false) {
        let diameter = min(bounds.width, bounds.height)
        center = CGPoint(x: bounds.midX, y: bounds.midY)
        let stopSize = diameter * 0.25
        stopRect = CGRect(
            x: center.x - stopSize / 2,
            y: center.y - stopSize / 2,
            width: stopSize,
            height: stopSize
        )
        let arrowHalfHeight = diameter * 0.25
        let arrowHalfWidth = diameter * 0.21
        let upward: CGFloat = isFlipped ? -1 : 1
        arrowBottom = CGPoint(
            x: center.x,
            y: center.y - upward * arrowHalfHeight
        )
        arrowTip = CGPoint(
            x: center.x,
            y: center.y + upward * arrowHalfHeight
        )
        arrowLeft = CGPoint(
            x: center.x - arrowHalfWidth,
            y: center.y + upward * diameter * 0.06
        )
        arrowRight = CGPoint(
            x: center.x + arrowHalfWidth,
            y: center.y + upward * diameter * 0.06
        )
        arrowLineWidth = max(1.5, diameter / 16)
    }
}

private final class BadgeActionButton: NSButton {
    override var acceptsFirstResponder: Bool { false }

    var badgeSymbol: BadgeActionSymbol = .stop {
        didSet {
            needsDisplay = true
        }
    }

    var symbolColor: NSColor = .labelColor {
        didSet {
            needsDisplay = true
        }
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        layer?.masksToBounds = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let geometry = BadgeActionSymbolGeometry(
            in: bounds,
            isFlipped: isFlipped
        )
        symbolColor.withAlphaComponent(
            cell?.isHighlighted == true ? 0.72 : 1
        ).set()
        switch badgeSymbol {
        case .stop:
            NSBezierPath(
                roundedRect: geometry.stopRect,
                xRadius: geometry.stopRect.width * 0.16,
                yRadius: geometry.stopRect.height * 0.16
            ).fill()
        case .send:
            let arrow = NSBezierPath()
            arrow.lineWidth = geometry.arrowLineWidth
            arrow.lineCapStyle = .round
            arrow.lineJoinStyle = .round
            arrow.move(to: geometry.arrowBottom)
            arrow.line(to: geometry.arrowTip)
            arrow.move(to: geometry.arrowLeft)
            arrow.line(to: geometry.arrowTip)
            arrow.line(to: geometry.arrowRight)
            arrow.stroke()
        }
    }
}

@MainActor
private final class AudioWaveformView: NSView {
    private var history = AudioWaveformHistory()
    var color = BadgeThemePalette.palette(
        for: .defaultTheme
    ).waveform {
        didSet {
            needsDisplay = true
        }
    }

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
                ? color.withAlphaComponent(0.38)
                : color
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
