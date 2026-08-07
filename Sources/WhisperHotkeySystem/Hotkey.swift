@preconcurrency import CoreGraphics
import Foundation
import WhisperHotkeyCore

public enum MacVirtualKey {
    public static let c: Int64 = 8
    public static let v: Int64 = 9
    public static let x: Int64 = 7
    public static let returnKey: Int64 = 36
    public static let escape: Int64 = 53
    public static let keypadEnter: Int64 = 76
    public static let rightCommand: Int64 = 54
    public static let leftCommand: Int64 = 55
    public static let leftShift: Int64 = 56
    public static let capsLock: Int64 = 57
    public static let leftOption: Int64 = 58
    public static let leftControl: Int64 = 59
    public static let rightShift: Int64 = 60
    public static let rightOption: Int64 = 61
    public static let rightControl: Int64 = 62
    public static let function: Int64 = 63
}

public enum HotkeyKey: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case rightCommand
    case leftCommand
    case rightShift
    case leftShift
    case rightOption
    case leftOption
    case rightControl
    case leftControl
    case capsLock
    case function

    public var displayName: String {
        switch self {
        case .rightCommand:
            "Right Command"
        case .leftCommand:
            "Left Command"
        case .rightShift:
            "Right Shift"
        case .leftShift:
            "Left Shift"
        case .rightOption:
            "Right Option"
        case .leftOption:
            "Left Option"
        case .rightControl:
            "Right Control"
        case .leftControl:
            "Left Control"
        case .capsLock:
            "Caps Lock"
        case .function:
            "Fn / Globe"
        }
    }

    /// Apple's canonical modifier glyph, matched to how macOS itself labels
    /// these keys in menus and System Settings. `function` has no single
    /// standard glyph, so it is left textual.
    public var glyph: String? {
        switch self {
        case .rightCommand, .leftCommand:
            "\u{2318}"
        case .rightShift, .leftShift:
            "\u{21E7}"
        case .rightOption, .leftOption:
            "\u{2325}"
        case .rightControl, .leftControl:
            "\u{2303}"
        case .capsLock:
            "\u{21EA}"
        case .function:
            nil
        }
    }

    /// The popup menu wants the glyph prefixed; other call sites (user guide
    /// prose, cross-references) want `displayName` alone.
    public var menuTitle: String {
        guard let glyph else {
            return displayName
        }
        return "\(glyph) \(displayName)"
    }

    public var virtualKeyCode: Int64 {
        switch self {
        case .rightCommand:
            MacVirtualKey.rightCommand
        case .leftCommand:
            MacVirtualKey.leftCommand
        case .rightShift:
            MacVirtualKey.rightShift
        case .leftShift:
            MacVirtualKey.leftShift
        case .rightOption:
            MacVirtualKey.rightOption
        case .leftOption:
            MacVirtualKey.leftOption
        case .rightControl:
            MacVirtualKey.rightControl
        case .leftControl:
            MacVirtualKey.leftControl
        case .capsLock:
            MacVirtualKey.capsLock
        case .function:
            MacVirtualKey.function
        }
    }

    /// Caps Lock exposes a toggled state rather than a momentary press/release
    /// pair through the macOS flags-changed stream.
    public var requiresToggleMode: Bool {
        self == .capsLock
    }

    func modifierIsDown(in flags: CGEventFlags) -> Bool {
        guard let modifierFlag else {
            return false
        }
        return flags.contains(modifierFlag)
    }

    private var modifierFlag: CGEventFlags? {
        switch self {
        case .rightCommand, .leftCommand:
            .maskCommand
        case .rightShift, .leftShift:
            .maskShift
        case .rightOption, .leftOption:
            .maskAlternate
        case .rightControl, .leftControl:
            .maskControl
        case .capsLock:
            .maskAlphaShift
        case .function:
            .maskSecondaryFn
        }
    }
}

public enum GlobalKeyEventKind: Equatable, Sendable {
    case flagsChanged
    case keyDown
    case keyUp
}

public enum HotkeyActivationMode: String, Codable, Hashable, Sendable {
    case hold
    case toggle
    case pause
}

public struct GlobalKeyEvent: Equatable, Sendable {
    public let kind: GlobalKeyEventKind
    public let keyCode: Int64
    public let selectedModifierIsDown: Bool
    public let isAutoRepeat: Bool

    public init(
        kind: GlobalKeyEventKind,
        keyCode: Int64,
        selectedModifierIsDown: Bool,
        isAutoRepeat: Bool = false
    ) {
        self.kind = kind
        self.keyCode = keyCode
        self.selectedModifierIsDown = selectedModifierIsDown
        self.isAutoRepeat = isAutoRepeat
    }
}

public enum GlobalInputAction: Equatable, Sendable {
    case hotkey(HotkeyAction)
    case armHold
    case disarmHold
}

public struct GlobalInputRouting: Equatable, Sendable {
    public let consume: Bool
    public let actions: [GlobalInputAction]

    public init(consume: Bool, actions: [GlobalInputAction] = []) {
        self.consume = consume
        self.actions = actions
    }
}

/// A deterministic state reducer used by the event tap. Modifier events do not
/// auto-repeat, so once a selected-side press has been observed, the next
/// flags change for that key is its release even when the opposite side remains
/// down.
public struct GlobalInputReducer: Sendable {
    public private(set) var hotkey: HotkeyKey
    public private(set) var hotkeyIsDown = false
    public private(set) var completionKeyBeingConsumed: Int64?
    public private(set) var activationMode: HotkeyActivationMode
    private var bareHotkeyCandidate = false
    private var dictationHoldIsActive = false
    private var toggleSessionIsActive = false

    public init(
        activationMode: HotkeyActivationMode = .hold,
        hotkey: HotkeyKey = .rightCommand
    ) {
        self.hotkey = hotkey
        self.activationMode = Self.effectiveMode(
            activationMode,
            for: hotkey
        )
    }

    /// Reconfiguring the gesture is a cancellation boundary. This avoids
    /// carrying a half-finished physical hold or toggle session into the new
    /// interpretation.
    public mutating func setActivationMode(
        _ mode: HotkeyActivationMode
    ) -> HotkeyAction? {
        let effectiveMode = Self.effectiveMode(mode, for: hotkey)
        guard activationMode != effectiveMode else {
            return nil
        }
        let action: HotkeyAction? =
            dictationHoldIsActive || toggleSessionIsActive ? .cancel : nil
        activationMode = effectiveMode
        hotkeyIsDown = false
        bareHotkeyCandidate = false
        completionKeyBeingConsumed = nil
        dictationHoldIsActive = false
        toggleSessionIsActive = false
        return action
    }

    public mutating func setHotkey(_ newHotkey: HotkeyKey) -> HotkeyAction? {
        guard hotkey != newHotkey else {
            return nil
        }
        let action: HotkeyAction? =
            dictationHoldIsActive || toggleSessionIsActive ? .cancel : nil
        hotkey = newHotkey
        if newHotkey.requiresToggleMode && activationMode == .hold {
            activationMode = .toggle
        }
        hotkeyIsDown = false
        bareHotkeyCandidate = false
        completionKeyBeingConsumed = nil
        dictationHoldIsActive = false
        toggleSessionIsActive = false
        return action
    }

    /// The app state machine remains authoritative if a toggle press is
    /// rejected because transcription or insertion is already busy.
    public mutating func synchronizeToggleSession(isActive: Bool) {
        guard activationMode != .hold else {
            return
        }
        toggleSessionIsActive = isActive
    }

    public mutating func route(_ event: GlobalKeyEvent) -> GlobalInputRouting {
        if event.keyCode == hotkey.virtualKeyCode {
            if hotkey == .capsLock {
                return routeCapsLock(event)
            }
            return routeSelectedHotkey(event)
        }

        if event.keyCode == MacVirtualKey.escape {
            return routeCompletionKey(event, action: .cancel)
        }

        if event.keyCode == MacVirtualKey.returnKey
            || event.keyCode == MacVirtualKey.keypadEnter
        {
            return routeCompletionKey(event, action: .insertAndSubmit)
        }

        var actions: [GlobalInputAction] = []
        if hotkeyIsDown,
           event.kind == .keyDown || event.kind == .flagsChanged
        {
            actions.append(contentsOf: cancelBareHotkeyCandidate())
        }
        return GlobalInputRouting(consume: false, actions: actions)
    }

    /// Mouse clicks while the selected modifier is down remain ordinary
    /// modifier-click gestures, never dictation gestures.
    public mutating func routePointerDown() -> GlobalInputRouting {
        guard hotkeyIsDown else {
            return GlobalInputRouting(consume: false)
        }
        return GlobalInputRouting(
            consume: false,
            actions: cancelBareHotkeyCandidate()
        )
    }

    /// Called by the monitor's one-shot dwell timer. No model or microphone is
    /// started until this confirms the key is still a bare hold.
    public mutating func holdActivationFired() -> HotkeyAction? {
        guard activationMode == .hold,
              hotkeyIsDown,
              bareHotkeyCandidate,
              !dictationHoldIsActive
        else {
            return nil
        }
        dictationHoldIsActive = true
        return .pressed
    }

    /// Resets state after an event-tap disable or monitor stop. An active hold
    /// becomes exactly one cancellation.
    public mutating func reset() -> HotkeyAction? {
        let action: HotkeyAction? =
            dictationHoldIsActive || toggleSessionIsActive ? .cancel : nil
        hotkeyIsDown = false
        bareHotkeyCandidate = false
        dictationHoldIsActive = false
        toggleSessionIsActive = false
        completionKeyBeingConsumed = nil
        return action
    }

    private mutating func routeSelectedHotkey(
        _ event: GlobalKeyEvent
    ) -> GlobalInputRouting {
        switch activationMode {
        case .hold:
            routeHoldHotkey(event)
        case .toggle, .pause:
            routeToggleHotkey(event)
        }
    }

    private mutating func routeHoldHotkey(
        _ event: GlobalKeyEvent
    ) -> GlobalInputRouting {
        switch event.kind {
        case .flagsChanged:
            if hotkeyIsDown {
                return releaseHoldHotkey()
            }
            guard event.selectedModifierIsDown else {
                return GlobalInputRouting(consume: false)
            }
            return armHoldHotkey()

        case .keyDown:
            guard !hotkeyIsDown, !event.isAutoRepeat else {
                return GlobalInputRouting(consume: false)
            }
            return armHoldHotkey()

        case .keyUp:
            guard hotkeyIsDown else {
                return GlobalInputRouting(consume: false)
            }
            return releaseHoldHotkey()
        }
    }

    private mutating func armHoldHotkey() -> GlobalInputRouting {
        hotkeyIsDown = true
        bareHotkeyCandidate = true
        return GlobalInputRouting(
            consume: false,
            actions: [.armHold]
        )
    }

    private mutating func releaseHoldHotkey() -> GlobalInputRouting {
        hotkeyIsDown = false
        bareHotkeyCandidate = false
        var actions: [GlobalInputAction] = [.disarmHold]
        if dictationHoldIsActive {
            actions.append(.hotkey(.released))
        }
        dictationHoldIsActive = false
        return GlobalInputRouting(
            consume: false,
            actions: actions
        )
    }

    private mutating func routeToggleHotkey(
        _ event: GlobalKeyEvent
    ) -> GlobalInputRouting {
        switch event.kind {
        case .flagsChanged:
            if hotkeyIsDown {
                return releaseToggleHotkey()
            }
            guard event.selectedModifierIsDown else {
                return GlobalInputRouting(consume: false)
            }
            return armToggleHotkey()

        case .keyDown:
            guard !hotkeyIsDown, !event.isAutoRepeat else {
                return GlobalInputRouting(consume: false)
            }
            return armToggleHotkey()

        case .keyUp:
            guard hotkeyIsDown else {
                return GlobalInputRouting(consume: false)
            }
            return releaseToggleHotkey()
        }
    }

    private mutating func armToggleHotkey() -> GlobalInputRouting {
        hotkeyIsDown = true
        bareHotkeyCandidate = true
        return GlobalInputRouting(consume: false)
    }

    private mutating func releaseToggleHotkey() -> GlobalInputRouting {
        hotkeyIsDown = false
        let shouldToggle = bareHotkeyCandidate
        bareHotkeyCandidate = false
        guard shouldToggle else {
            return GlobalInputRouting(consume: false)
        }
        let action: HotkeyAction = toggleSessionIsActive ? .released : .pressed
        toggleSessionIsActive.toggle()
        return GlobalInputRouting(
            consume: false,
            actions: [.hotkey(action)]
        )
    }

    private mutating func routeCapsLock(
        _ event: GlobalKeyEvent
    ) -> GlobalInputRouting {
        guard event.kind == .flagsChanged else {
            return GlobalInputRouting(consume: false)
        }
        let action: HotkeyAction = toggleSessionIsActive ? .released : .pressed
        toggleSessionIsActive.toggle()
        return GlobalInputRouting(consume: false, actions: [.hotkey(action)])
    }

    private mutating func routeCompletionKey(
        _ event: GlobalKeyEvent,
        action: HotkeyAction
    ) -> GlobalInputRouting {
        switch event.kind {
        case .keyDown:
            if completionKeyBeingConsumed == event.keyCode {
                return GlobalInputRouting(consume: true)
            }
            if hotkeyIsDown, !dictationHoldIsActive {
                return GlobalInputRouting(
                    consume: false,
                    actions: cancelBareHotkeyCandidate()
                )
            }
            guard dictationHoldIsActive || toggleSessionIsActive else {
                return GlobalInputRouting(consume: false)
            }
            completionKeyBeingConsumed = event.keyCode
            bareHotkeyCandidate = false
            let shouldDisarmHold = dictationHoldIsActive
            dictationHoldIsActive = false
            toggleSessionIsActive = false
            var actions: [GlobalInputAction] = []
            if shouldDisarmHold {
                actions.append(.disarmHold)
            }
            actions.append(.hotkey(action))
            return GlobalInputRouting(consume: true, actions: actions)

        case .keyUp:
            guard completionKeyBeingConsumed == event.keyCode else {
                return GlobalInputRouting(consume: false)
            }
            completionKeyBeingConsumed = nil
            return GlobalInputRouting(consume: true)

        case .flagsChanged:
            return GlobalInputRouting(consume: false)
        }
    }

    private mutating func cancelBareHotkeyCandidate() -> [GlobalInputAction] {
        guard bareHotkeyCandidate else {
            return []
        }
        bareHotkeyCandidate = false
        var actions: [GlobalInputAction] = []
        if activationMode == .hold {
            actions.append(.disarmHold)
            if dictationHoldIsActive {
                dictationHoldIsActive = false
                actions.append(.hotkey(.cancel))
            }
        }
        return actions
    }

    private static func effectiveMode(
        _ mode: HotkeyActivationMode,
        for hotkey: HotkeyKey
    ) -> HotkeyActivationMode {
        hotkey.requiresToggleMode && mode == .hold ? .toggle : mode
    }
}

public enum GlobalHotkeyMonitorError: Error, Equatable, Sendable {
    case inputMonitoringNotGranted
    case eventTapCreationFailed
}

@MainActor
public final class GlobalHotkeyMonitor {
    public typealias Handler = @MainActor (
        _ action: HotkeyAction,
        _ insertionContext: DictationInsertionContext?,
        _ eventTimestampNanoseconds: UInt64
    ) -> Void

    private struct PendingInputEvent {
        let actions: [GlobalInputAction]
        let timestampNanoseconds: UInt64
    }

    private let captureInsertionContext: @MainActor () -> DictationInsertionContext?
    private let shouldIgnorePointerDown: @MainActor () -> Bool
    private let holdActivationDelay: Duration
    private let handler: Handler
    private var reducer = GlobalInputReducer()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pendingInputEvents: [PendingInputEvent] = []
    private var deliveryIsScheduled = false
    private var holdActivationTask: Task<Void, Never>?

    public init(
        contextProvider: AccessibilityContextProvider,
        shouldIgnorePointerDown: @escaping @MainActor () -> Bool = { false },
        holdActivationDelay: Duration = .milliseconds(150),
        handler: @escaping Handler
    ) {
        captureInsertionContext = {
            contextProvider.captureInsertionContext()
        }
        self.shouldIgnorePointerDown = shouldIgnorePointerDown
        self.holdActivationDelay = holdActivationDelay
        self.handler = handler
    }

    init(
        captureInsertionContext: @escaping @MainActor () -> DictationInsertionContext?,
        shouldIgnorePointerDown: @escaping @MainActor () -> Bool = { false },
        holdActivationDelay: Duration = .milliseconds(150),
        handler: @escaping Handler
    ) {
        self.captureInsertionContext = captureInsertionContext
        self.shouldIgnorePointerDown = shouldIgnorePointerDown
        self.holdActivationDelay = holdActivationDelay
        self.handler = handler
    }

    public var isRunning: Bool {
        eventTap != nil
    }

    public func start() throws {
        guard eventTap == nil else {
            return
        }
        let mask = eventMask(
            for: [
                .flagsChanged,
                .keyDown,
                .keyUp,
                .leftMouseDown,
                .rightMouseDown,
                .otherMouseDown,
            ]
        )
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: globalHotkeyEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            // Creating the tap is the authoritative check, so it is the one
            // this guards on. Accessibility alone is enough to create the tap
            // and to receive `flagsChanged`, so a preflight of
            // `kTCCServiceListenEvent` refused to start on a Mac whose
            // dictation modifier would have worked. Listen access is still
            // required -- it is what delivers `keyDown`, and so what makes
            // Return and Escape work -- but that is `SetupReadiness`'s
            // precondition to enforce, not this one. The preflight survives
            // only to name which of the two failures happened.
            throw CGPreflightListenEventAccess()
                ? GlobalHotkeyMonitorError.eventTapCreationFailed
                : GlobalHotkeyMonitorError.inputMonitoringNotGranted
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            throw GlobalHotkeyMonitorError.eventTapCreationFailed
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    public func stop() {
        cancelHoldActivation()
        if let action = reducer.reset() {
            enqueue(
                actions: [.hotkey(action)],
                timestampNanoseconds: DispatchTime.now().uptimeNanoseconds
            )
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
    }

    public func setActivationMode(_ mode: HotkeyActivationMode) {
        cancelHoldActivation()
        if let action = reducer.setActivationMode(mode) {
            enqueue(
                actions: [.hotkey(action)],
                timestampNanoseconds: DispatchTime.now().uptimeNanoseconds
            )
        }
    }

    public func setHotkey(_ hotkey: HotkeyKey) {
        cancelHoldActivation()
        if let action = reducer.setHotkey(hotkey) {
            enqueue(
                actions: [.hotkey(action)],
                timestampNanoseconds: DispatchTime.now().uptimeNanoseconds
            )
        }
    }

    public func synchronizeToggleSession(isActive: Bool) {
        reducer.synchronizeToggleSession(isActive: isActive)
    }

    func shouldConsumeTapEvent(
        type: CGEventType,
        event: CGEvent
    ) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            cancelHoldActivation()
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            if let action = reducer.reset() {
                enqueue(
                    actions: [.hotkey(action)],
                    timestampNanoseconds: event.timestamp
                )
            }
            return false
        }

        if type == .leftMouseDown
            || type == .rightMouseDown
            || type == .otherMouseDown
        {
            // The non-activating recording controller is part of dictation,
            // not a shortcut chord in the destination app. Let AppKit deliver
            // this click without cancelling the active modifier session.
            if shouldIgnorePointerDown() {
                return false
            }
            let routing = reducer.routePointerDown()
            enqueue(
                actions: routing.actions,
                timestampNanoseconds: event.timestamp
            )
            return routing.consume
        }

        guard let kind = GlobalKeyEventKind(type) else {
            return false
        }
        let rawEvent = GlobalKeyEvent(
            kind: kind,
            keyCode: event.getIntegerValueField(.keyboardEventKeycode),
            selectedModifierIsDown: reducer.hotkey.modifierIsDown(
                in: event.flags
            ),
            isAutoRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        )
        let routing = reducer.route(rawEvent)
        enqueue(
            actions: routing.actions,
            timestampNanoseconds: event.timestamp
        )
        return routing.consume
    }

    /// Event-tap callbacks must finish promptly. Delivery is deferred to an
    /// explicitly ordered queue so audio startup and AX inspection never run
    /// inside the tap callback while the physical event timestamp is retained.
    private func enqueue(
        actions: [GlobalInputAction],
        timestampNanoseconds: UInt64
    ) {
        guard !actions.isEmpty else {
            return
        }
        pendingInputEvents.append(
            PendingInputEvent(
                actions: actions,
                timestampNanoseconds: timestampNanoseconds
            )
        )
        guard !deliveryIsScheduled else {
            return
        }
        deliveryIsScheduled = true
        Task { @MainActor [self] in
            drainPendingInputEvents()
        }
    }

    private func drainPendingInputEvents() {
        while !pendingInputEvents.isEmpty {
            let pending = pendingInputEvents.removeFirst()
            deliver(pending)
        }
        deliveryIsScheduled = false
    }

    private func deliver(_ pending: PendingInputEvent) {
        for action in pending.actions {
            switch action {
            case .armHold:
                scheduleHoldActivation(
                    pressedAtNanoseconds: pending.timestampNanoseconds
                )
            case .disarmHold:
                cancelHoldActivation()
            case let .hotkey(hotkeyAction):
                let insertionContext: DictationInsertionContext?
                switch hotkeyAction {
                case .released, .stopAndInsert, .insertAndSubmit:
                    insertionContext = captureInsertionContext()
                case .pressed, .cancel:
                    insertionContext = nil
                }
                handler(
                    hotkeyAction,
                    insertionContext,
                    pending.timestampNanoseconds
                )
            }
        }
    }

    private func scheduleHoldActivation(
        pressedAtNanoseconds: UInt64
    ) {
        cancelHoldActivation()
        let activationDelay = holdActivationDelay
        holdActivationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: activationDelay)
            } catch {
                return
            }
            guard let self else {
                return
            }
            holdActivationTask = nil
            guard let action = reducer.holdActivationFired() else {
                return
            }
            handler(action, nil, pressedAtNanoseconds)
        }
    }

    private func cancelHoldActivation() {
        holdActivationTask?.cancel()
        holdActivationTask = nil
    }

    deinit {
        if let source = runLoopSource {
            CFRunLoopSourceInvalidate(source)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
    }
}

private func globalHotkeyEventTapCallback(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let monitorAddress = UInt(bitPattern: userInfo)
    let shouldConsume = MainActor.assumeIsolated {
        guard let monitorPointer = UnsafeMutableRawPointer(bitPattern: monitorAddress) else {
            return false
        }
        let monitor = Unmanaged<GlobalHotkeyMonitor>
            .fromOpaque(monitorPointer)
            .takeUnretainedValue()
        return monitor.shouldConsumeTapEvent(type: type, event: event)
    }
    return shouldConsume ? nil : Unmanaged.passUnretained(event)
}

private extension GlobalKeyEventKind {
    init?(_ eventType: CGEventType) {
        switch eventType {
        case .flagsChanged:
            self = .flagsChanged
        case .keyDown:
            self = .keyDown
        case .keyUp:
            self = .keyUp
        default:
            return nil
        }
    }
}

private func eventMask(for types: [CGEventType]) -> CGEventMask {
    types.reduce(CGEventMask(0)) { mask, type in
        mask | (CGEventMask(1) << type.rawValue)
    }
}
