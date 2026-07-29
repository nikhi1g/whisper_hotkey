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
    public var showAdvancedSettings: () -> Void
    public var cancelDictation: () -> Void
    public var copyLastDictation: () -> Void
    public var restart: () -> Void
    public var quit: () -> Void

    public init(
        showSetup: @escaping () -> Void,
        showAdvancedSettings: @escaping () -> Void,
        cancelDictation: @escaping () -> Void,
        copyLastDictation: @escaping () -> Void,
        restart: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        self.showSetup = showSetup
        self.showAdvancedSettings = showAdvancedSettings
        self.cancelDictation = cancelDictation
        self.copyLastDictation = copyLastDictation
        self.restart = restart
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
    private let setupItem = NSMenuItem(
        title: "Open Setup…",
        action: #selector(showSetup),
        keyEquivalent: ""
    )
    private let advancedSettingsItem = NSMenuItem(
        title: "Settings…",
        action: #selector(showAdvancedSettings),
        keyEquivalent: ","
    )
    private let restartItem = NSMenuItem(
        title: "Restart whisper_hotkey",
        action: #selector(restart),
        keyEquivalent: ""
    )

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
        cancelItem.isHidden = true
        menu.addItem(cancelItem)

        copyLastDictationItem.target = self
        copyLastDictationItem.isEnabled = hasLastDictation
        copyLastDictationItem.isHidden = !hasLastDictation
        menu.addItem(copyLastDictationItem)

        setupItem.target = self
        menu.addItem(setupItem)

        advancedSettingsItem.target = self
        menu.addItem(advancedSettingsItem)
        menu.addItem(.separator())

        restartItem.target = self
        menu.addItem(restartItem)

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
        cancelItem.isHidden = !state.canCancel
        copyLastDictationItem.isEnabled = hasLastDictation
        copyLastDictationItem.isHidden = !hasLastDictation
        setupItem.isEnabled = !state.canCancel
        advancedSettingsItem.isEnabled = !state.canCancel

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

    @objc private func showAdvancedSettings() {
        actions.showAdvancedSettings()
    }

    @objc private func cancelDictation() {
        actions.cancelDictation()
    }

    @objc private func copyLastDictation() {
        actions.copyLastDictation()
    }

    @objc private func quit() {
        actions.quit()
    }

    @objc private func restart() {
        actions.restart()
    }

    var menuItemTitlesForTesting: [String] {
        statusItem.menu?.items.map(\.title) ?? []
    }

    var visibleMenuItemTitlesForTesting: [String] {
        statusItem.menu?.items.filter { !$0.isHidden }.map(\.title) ?? []
    }

    func activateMenuItemForTesting(titled title: String) {
        guard let menu = statusItem.menu,
              let index = menu.items.firstIndex(where: { $0.title == title })
        else {
            return
        }
        menu.performActionForItem(at: index)
    }

    func menuItemIsEnabledForTesting(titled title: String) -> Bool? {
        statusItem.menu?.items.first(where: { $0.title == title })?.isEnabled
    }

}
