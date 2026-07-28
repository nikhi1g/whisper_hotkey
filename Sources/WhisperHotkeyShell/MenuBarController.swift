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

@MainActor
public struct MenuBarActions {
    public var showSetup: () -> Void
    public var cancelDictation: () -> Void
    public var copyLastDictation: () -> Void
    public var selectDictationMode: (HotkeyActivationMode) -> Void
    public var selectHotkey: (HotkeyKey) -> Void
    public var selectModel: (DictationModel) -> Void
    public var selectRecordingLimit: (RecordingLimit) -> Void
    public var restart: () -> Void
    public var quit: () -> Void

    public init(
        showSetup: @escaping () -> Void,
        cancelDictation: @escaping () -> Void,
        copyLastDictation: @escaping () -> Void,
        selectDictationMode: @escaping (HotkeyActivationMode) -> Void,
        selectHotkey: @escaping (HotkeyKey) -> Void,
        selectModel: @escaping (DictationModel) -> Void,
        selectRecordingLimit: @escaping (RecordingLimit) -> Void,
        restart: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        self.showSetup = showSetup
        self.cancelDictation = cancelDictation
        self.copyLastDictation = copyLastDictation
        self.selectDictationMode = selectDictationMode
        self.selectHotkey = selectHotkey
        self.selectModel = selectModel
        self.selectRecordingLimit = selectRecordingLimit
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
    private let dictationModeMenu = NSMenu(title: "Dictation Mode")
    private let dictationModeItem = NSMenuItem(
        title: "Dictation Mode",
        action: nil,
        keyEquivalent: ""
    )
    private var dictationModeItems: [HotkeyActivationMode: NSMenuItem] = [:]
    private let hotkeyMenu = NSMenu(title: "Dictation Key")
    private var hotkeyItems: [HotkeyKey: NSMenuItem] = [:]
    private let modelMenu = NSMenu(title: "Whisper Model")
    private var modelItems: [DictationModel: NSMenuItem] = [:]
    private let recordingLimitMenu = NSMenu(title: "Recording Limit")
    private let recordingLimitItem = NSMenuItem(
        title: "Recording Limit",
        action: nil,
        keyEquivalent: ""
    )
    private let restartItem = NSMenuItem(
        title: "Restart whisper_hotkey",
        action: #selector(restart),
        keyEquivalent: ""
    )
    private var recordingLimitItems: [RecordingLimit: NSMenuItem] = [:]
    private var availableModels: Set<DictationModel>

    public init(
        toggleDictationEnabled: Bool,
        selectedHotkey: HotkeyKey,
        selectedModel: DictationModel,
        recordingLimit: RecordingLimit,
        availableModels: Set<DictationModel>,
        hasLastDictation: Bool,
        actions: MenuBarActions
    ) {
        self.actions = actions
        self.availableModels = availableModels
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

        dictationModeItem.submenu = dictationModeMenu
        for mode in [HotkeyActivationMode.hold, .toggle] {
            let item = NSMenuItem(
                title: DictationModeMenuPresentation.optionTitle(for: mode),
                action: #selector(selectDictationMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            dictationModeMenu.addItem(item)
            dictationModeItems[mode] = item
        }
        menu.addItem(dictationModeItem)

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

        let modelItem = NSMenuItem(
            title: "Whisper Model",
            action: nil,
            keyEquivalent: ""
        )
        modelItem.submenu = modelMenu
        for model in DictationModel.allCases {
            let item = NSMenuItem(
                title: model.menuTitle,
                action: #selector(selectModel(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = model.rawValue
            item.state = model == selectedModel ? .on : .off
            modelMenu.addItem(item)
            modelItems[model] = item
        }
        menu.addItem(modelItem)

        recordingLimitItem.submenu = recordingLimitMenu
        for limit in RecordingLimit.allCases {
            let item = NSMenuItem(
                title: limit.displayName,
                action: #selector(selectRecordingLimit(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = limit.rawValue
            item.state = limit == recordingLimit ? .on : .off
            recordingLimitMenu.addItem(item)
            recordingLimitItems[limit] = item
        }
        menu.addItem(recordingLimitItem)

        let setupItem = NSMenuItem(
            title: "Open Setup…",
            action: #selector(showSetup),
            keyEquivalent: ""
        )
        setupItem.target = self
        menu.addItem(setupItem)
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
            selectedModel: selectedModel,
            recordingLimit: recordingLimit,
            availableModels: availableModels,
            hasLastDictation: hasLastDictation
        )
    }

    public func update(
        _ state: MenuBarState,
        toggleDictationEnabled: Bool,
        selectedHotkey: HotkeyKey,
        selectedModel: DictationModel,
        recordingLimit: RecordingLimit,
        availableModels: Set<DictationModel>,
        hasLastDictation: Bool
    ) {
        self.availableModels = availableModels
        let stateTitle = state.title(
            toggleDictationEnabled: toggleDictationEnabled,
            hotkey: selectedHotkey
        )
        stateItem.title = stateTitle
        cancelItem.isEnabled = state.canCancel
        copyLastDictationItem.isEnabled = hasLastDictation
        let selectedMode: HotkeyActivationMode =
            selectedHotkey.requiresToggleMode || toggleDictationEnabled
                ? .toggle
                : .hold
        dictationModeItem.title = DictationModeMenuPresentation.title(
            for: selectedMode
        )
        for (mode, item) in dictationModeItems {
            item.state = mode == selectedMode ? .on : .off
            item.isEnabled = mode != .hold || !selectedHotkey.requiresToggleMode
        }
        for (hotkey, item) in hotkeyItems {
            item.state = hotkey == selectedHotkey ? .on : .off
        }
        for (model, item) in modelItems {
            let installed = availableModels.contains(model)
            item.title = installed
                ? model.menuTitle
                : "\(model.menuTitle) (Not Installed)"
            item.state = model == selectedModel ? .on : .off
            item.isEnabled = installed && !state.canCancel
        }
        for (limit, item) in recordingLimitItems {
            item.state = limit == recordingLimit ? .on : .off
            item.isEnabled = !state.canCancel
        }
        recordingLimitItem.title = RecordingLimitMenuPresentation.title(
            for: recordingLimit
        )

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

    @objc private func selectDictationMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = HotkeyActivationMode(rawValue: rawValue)
        else {
            return
        }
        actions.selectDictationMode(mode)
    }

    @objc private func selectHotkey(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let hotkey = HotkeyKey(rawValue: rawValue)
        else {
            return
        }
        actions.selectHotkey(hotkey)
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let model = DictationModel(rawValue: rawValue),
              availableModels.contains(model)
        else {
            return
        }
        actions.selectModel(model)
    }

    @objc private func selectRecordingLimit(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let limit = RecordingLimit(rawValue: rawValue)
        else {
            return
        }
        actions.selectRecordingLimit(limit)
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

    func activateMenuItemForTesting(titled title: String) {
        guard let menu = statusItem.menu,
              let index = menu.items.firstIndex(where: { $0.title == title })
        else {
            return
        }
        menu.performActionForItem(at: index)
    }

    func activateDictationModeForTesting(_ mode: HotkeyActivationMode) {
        guard let item = dictationModeItems[mode],
              let index = dictationModeMenu.items.firstIndex(of: item)
        else {
            return
        }
        dictationModeMenu.performActionForItem(at: index)
    }

    func dictationModeStateForTesting(
        _ mode: HotkeyActivationMode
    ) -> NSControl.StateValue? {
        dictationModeItems[mode]?.state
    }

    func dictationModeIsEnabledForTesting(
        _ mode: HotkeyActivationMode
    ) -> Bool? {
        dictationModeItems[mode]?.isEnabled
    }
}

enum DictationModeMenuPresentation {
    static func title(for mode: HotkeyActivationMode) -> String {
        "Dictation Mode: \(optionTitle(for: mode))"
    }

    static func optionTitle(for mode: HotkeyActivationMode) -> String {
        switch mode {
        case .hold:
            "Press and Hold"
        case .toggle:
            "Toggle"
        }
    }
}

enum RecordingLimitMenuPresentation {
    static func title(for limit: RecordingLimit) -> String {
        "Recording Limit: \(limit.displayName)"
    }
}
