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

    public init() {}

    public mutating func route(_ event: GlobalKeyEvent) -> GlobalInputRouting {
        if event.keyCode == MacVirtualKey.rightCommand {
            return routeRightCommand(event)
        }

        if event.keyCode == MacVirtualKey.escape {
            return routeEscape(event)
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
        let action: HotkeyAction? = rightCommandIsDown ? .cancel : nil
        rightCommandIsDown = false
        escapeIsBeingConsumed = false
        return action
    }

    private mutating func routeRightCommand(
        _ event: GlobalKeyEvent
    ) -> GlobalInputRouting {
        switch event.kind {
        case .flagsChanged:
            if rightCommandIsDown {
                rightCommandIsDown = false
                return GlobalInputRouting(consume: true, actions: [.hotkey(.released)])
            }
            guard event.commandIsDown else {
                return GlobalInputRouting(consume: true)
            }
            rightCommandIsDown = true
            return GlobalInputRouting(consume: true, actions: [.hotkey(.pressed)])

        case .keyDown:
            guard !rightCommandIsDown, !event.isAutoRepeat else {
                return GlobalInputRouting(consume: true)
            }
            rightCommandIsDown = true
            return GlobalInputRouting(consume: true, actions: [.hotkey(.pressed)])

        case .keyUp:
            guard rightCommandIsDown else {
                return GlobalInputRouting(consume: true)
            }
            rightCommandIsDown = false
            return GlobalInputRouting(consume: true, actions: [.hotkey(.released)])
        }
    }

    private mutating func routeEscape(_ event: GlobalKeyEvent) -> GlobalInputRouting {
        switch event.kind {
        case .keyDown:
            if escapeIsBeingConsumed {
                return GlobalInputRouting(consume: true)
            }
            guard rightCommandIsDown else {
                return GlobalInputRouting(consume: false)
            }
            escapeIsBeingConsumed = true
            rightCommandIsDown = false
            return GlobalInputRouting(consume: true, actions: [.hotkey(.cancel)])

        case .keyUp:
            guard escapeIsBeingConsumed else {
                return GlobalInputRouting(consume: false)
            }
            escapeIsBeingConsumed = false
            return GlobalInputRouting(consume: true)

        case .flagsChanged:
            return GlobalInputRouting(consume: false)
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
        _ releaseTarget: ReleaseTarget?
    ) -> Void

    /// Synthetic key events are tagged so this monitor never treats the
    /// service's own Cmd-V as the manual paste that consumes a lease.
    public static let syntheticEventMarker: Int64 = 0x5748_4B59

    private let targetProvider: AccessibilityTargetProvider
    private let clipboard: ClipboardTransactionController
    private let handler: Handler
    private var reducer = GlobalInputReducer()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    public init(
        targetProvider: AccessibilityTargetProvider,
        clipboard: ClipboardTransactionController,
        handler: @escaping Handler
    ) {
        self.targetProvider = targetProvider
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
            handler(action, nil)
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

    fileprivate func shouldConsumeTapEvent(
        type: CGEventType,
        event: CGEvent
    ) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            if let action = reducer.reset() {
                handler(action, nil)
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
        for action in routing.actions {
            switch action {
            case .hotkey(.released):
                handler(.released, targetProvider.captureFocusedTarget())
            case let .hotkey(hotkeyAction):
                handler(hotkeyAction, nil)
            case .manualPaste:
                clipboard.manualPasteWillDispatch()
            case .copyOrCut:
                clipboard.copyOrCutWillDispatch()
            }
        }
        return routing.consume
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
