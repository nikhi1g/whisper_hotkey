import AppKit
import WhisperHotkeyCore
import WhisperHotkeySystem

public struct AdvancedSettingsState: Equatable, Sendable {
    public let selectedHotkey: HotkeyKey
    public let activationMode: HotkeyActivationMode
    public let selectedModel: DictationModel
    public let recordingLimit: RecordingLimit
    public let availableModels: Set<DictationModel>
    public let configurationEnabled: Bool

    public init(
        selectedHotkey: HotkeyKey,
        activationMode: HotkeyActivationMode,
        selectedModel: DictationModel,
        recordingLimit: RecordingLimit,
        availableModels: Set<DictationModel>,
        configurationEnabled: Bool
    ) {
        self.selectedHotkey = selectedHotkey
        self.activationMode = activationMode
        self.selectedModel = selectedModel
        self.recordingLimit = recordingLimit
        self.availableModels = availableModels
        self.configurationEnabled = configurationEnabled
    }
}

@MainActor
public struct AdvancedSettingsActions {
    public var selectDictationMode: (HotkeyActivationMode) -> Void
    public var selectHotkey: (HotkeyKey) -> Void
    public var selectModel: (DictationModel) -> Void
    public var selectRecordingLimit: (RecordingLimit) -> Void
    public var loginItemChanged: () -> Void

    public init(
        selectDictationMode: @escaping (HotkeyActivationMode) -> Void,
        selectHotkey: @escaping (HotkeyKey) -> Void,
        selectModel: @escaping (DictationModel) -> Void,
        selectRecordingLimit: @escaping (RecordingLimit) -> Void,
        loginItemChanged: @escaping () -> Void = {}
    ) {
        self.selectDictationMode = selectDictationMode
        self.selectHotkey = selectHotkey
        self.selectModel = selectModel
        self.selectRecordingLimit = selectRecordingLimit
        self.loginItemChanged = loginItemChanged
    }
}

enum DictationModePresentation {
    static func optionTitle(for mode: HotkeyActivationMode) -> String {
        switch mode {
        case .hold:
            "Press and Hold"
        case .toggle:
            "Toggle"
        case .pause:
            "Pause Mode"
        }
    }
}

@MainActor
public final class AdvancedSettingsWindowController:
    NSWindowController,
    NSWindowDelegate
{
    public typealias StateProvider = () -> AdvancedSettingsState

    private let stateProvider: StateProvider
    private let actions: AdvancedSettingsActions
    private let loginItemManager: LoginItemManager
    private let hotkeyPopup = NSPopUpButton()
    private let modePopup = NSPopUpButton()
    private let modelPopup = NSPopUpButton()
    private let recordingLimitPopup = NSPopUpButton()
    private let loginItemToggle = NSButton(
        checkboxWithTitle: "Open automatically",
        target: nil,
        action: nil
    )
    private let loginItemStatus = NSTextField(labelWithString: "")
    private let loginItemSettingsButton = NSButton(
        title: "Open Settings",
        target: nil,
        action: nil
    )
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private var actionError: String?

    public init(
        stateProvider: @escaping StateProvider,
        actions: AdvancedSettingsActions,
        loginItemManager: LoginItemManager = LoginItemManager()
    ) {
        self.stateProvider = stateProvider
        self.actions = actions
        self.loginItemManager = loginItemManager
        super.init(window: nil)

        configurePopups()
        configureLoginItemControls()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 390),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Advanced Settings for whisper_hotkey"
        window.isReleasedWhenClosed = false
        window.animationBehavior = .utilityWindow
        window.center()
        window.delegate = self
        window.contentView = makeContentView()
        self.window = window

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        refresh()
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func showSettings() {
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    public func refreshIfVisible() {
        guard window?.isVisible == true else {
            return
        }
        refresh()
    }

    public func refresh() {
        let state = stateProvider()
        select(rawValue: state.selectedHotkey.rawValue, in: hotkeyPopup)
        select(rawValue: state.activationMode.rawValue, in: modePopup)
        select(rawValue: state.selectedModel.rawValue, in: modelPopup)
        select(rawValue: state.recordingLimit.rawValue, in: recordingLimitPopup)

        hotkeyPopup.isEnabled = state.configurationEnabled
        modePopup.isEnabled = state.configurationEnabled
        modelPopup.isEnabled = state.configurationEnabled
        recordingLimitPopup.isEnabled = state.configurationEnabled

        for item in modelPopup.itemArray {
            guard let rawValue = item.representedObject as? String,
                  let model = DictationModel(rawValue: rawValue)
            else {
                continue
            }
            let installed = state.availableModels.contains(model)
            item.title = installed
                ? model.menuTitle
                : "\(model.menuTitle) (Not Installed)"
            item.isEnabled = installed
        }

        for item in modePopup.itemArray {
            guard let rawValue = item.representedObject as? String,
                  let mode = HotkeyActivationMode(rawValue: rawValue)
            else {
                continue
            }
            item.isEnabled = state.configurationEnabled
                && (mode != .hold || !state.selectedHotkey.requiresToggleMode)
        }

        let loginStatus = loginItemManager.status
        updateLoginItemControls(loginStatus)
        loginItemToggle.isEnabled =
            state.configurationEnabled && loginStatus != .unknown
        loginItemSettingsButton.isEnabled = state.configurationEnabled
        updateDetail(using: state)
    }

    public func windowWillClose(_ notification: Notification) {
        NSApp.deactivate()
    }

    @objc private func applicationDidBecomeActive() {
        refreshIfVisible()
    }

    @objc private func selectHotkey(_ sender: NSPopUpButton) {
        guard stateProvider().configurationEnabled,
              let rawValue = sender.selectedItem?.representedObject as? String,
              let hotkey = HotkeyKey(rawValue: rawValue)
        else {
            refresh()
            return
        }
        actionError = nil
        actions.selectHotkey(hotkey)
        refresh()
    }

    @objc private func selectDictationMode(_ sender: NSPopUpButton) {
        let state = stateProvider()
        guard state.configurationEnabled,
              let rawValue = sender.selectedItem?.representedObject as? String,
              let mode = HotkeyActivationMode(rawValue: rawValue),
              mode != .hold || !state.selectedHotkey.requiresToggleMode
        else {
            refresh()
            return
        }
        actionError = nil
        actions.selectDictationMode(mode)
        refresh()
    }

    @objc private func selectModel(_ sender: NSPopUpButton) {
        let state = stateProvider()
        guard state.configurationEnabled,
              let rawValue = sender.selectedItem?.representedObject as? String,
              let model = DictationModel(rawValue: rawValue),
              state.availableModels.contains(model)
        else {
            refresh()
            return
        }
        actionError = nil
        actions.selectModel(model)
        refresh()
    }

    @objc private func selectRecordingLimit(_ sender: NSPopUpButton) {
        guard stateProvider().configurationEnabled,
              let rawValue = sender.selectedItem?.representedObject as? String,
              let limit = RecordingLimit(rawValue: rawValue)
        else {
            refresh()
            return
        }
        actionError = nil
        actions.selectRecordingLimit(limit)
        refresh()
    }

    @objc private func toggleLoginItem(_ sender: NSButton) {
        guard stateProvider().configurationEnabled else {
            refresh()
            return
        }
        do {
            if sender.state == .on {
                _ = try loginItemManager.enableExplicitly()
            } else {
                _ = try loginItemManager.disableExplicitly()
            }
            actionError = nil
            actions.loginItemChanged()
        } catch {
            actionError = "Could not update Open at Login: \(error.localizedDescription)"
        }
        refresh()
    }

    @objc private func openLoginItemSettings() {
        loginItemManager.openLoginItemsSettings()
    }

    private func configurePopups() {
        configure(
            hotkeyPopup,
            values: HotkeyKey.allCases.map {
                ($0.displayName, $0.rawValue)
            },
            action: #selector(selectHotkey(_:))
        )
        configure(
            modePopup,
            values: [HotkeyActivationMode.hold, .toggle, .pause].map {
                (DictationModePresentation.optionTitle(for: $0), $0.rawValue)
            },
            action: #selector(selectDictationMode(_:))
        )
        configure(
            modelPopup,
            values: DictationModel.allCases.map {
                ($0.menuTitle, $0.rawValue)
            },
            action: #selector(selectModel(_:))
        )
        configure(
            recordingLimitPopup,
            values: RecordingLimit.allCases.map {
                ($0.displayName, $0.rawValue)
            },
            action: #selector(selectRecordingLimit(_:))
        )
    }

    private func configure(
        _ popup: NSPopUpButton,
        values: [(title: String, rawValue: String)],
        action: Selector
    ) {
        popup.target = self
        popup.action = action
        popup.controlSize = .regular
        for value in values {
            popup.addItem(withTitle: value.title)
            popup.lastItem?.representedObject = value.rawValue
        }
    }

    private func configureLoginItemControls() {
        loginItemToggle.target = self
        loginItemToggle.action = #selector(toggleLoginItem(_:))
        loginItemStatus.textColor = .secondaryLabelColor
        loginItemStatus.alignment = .right
        loginItemSettingsButton.target = self
        loginItemSettingsButton.action = #selector(openLoginItemSettings)
        loginItemSettingsButton.bezelStyle = .rounded
        loginItemSettingsButton.controlSize = .small
    }

    private func updateLoginItemControls(_ status: LoginItemStatus) {
        switch status {
        case .enabled:
            loginItemToggle.state = .on
            loginItemStatus.stringValue = "Enabled"
            loginItemStatus.textColor = .systemGreen
            loginItemSettingsButton.isHidden = true
        case .requiresApproval:
            loginItemToggle.state = .on
            loginItemStatus.stringValue = "Approval needed"
            loginItemStatus.textColor = .systemOrange
            loginItemSettingsButton.isHidden = false
        case .notRegistered, .notFound:
            loginItemToggle.state = .off
            loginItemStatus.stringValue = "Off"
            loginItemStatus.textColor = .secondaryLabelColor
            loginItemSettingsButton.isHidden = true
        case .unknown:
            loginItemToggle.state = .off
            loginItemStatus.stringValue = "Unavailable"
            loginItemStatus.textColor = .secondaryLabelColor
            loginItemSettingsButton.isHidden = false
        }
        loginItemToggle.isEnabled = status != .unknown
    }

    private func updateDetail(using state: AdvancedSettingsState) {
        if let actionError {
            detailLabel.stringValue = actionError
            detailLabel.textColor = .systemRed
        } else if !state.configurationEnabled {
            detailLabel.stringValue =
                "Finish or cancel the current dictation before changing settings."
            detailLabel.textColor = .systemOrange
        } else if state.selectedHotkey.requiresToggleMode
            && state.activationMode == .toggle
        {
            detailLabel.stringValue =
                "Caps Lock cannot use Press and Hold because macOS exposes its lock-state changes."
            detailLabel.textColor = .secondaryLabelColor
        } else if state.activationMode == .pause {
            detailLabel.stringValue =
                "Pause Mode pastes each phrase after a natural silence and keeps listening until stopped."
            detailLabel.textColor = .secondaryLabelColor
        } else {
            detailLabel.stringValue =
                "Changes apply immediately and persist across launches. Audio remains local."
            detailLabel.textColor = .secondaryLabelColor
        }
    }

    private func select(rawValue: String, in popup: NSPopUpButton) {
        guard let index = popup.itemArray.firstIndex(where: {
            $0.representedObject as? String == rawValue
        }) else {
            return
        }
        popup.selectItem(at: index)
    }

    private func makeContentView() -> NSView {
        let root = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        let title = NSTextField(labelWithString: "Advanced settings")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        stack.addArrangedSubview(title)

        let subtitle = NSTextField(
            wrappingLabelWithString:
                "Configure persistent dictation behavior. Setup permissions remain separate."
        )
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 2
        stack.addArrangedSubview(subtitle)

        let grid = NSGridView()
        grid.columnSpacing = 16
        grid.rowSpacing = 12
        grid.xPlacement = .fill
        grid.translatesAutoresizingMaskIntoConstraints = false
        addRow(to: grid, title: "Dictation key", control: hotkeyPopup)
        addRow(to: grid, title: "Input behavior", control: modePopup)
        addRow(to: grid, title: "Whisper model", control: modelPopup)
        addRow(to: grid, title: "Recording limit", control: recordingLimitPopup)
        grid.column(at: 0).width = 125
        grid.column(at: 1).width = 335
        stack.addArrangedSubview(grid)

        let separator = NSBox()
        separator.boxType = .separator
        stack.addArrangedSubview(separator)

        let loginControls = NSStackView(
            views: [
                loginItemToggle,
                loginItemStatus,
                loginItemSettingsButton,
            ]
        )
        loginControls.orientation = .horizontal
        loginControls.alignment = .centerY
        loginControls.spacing = 10
        addRow(to: grid, title: "Open at login", control: loginControls)

        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 2
        stack.addArrangedSubview(detailLabel)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(
                lessThanOrEqualTo: root.bottomAnchor,
                constant: -22
            ),
            subtitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
            grid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            detailLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return root
    }

    private func addRow(
        to grid: NSGridView,
        title: String,
        control: NSView
    ) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        grid.addRow(with: [label, control])
    }

    var selectedHotkeyForTesting: HotkeyKey? {
        selectedValue(in: hotkeyPopup)
    }

    var selectedModeForTesting: HotkeyActivationMode? {
        selectedValue(in: modePopup)
    }

    var selectedModelForTesting: DictationModel? {
        selectedValue(in: modelPopup)
    }

    var selectedLimitForTesting: RecordingLimit? {
        selectedValue(in: recordingLimitPopup)
    }

    var configurationControlsEnabledForTesting: Bool {
        hotkeyPopup.isEnabled
            && modelPopup.isEnabled
            && recordingLimitPopup.isEnabled
    }

    var modeControlEnabledForTesting: Bool {
        modePopup.isEnabled
    }

    func modelIsEnabledForTesting(_ model: DictationModel) -> Bool? {
        modelPopup.itemArray.first(where: {
            $0.representedObject as? String == model.rawValue
        })?.isEnabled
    }

    func modelTitleForTesting(_ model: DictationModel) -> String? {
        modelPopup.itemArray.first(where: {
            $0.representedObject as? String == model.rawValue
        })?.title
    }

    var optionCountsForTesting: [Int] {
        [
            hotkeyPopup.numberOfItems,
            modePopup.numberOfItems,
            modelPopup.numberOfItems,
            recordingLimitPopup.numberOfItems,
        ]
    }

    var loginItemIsOnForTesting: Bool {
        loginItemToggle.state == .on
    }

    var loginStatusTextForTesting: String {
        loginItemStatus.stringValue
    }

    var loginSettingsIsVisibleForTesting: Bool {
        !loginItemSettingsButton.isHidden
    }

    var detailTextForTesting: String {
        detailLabel.stringValue
    }

    func selectHotkeyForTesting(_ hotkey: HotkeyKey) {
        select(rawValue: hotkey.rawValue, in: hotkeyPopup)
        selectHotkey(hotkeyPopup)
    }

    func selectModeForTesting(_ mode: HotkeyActivationMode) {
        select(rawValue: mode.rawValue, in: modePopup)
        selectDictationMode(modePopup)
    }

    func selectModelForTesting(_ model: DictationModel) {
        select(rawValue: model.rawValue, in: modelPopup)
        selectModel(modelPopup)
    }

    func selectLimitForTesting(_ limit: RecordingLimit) {
        select(rawValue: limit.rawValue, in: recordingLimitPopup)
        selectRecordingLimit(recordingLimitPopup)
    }

    func setLoginItemForTesting(enabled: Bool) {
        loginItemToggle.state = enabled ? .on : .off
        toggleLoginItem(loginItemToggle)
    }

    func openLoginSettingsForTesting() {
        openLoginItemSettings()
    }

    @discardableResult
    func clickLoginToggleForTesting(atVisibleEdge: Bool) -> Bool {
        guard let contentView = window?.contentView else {
            return false
        }
        contentView.layoutSubtreeIfNeeded()
        let localPoint = CGPoint(
            x: atVisibleEdge
                ? max(0.5, loginItemToggle.bounds.maxX - 0.5)
                : loginItemToggle.bounds.midX,
            y: loginItemToggle.bounds.midY
        )
        let contentPoint = loginItemToggle.convert(localPoint, to: contentView)
        guard let button = contentView.hitTest(contentPoint) as? NSButton else {
            return false
        }
        button.performClick(nil)
        return true
    }

    private func selectedValue<Value: RawRepresentable>(
        in popup: NSPopUpButton
    ) -> Value? where Value.RawValue == String {
        guard let rawValue = popup.selectedItem?.representedObject as? String else {
            return nil
        }
        return Value(rawValue: rawValue)
    }
}
