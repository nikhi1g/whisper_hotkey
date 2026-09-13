import AppKit
import WhisperHotkeyCore
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

public struct MenuBarMicrophoneState: Equatable, Sendable {
    public let selection: MicrophoneSelection
    public let devices: [MicrophoneDevice]
    public let automaticDeviceName: String?
    public let configurationEnabled: Bool

    public init(
        selection: MicrophoneSelection,
        devices: [MicrophoneDevice],
        automaticDeviceName: String? = nil,
        configurationEnabled: Bool
    ) {
        self.selection = selection
        self.devices = devices
        self.automaticDeviceName = automaticDeviceName
        self.configurationEnabled = configurationEnabled
    }
}

@MainActor
public struct MenuBarActions {
    public var showSetup: () -> Void
    public var showAdvancedSettings: () -> Void
    public var cancelDictation: () -> Void
    public var copyLastDictation: () -> Void
    public var selectMicrophone: (MicrophoneSelection) -> Void
    public var microphoneState: () -> MenuBarMicrophoneState
    public var restart: () -> Void
    public var quit: () -> Void

    public init(
        showSetup: @escaping () -> Void,
        showAdvancedSettings: @escaping () -> Void,
        cancelDictation: @escaping () -> Void,
        copyLastDictation: @escaping () -> Void,
        selectMicrophone: @escaping (MicrophoneSelection) -> Void = { _ in },
        microphoneState: @escaping () -> MenuBarMicrophoneState = {
            MenuBarMicrophoneState(
                selection: .automatic,
                devices: [],
                configurationEnabled: true
            )
        },
        restart: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        self.showSetup = showSetup
        self.showAdvancedSettings = showAdvancedSettings
        self.cancelDictation = cancelDictation
        self.copyLastDictation = copyLastDictation
        self.selectMicrophone = selectMicrophone
        self.microphoneState = microphoneState
        self.restart = restart
        self.quit = quit
    }
}

@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate {
    private let actions: MenuBarActions
    private var microphoneDevicesByUID: [String: MicrophoneDevice] = [:]
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
    private let microphoneItem = NSMenuItem(
        title: "Microphone",
        action: nil,
        keyEquivalent: ""
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
        menu.delegate = self
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
        menu.addItem(microphoneItem)
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
        microphoneItem.isEnabled = !state.canCancel

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

    public func menuWillOpen(_ menu: NSMenu) {
        rebuildMicrophoneMenu()
    }

    private func rebuildMicrophoneMenu() {
        let state = actions.microphoneState()
        let submenu = NSMenu(title: "Microphone")
        microphoneDevicesByUID = Dictionary(
            uniqueKeysWithValues: state.devices.map { ($0.uid, $0) }
        )
        let automaticName = state.automaticDeviceName
            ?? state.devices.first(where: \.isSystemDefault)?.name
        let automaticTitle = automaticName.map {
            "Automatic (\($0))"
        } ?? "Automatic"
        let automatic = NSMenuItem(
            title: automaticTitle,
            action: #selector(selectMicrophone(_:)),
            keyEquivalent: ""
        )
        automatic.target = self
        automatic.state = state.selection.isAutomatic ? .on : .off
        submenu.addItem(automatic)

        for device in state.devices {
            let suffix = device.isSystemDefault ? " (System Default)" : ""
            let item = NSMenuItem(
                title: device.name + suffix,
                action: #selector(selectMicrophone(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = device.uid
            item.state = state.selection.deviceUID == device.uid ? .on : .off
            submenu.addItem(item)
        }

        if let selectedUID = state.selection.deviceUID,
           microphoneDevicesByUID[selectedUID] == nil
        {
            let unavailable = NSMenuItem(
                title: (state.selection.displayName ?? "Selected Microphone")
                    + " (Unavailable)",
                action: nil,
                keyEquivalent: ""
            )
            unavailable.state = .on
            unavailable.isEnabled = false
            submenu.addItem(unavailable)
        }

        microphoneItem.submenu = submenu
        microphoneItem.isEnabled = state.configurationEnabled
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

    @objc private func selectMicrophone(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else {
            actions.selectMicrophone(.automatic)
            rebuildMicrophoneMenu()
            return
        }
        guard let device = microphoneDevicesByUID[uid] else {
            return
        }
        actions.selectMicrophone(
            MicrophoneSelection(deviceUID: device.uid, displayName: device.name)
        )
        rebuildMicrophoneMenu()
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

    var microphoneMenuItemTitlesForTesting: [String] {
        rebuildMicrophoneMenu()
        return microphoneItem.submenu?.items.map(\.title) ?? []
    }

    func activateMicrophoneItemForTesting(titled title: String) {
        rebuildMicrophoneMenu()
        guard let submenu = microphoneItem.submenu,
              let index = submenu.items.firstIndex(where: { $0.title == title })
        else {
            return
        }
        submenu.performActionForItem(at: index)
    }

    func menuItemIsEnabledForTesting(titled title: String) -> Bool? {
        statusItem.menu?.items.first(where: { $0.title == title })?.isEnabled
    }

}
