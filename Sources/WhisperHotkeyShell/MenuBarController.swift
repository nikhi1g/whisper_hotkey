import AppKit
import WhisperHotkeySystem

public enum MenuBarState: Equatable, Sendable {
    case starting
    case idle
    case preparing
    case listening
    case transcribing
    case inserting
    case cancelled
    case unavailable
    case failed

    public var symbolName: String {
        switch self {
        case .starting:
            "mic.circle"
        case .idle:
            "mic"
        case .preparing:
            "mic.circle.fill"
        case .listening:
            "mic.fill"
        case .transcribing:
            "waveform"
        case .inserting:
            "text.cursor"
        case .cancelled:
            "xmark.circle"
        case .unavailable:
            "mic.slash"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    public var title: String {
        title(toggleDictationEnabled: false, hotkey: .rightCommand)
    }

    public func title(
        toggleDictationEnabled: Bool,
        hotkey: HotkeyKey
    ) -> String {
        switch self {
        case .starting:
            "Starting…"
        case .idle:
            toggleDictationEnabled
                ? "Ready: press \(hotkey.displayName)"
                : "Ready: hold \(hotkey.displayName)"
        case .preparing:
            "Preparing microphone…"
        case .listening:
            "Listening…"
        case .transcribing:
            "Transcribing…"
        case .inserting:
            "Inserting…"
        case .cancelled:
            "Cancelled"
        case .unavailable:
            "Setup needed"
        case .failed:
            "Dictation error"
        }
    }

    public var canCancel: Bool {
        switch self {
        case .preparing, .listening, .transcribing, .inserting:
            true
        case .starting, .idle, .cancelled, .unavailable, .failed:
            false
        }
    }
}

@MainActor
public struct MenuBarActions {
    public var showSetup: () -> Void
    public var cancelDictation: () -> Void
    public var copyLastDictation: () -> Void
    public var toggleDictationMode: () -> Void
    public var selectHotkey: (HotkeyKey) -> Void
    public var quit: () -> Void

    public init(
        showSetup: @escaping () -> Void,
        cancelDictation: @escaping () -> Void,
        copyLastDictation: @escaping () -> Void,
        toggleDictationMode: @escaping () -> Void,
        selectHotkey: @escaping (HotkeyKey) -> Void,
        quit: @escaping () -> Void
    ) {
        self.showSetup = showSetup
        self.cancelDictation = cancelDictation
        self.copyLastDictation = copyLastDictation
        self.toggleDictationMode = toggleDictationMode
        self.selectHotkey = selectHotkey
        self.quit = quit
    }
}

@MainActor
public final class MenuBarController: NSObject {
    private let actions: MenuBarActions
    private let statusItem: NSStatusItem
    private let stateItem = NSMenuItem(
        title: MenuBarState.starting.title,
        action: nil,
        keyEquivalent: ""
    )
    private let cancelItem = NSMenuItem(
        title: "Cancel Dictation",
        action: #selector(cancelDictation),
        keyEquivalent: ""
    )
    private let copyLastDictationItem = NSMenuItem(
        title: "Copy Last Dictation",
        action: #selector(copyLastDictation),
        keyEquivalent: ""
    )
    private let toggleModeItem = NSMenuItem(
        title: "Right Command Toggles Dictation",
        action: #selector(toggleDictationMode),
        keyEquivalent: ""
    )
    private let hotkeyMenu = NSMenu(title: "Dictation Key")
    private var hotkeyItems: [HotkeyKey: NSMenuItem] = [:]

    public init(
        toggleDictationEnabled: Bool,
        selectedHotkey: HotkeyKey,
        hasLastDictation: Bool,
        actions: MenuBarActions
    ) {
        self.actions = actions
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        let menu = NSMenu()
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())

        cancelItem.target = self
        menu.addItem(cancelItem)

        copyLastDictationItem.target = self
        copyLastDictationItem.isEnabled = hasLastDictation
        menu.addItem(copyLastDictationItem)

        toggleModeItem.target = self
        toggleModeItem.state = toggleDictationEnabled ? .on : .off
        menu.addItem(toggleModeItem)

        let hotkeyItem = NSMenuItem(
            title: "Dictation Key",
            action: nil,
            keyEquivalent: ""
        )
        hotkeyItem.submenu = hotkeyMenu
        for hotkey in HotkeyKey.allCases {
            let item = NSMenuItem(
                title: hotkey.displayName,
                action: #selector(selectHotkey(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = hotkey.rawValue
            item.state = hotkey == selectedHotkey ? .on : .off
            hotkeyMenu.addItem(item)
            hotkeyItems[hotkey] = item
        }
        menu.addItem(hotkeyItem)

        let setupItem = NSMenuItem(
            title: "Open Setup…",
            action: #selector(showSetup),
            keyEquivalent: ""
        )
        setupItem.target = self
        menu.addItem(setupItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit whisper_hotkey",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        update(
            .starting,
            toggleDictationEnabled: toggleDictationEnabled,
            selectedHotkey: selectedHotkey,
            hasLastDictation: hasLastDictation
        )
    }

    public func update(
        _ state: MenuBarState,
        toggleDictationEnabled: Bool,
        selectedHotkey: HotkeyKey,
        hasLastDictation: Bool
    ) {
        let stateTitle = state.title(
            toggleDictationEnabled: toggleDictationEnabled,
            hotkey: selectedHotkey
        )
        stateItem.title = stateTitle
        cancelItem.isEnabled = state.canCancel
        copyLastDictationItem.isEnabled = hasLastDictation
        toggleModeItem.state = toggleDictationEnabled ? .on : .off
        toggleModeItem.title = "\(selectedHotkey.displayName) Toggles Dictation"
        toggleModeItem.isEnabled = !selectedHotkey.requiresToggleMode
        for (hotkey, item) in hotkeyItems {
            item.state = hotkey == selectedHotkey ? .on : .off
        }

        guard let button = statusItem.button else {
            return
        }
        let description = "whisper_hotkey: \(stateTitle)"
        let image = NSImage(
            systemSymbolName: state.symbolName,
            accessibilityDescription: description
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        )
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        button.title = image == nil ? "W" : ""
        button.toolTip = description
        button.setAccessibilityLabel(description)
    }

    @objc private func showSetup() {
        actions.showSetup()
    }

    @objc private func cancelDictation() {
        actions.cancelDictation()
    }

    @objc private func copyLastDictation() {
        actions.copyLastDictation()
    }

    @objc private func toggleDictationMode() {
        actions.toggleDictationMode()
    }

    @objc private func selectHotkey(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let hotkey = HotkeyKey(rawValue: rawValue)
        else {
            return
        }
        actions.selectHotkey(hotkey)
    }

    @objc private func quit() {
        actions.quit()
    }
}
