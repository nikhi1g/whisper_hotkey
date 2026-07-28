@preconcurrency import CoreGraphics
import Foundation
import WhisperHotkeyCore

public enum MacVirtualKey {
    public static let c: Int64 = 8
    public static let v: Int64 = 9
    public static let x: Int64 = 7
    public static let escape: Int64 = 53
    public static let rightCommand: Int64 = 54
}

public enum GlobalKeyEventKind: Equatable, Sendable {
    case flagsChanged
    case keyDown
    case keyUp
}

public enum HotkeyActivationMode: String, Codable, Equatable, Sendable {
    case hold
    case toggle
}

public struct GlobalKeyEvent: Equatable, Sendable {
    public let kind: GlobalKeyEventKind
    public let keyCode: Int64
    public let commandIsDown: Bool
    public let isAutoRepeat: Bool
    public let isSynthetic: Bool

    public init(
        kind: GlobalKeyEventKind,
        keyCode: Int64,
        commandIsDown: Bool,
        isAutoRepeat: Bool = false,
        isSynthetic: Bool = false
    ) {
        self.kind = kind
        self.keyCode = keyCode
        self.commandIsDown = commandIsDown
        self.isAutoRepeat = isAutoRepeat
        self.isSynthetic = isSynthetic
    }
}

public enum GlobalInputAction: Equatable, Sendable {
    case hotkey(HotkeyAction)
    case manualPaste
    case copyOrCut
}

public struct GlobalInputRouting: Equatable, Sendable {
    public let consume: Bool
    public let actions: [GlobalInputAction]

    public init(consume: Bool, actions: [GlobalInputAction] = []) {
        self.consume = consume
        self.actions = actions
    }
}

/// A deterministic state reducer used by the event tap. Right Command modifier
/// events do not auto-repeat, so once a press has been observed, the next
/// Right Command flags change is its release even when Left Command remains down.
public struct GlobalInputReducer: Sendable {
    public private(set) var rightCommandIsDown = false
    public private(set) var escapeIsBeingConsumed = false
    public private(set) var activationMode: HotkeyActivationMode
    private var hotkeyIsActive = false
    private var toggleSessionIsActive = false

    public init(activationMode: HotkeyActivationMode = .hold) {
        self.activationMode = activationMode
    }

    /// Reconfiguring the gesture is a cancellation boundary. This avoids
    /// carrying a half-finished physical hold or toggle session into the new
    /// interpretation.
    public mutating func setActivationMode(
        _ mode: HotkeyActivationMode
    ) -> HotkeyAction? {
        guard activationMode != mode else {
            return nil
        }
        let action: HotkeyAction? =
            hotkeyIsActive || toggleSessionIsActive ? .cancel : nil
        activationMode = mode
        rightCommandIsDown = false
        escapeIsBeingConsumed = false
        hotkeyIsActive = false
        toggleSessionIsActive = false
        return action
    }

    /// The app state machine remains authoritative if a toggle press is
    /// rejected because transcription or insertion is already busy.
    public mutating func synchronizeToggleSession(isActive: Bool) {
        guard activationMode == .toggle else {
            return
        }
        toggleSessionIsActive = isActive
    }

    public mutating func route(_ event: GlobalKeyEvent) -> GlobalInputRouting {
        if event.keyCode == MacVirtualKey.rightCommand {
            return routeRightCommand(event)
        }

        if event.keyCode == MacVirtualKey.escape {
            return routeEscape(event)
        }

        // Right Command is dedicated to dictation for its entire physical
        // hold. This remains true after Escape cancels the active dictation,
        // until the matching Right Command release arrives.
        guard !rightCommandIsDown else {
            return GlobalInputRouting(consume: true)
        }

        guard !event.isSynthetic else {
            return GlobalInputRouting(consume: false)
        }

        guard event.kind == .keyDown, event.commandIsDown, !event.isAutoRepeat else {
            return GlobalInputRouting(consume: false)
        }

        switch event.keyCode {
        case MacVirtualKey.v:
            return GlobalInputRouting(consume: false, actions: [.manualPaste])
        case MacVirtualKey.c, MacVirtualKey.x:
            return GlobalInputRouting(consume: false, actions: [.copyOrCut])
        default:
            return GlobalInputRouting(consume: false)
        }
    }

    /// Resets state after an event-tap disable or monitor stop. An active hold
    /// becomes exactly one cancellation.
    public mutating func reset() -> HotkeyAction? {
        let action: HotkeyAction? =
            hotkeyIsActive || toggleSessionIsActive ? .cancel : nil
        rightCommandIsDown = false
        hotkeyIsActive = false
        toggleSessionIsActive = false
        escapeIsBeingConsumed = false
        return action
    }

    private mutating func routeRightCommand(
        _ event: GlobalKeyEvent
    ) -> GlobalInputRouting {
        switch activationMode {
        case .hold:
            routeHoldRightCommand(event)
        case .toggle:
            routeToggleRightCommand(event)
        }
    }

    private mutating func routeHoldRightCommand(
        _ event: GlobalKeyEvent
    ) -> GlobalInputRouting {
        switch event.kind {
        case .flagsChanged:
            if rightCommandIsDown {
                rightCommandIsDown = false
                let action: [GlobalInputAction] = hotkeyIsActive
                    ? [.hotkey(.released)]
                    : []
                hotkeyIsActive = false
                return GlobalInputRouting(consume: true, actions: action)
            }
            guard event.commandIsDown else {
                return GlobalInputRouting(consume: true)
            }
            rightCommandIsDown = true
            guard !escapeIsBeingConsumed else {
                hotkeyIsActive = false
                return GlobalInputRouting(consume: true)
            }
            hotkeyIsActive = true
            return GlobalInputRouting(consume: true, actions: [.hotkey(.pressed)])

        case .keyDown:
            guard !rightCommandIsDown, !event.isAutoRepeat else {
                return GlobalInputRouting(consume: true)
            }
            rightCommandIsDown = true
            guard !escapeIsBeingConsumed else {
                hotkeyIsActive = false
                return GlobalInputRouting(consume: true)
            }
            hotkeyIsActive = true
            return GlobalInputRouting(consume: true, actions: [.hotkey(.pressed)])

        case .keyUp:
            guard rightCommandIsDown else {
                return GlobalInputRouting(consume: true)
            }
            rightCommandIsDown = false
            let action: [GlobalInputAction] = hotkeyIsActive
                ? [.hotkey(.released)]
                : []
            hotkeyIsActive = false
            return GlobalInputRouting(consume: true, actions: action)
        }
    }

    private mutating func routeToggleRightCommand(
        _ event: GlobalKeyEvent
    ) -> GlobalInputRouting {
        switch event.kind {
        case .flagsChanged:
            if rightCommandIsDown {
                rightCommandIsDown = false
                return GlobalInputRouting(consume: true)
            }
            guard event.commandIsDown else {
                return GlobalInputRouting(consume: true)
            }
            rightCommandIsDown = true
            return togglePressRouting()

        case .keyDown:
            guard !rightCommandIsDown, !event.isAutoRepeat else {
                return GlobalInputRouting(consume: true)
            }
            rightCommandIsDown = true
            return togglePressRouting()

        case .keyUp:
            rightCommandIsDown = false
            return GlobalInputRouting(consume: true)
        }
    }

    private mutating func togglePressRouting() -> GlobalInputRouting {
        guard !escapeIsBeingConsumed else {
            toggleSessionIsActive = false
            return GlobalInputRouting(consume: true)
        }
        let action: HotkeyAction = toggleSessionIsActive ? .released : .pressed
        toggleSessionIsActive.toggle()
        return GlobalInputRouting(consume: true, actions: [.hotkey(action)])
    }

    private mutating func routeEscape(_ event: GlobalKeyEvent) -> GlobalInputRouting {
        switch event.kind {
        case .keyDown:
            if escapeIsBeingConsumed {
                return GlobalInputRouting(consume: true)
            }
            guard rightCommandIsDown || toggleSessionIsActive else {
                return GlobalInputRouting(consume: false)
            }
            escapeIsBeingConsumed = true
            guard hotkeyIsActive || toggleSessionIsActive else {
                return GlobalInputRouting(consume: true)
            }
            hotkeyIsActive = false
            toggleSessionIsActive = false
            return GlobalInputRouting(consume: true, actions: [.hotkey(.cancel)])

        case .keyUp:
            guard escapeIsBeingConsumed else {
                return GlobalInputRouting(consume: false)
            }
            escapeIsBeingConsumed = false
            return GlobalInputRouting(consume: true)

        case .flagsChanged:
            return GlobalInputRouting(consume: rightCommandIsDown)
        }
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
        _ releaseTarget: ReleaseTarget?,
        _ eventTimestampNanoseconds: UInt64
    ) -> Void

    private struct PendingInputEvent {
        let actions: [GlobalInputAction]
        let timestampNanoseconds: UInt64
    }

    /// Synthetic key events are tagged so this monitor never treats the
    /// service's own Cmd-V as the manual paste that consumes a lease.
    public static let syntheticEventMarker: Int64 = 0x5748_4B59

    private let captureReleaseTarget: @MainActor () -> ReleaseTarget?
    private let clipboard: ClipboardTransactionController
    private let handler: Handler
    private var reducer = GlobalInputReducer()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pendingInputEvents: [PendingInputEvent] = []
    private var deliveryIsScheduled = false

    public init(
        targetProvider: AccessibilityTargetProvider,
        clipboard: ClipboardTransactionController,
        handler: @escaping Handler
    ) {
        captureReleaseTarget = {
            targetProvider.captureFocusedTarget()
        }
        self.clipboard = clipboard
        self.handler = handler
    }

    init(
        captureReleaseTarget: @escaping @MainActor () -> ReleaseTarget?,
        clipboard: ClipboardTransactionController,
        handler: @escaping Handler
    ) {
        self.captureReleaseTarget = captureReleaseTarget
        self.clipboard = clipboard
        self.handler = handler
    }

    public var isRunning: Bool {
        eventTap != nil
    }

    public func start() throws {
        guard eventTap == nil else {
            return
        }
        guard CGPreflightListenEventAccess() else {
            throw GlobalHotkeyMonitorError.inputMonitoringNotGranted
        }

        let mask = eventMask(for: [.flagsChanged, .keyDown, .keyUp])
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: globalHotkeyEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw GlobalHotkeyMonitorError.eventTapCreationFailed
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
        if let action = reducer.setActivationMode(mode) {
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

        guard let kind = GlobalKeyEventKind(type) else {
            return false
        }
        let rawEvent = GlobalKeyEvent(
            kind: kind,
            keyCode: event.getIntegerValueField(.keyboardEventKeycode),
            commandIsDown: event.flags.contains(.maskCommand),
            isAutoRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            isSynthetic: event.getIntegerValueField(.eventSourceUserData)
                == Self.syntheticEventMarker
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
            case .hotkey(.released):
                handler(
                    .released,
                    captureReleaseTarget(),
                    pending.timestampNanoseconds
                )
            case let .hotkey(hotkeyAction):
                handler(hotkeyAction, nil, pending.timestampNanoseconds)
            case .manualPaste:
                clipboard.manualPasteWillDispatch()
            case .copyOrCut:
                clipboard.copyOrCutWillDispatch()
            }
        }
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
