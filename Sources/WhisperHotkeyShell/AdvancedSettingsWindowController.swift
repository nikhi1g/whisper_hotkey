import AppKit
import WhisperHotkeyCore
import WhisperHotkeySystem

public struct AdvancedSettingsState: Equatable, Sendable {
    public let selectedHotkey: HotkeyKey
    public let activationMode: HotkeyActivationMode
    public let selectedModel: DictationModel
    public let selectedEngine: RecognitionEngine
    public let decodingProfile: DecodingProfile
    public let processingMode: ModelProcessingMode
    public let internalDictionaryEntries: [String]
    public let keepsLatestDictation: Bool
    public let recordingLimit: RecordingLimit
    public let selectedTheme: BadgeThemeSelection
    public let customThemes: [CustomBadgeTheme]
    public let availableModels: Set<DictationModel>
    public let availableEngines: Set<RecognitionEngine>
    public let configurationEnabled: Bool

    public init(
        selectedHotkey: HotkeyKey,
        activationMode: HotkeyActivationMode,
        selectedModel: DictationModel,
        selectedEngine: RecognitionEngine = .defaultEngine,
        decodingProfile: DecodingProfile = .defaultProfile,
        processingMode: ModelProcessingMode = .defaultMode,
        internalDictionaryEntries: [String] = [],
        keepsLatestDictation: Bool = true,
        recordingLimit: RecordingLimit,
        selectedTheme: BadgeThemeSelection = .defaultSelection,
        customThemes: [CustomBadgeTheme] = [],
        availableModels: Set<DictationModel>,
        availableEngines: Set<RecognitionEngine> = [.whisperCppMetal],
        configurationEnabled: Bool
    ) {
        self.selectedHotkey = selectedHotkey
        self.activationMode = activationMode
        self.selectedModel = selectedModel
        self.selectedEngine = selectedEngine
        self.decodingProfile = decodingProfile
        self.processingMode = processingMode
        self.internalDictionaryEntries = internalDictionaryEntries
        self.keepsLatestDictation = keepsLatestDictation
        self.recordingLimit = recordingLimit
        self.selectedTheme = selectedTheme
        self.customThemes = customThemes
        self.availableModels = availableModels
        self.availableEngines = availableEngines
        self.configurationEnabled = configurationEnabled
    }
}

@MainActor
public struct AdvancedSettingsActions {
    public var selectDictationMode: (HotkeyActivationMode) -> Void
    public var selectHotkey: (HotkeyKey) -> Void
    public var selectModel: (DictationModel) -> Void
    public var selectEngine: (RecognitionEngine) -> Void
    public var selectDecodingProfile: (DecodingProfile) -> Void
    public var selectProcessingMode: (ModelProcessingMode) -> Void
    public var setInternalDictionary: ([String]) -> Void
    public var setKeepsLatestDictation: (Bool) -> Void
    public var selectRecordingLimit: (RecordingLimit) -> Void
    public var selectTheme: (BadgeThemeSelection) -> Void
    public var saveCustomTheme: (CustomBadgeTheme) -> Void
    public var loginItemChanged: () -> Void

    public init(
        selectDictationMode: @escaping (HotkeyActivationMode) -> Void,
        selectHotkey: @escaping (HotkeyKey) -> Void,
        selectModel: @escaping (DictationModel) -> Void,
        selectEngine: @escaping (RecognitionEngine) -> Void = { _ in },
        selectDecodingProfile: @escaping (DecodingProfile) -> Void = { _ in },
        selectProcessingMode: @escaping (ModelProcessingMode) -> Void = { _ in },
        setInternalDictionary: @escaping ([String]) -> Void = { _ in },
        setKeepsLatestDictation: @escaping (Bool) -> Void = { _ in },
        selectRecordingLimit: @escaping (RecordingLimit) -> Void,
        selectTheme: @escaping (BadgeThemeSelection) -> Void = { _ in },
        saveCustomTheme: @escaping (CustomBadgeTheme) -> Void = { _ in },
        loginItemChanged: @escaping () -> Void = {}
    ) {
        self.selectDictationMode = selectDictationMode
        self.selectHotkey = selectHotkey
        self.selectModel = selectModel
        self.selectEngine = selectEngine
        self.selectDecodingProfile = selectDecodingProfile
        self.selectProcessingMode = selectProcessingMode
        self.setInternalDictionary = setInternalDictionary
        self.setKeepsLatestDictation = setKeepsLatestDictation
        self.selectRecordingLimit = selectRecordingLimit
        self.selectTheme = selectTheme
        self.saveCustomTheme = saveCustomTheme
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

enum DictationModelPresentation {
    static func chipTitle(for model: DictationModel) -> String {
        switch model {
        case .baseEnglish:
            "Base"
        case .smallEnglish:
            "Small"
        case .mediumEnglish:
            "Medium"
        case .largeV3TurboQ5:
            "Turbo"
        }
    }
}

@MainActor
public final class AdvancedSettingsWindowController:
    NSWindowController,
    NSWindowDelegate,
    NSTokenFieldDelegate
{
    public typealias StateProvider = () -> AdvancedSettingsState

    private let stateProvider: StateProvider
    private let actions: AdvancedSettingsActions
    private let loginItemManager: LoginItemManager
    private let hotkeyPopup = NSPopUpButton()
    private let modeControl = NSSegmentedControl()
    private let modelControl = NSSegmentedControl()
    private let engineControl = NSSegmentedControl()
    private let decodingControl = NSSegmentedControl()
    private let processingModeControl = NSSegmentedControl()
    private let internalDictionaryField = NSTokenField()
    private let keepLatestDictationToggle = NSButton(
        checkboxWithTitle: "Keep latest transcript until quit",
        target: nil,
        action: nil
    )
    private let recordingLimitPopup = NSPopUpButton()
    private let themePopup = NSPopUpButton()
    private let newThemeButton = NSButton(title: "New", target: nil, action: nil)
    private let editThemeButton = NSButton(title: "Edit", target: nil, action: nil)
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
    private let helpButton = NSButton()
    private let hotkeySummary = SettingsSummaryChip()
    private let modeSummary = SettingsSummaryChip()
    private let modelSummary = SettingsSummaryChip()
    private let limitSummary = SettingsSummaryChip()
    private let themeSummary = SettingsSummaryChip()
    private let loginSummary = SettingsSummaryChip()
    private lazy var userGuidePopover = UserGuidePopoverController(
        stateProvider: stateProvider,
        loginItemEnabledProvider: { [weak self] in
            self?.loginItemManager.status.isEnabled ?? false
        }
    )
    private weak var settingsRootView: NSView?
    private weak var settingsStack: NSStackView?
    private weak var settingsScrollView: NSScrollView?
    private weak var appearanceGrid: NSGridView?
    private var customThemeEditor: CustomThemeEditorViewController?
    private var collapsedSettingsFrame: CGRect?
    private var themedPrimaryLabels: [NSTextField] = []
    private var themedSecondaryLabels: [NSTextField] = []
    private var themedSectionLabels: [NSTextField] = []

    public init(
        stateProvider: @escaping StateProvider,
        actions: AdvancedSettingsActions,
        loginItemManager: LoginItemManager = LoginItemManager()
    ) {
        self.stateProvider = stateProvider
        self.actions = actions
        self.loginItemManager = loginItemManager
        super.init(window: nil)

        configureControls()
        configurePrivacyControls()
        configureLoginItemControls()
        configureHelpButton()

        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings for whisper_hotkey"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .utilityWindow
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.minSize = NSSize(width: 620, height: 520)
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
        select(mode: state.activationMode)
        select(model: state.selectedModel)
        select(engine: state.selectedEngine)
        select(decodingProfile: state.decodingProfile)
        select(processingMode: state.processingMode)
        if window?.firstResponder !== internalDictionaryField.currentEditor() {
            internalDictionaryField.objectValue =
                state.internalDictionaryEntries
        }
        keepLatestDictationToggle.state =
            state.keepsLatestDictation ? .on : .off
        select(rawValue: state.recordingLimit.rawValue, in: recordingLimitPopup)
        rebuildThemePopup(using: state)
        select(rawValue: state.selectedTheme.identifier, in: themePopup)

        hotkeyPopup.isEnabled = state.configurationEnabled
        modeControl.isEnabled = state.configurationEnabled
        modelControl.isEnabled = state.configurationEnabled
        engineControl.isEnabled = state.configurationEnabled
        decodingControl.isEnabled =
            state.configurationEnabled
                && state.selectedEngine != .whisperKitCoreML
        processingModeControl.isEnabled = state.configurationEnabled
        internalDictionaryField.isEnabled = state.configurationEnabled
        keepLatestDictationToggle.isEnabled = state.configurationEnabled
        recordingLimitPopup.isEnabled = state.configurationEnabled
        themePopup.isEnabled = state.configurationEnabled
        newThemeButton.isEnabled = state.configurationEnabled
        editThemeButton.isEnabled =
            state.configurationEnabled
                && state.selectedTheme.customTheme != nil

        for (index, model) in DictationModel.allCases.enumerated() {
            let installed = state.availableModels.contains(model)
            modelControl.setEnabled(
                state.configurationEnabled && installed,
                forSegment: index
            )
            modelControl.setToolTip(
                installed ? model.menuTitle : "\(model.menuTitle): Not Installed",
                forSegment: index
            )
        }
        for (index, engine) in RecognitionEngine.allCases.enumerated() {
            let installed = state.availableEngines.contains(engine)
            engineControl.setEnabled(
                state.configurationEnabled && installed,
                forSegment: index
            )
            engineControl.setToolTip(
                installed
                    ? engine.menuTitle
                    : "\(engine.menuTitle): Required local files are not installed",
                forSegment: index
            )
        }

        for (index, mode) in dictationModes.enumerated() {
            modeControl.setEnabled(
                state.configurationEnabled
                    && (mode != .hold || !state.selectedHotkey.requiresToggleMode),
                forSegment: index
            )
        }

        let loginStatus = loginItemManager.status
        updateLoginItemControls(loginStatus)
        updateSummary(using: state, loginStatus: loginStatus)
        applyTheme(state.selectedTheme)
        loginItemToggle.isEnabled =
            state.configurationEnabled && loginStatus != .unknown
        loginItemSettingsButton.isEnabled = state.configurationEnabled
    }

    public func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)
        commitInternalDictionary()
        hideCustomThemeEditor()
        userGuidePopover.close()
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
        actions.selectHotkey(hotkey)
        refresh()
    }

    @objc private func selectDictationMode(_ sender: NSSegmentedControl) {
        let state = stateProvider()
        guard state.configurationEnabled,
              dictationModes.indices.contains(sender.selectedSegment)
        else {
            refresh()
            return
        }
        let mode = dictationModes[sender.selectedSegment]
        guard
              mode != .hold || !state.selectedHotkey.requiresToggleMode
        else {
            refresh()
            return
        }
        actions.selectDictationMode(mode)
        refresh()
    }

    @objc private func selectModel(_ sender: NSSegmentedControl) {
        let state = stateProvider()
        guard state.configurationEnabled,
              DictationModel.allCases.indices.contains(sender.selectedSegment)
        else {
            refresh()
            return
        }
        let model = DictationModel.allCases[sender.selectedSegment]
        guard
              state.availableModels.contains(model)
        else {
            refresh()
            return
        }
        actions.selectModel(model)
        refresh()
    }

    @objc private func selectEngine(_ sender: NSSegmentedControl) {
        let state = stateProvider()
        guard state.configurationEnabled,
              RecognitionEngine.allCases.indices.contains(
                sender.selectedSegment
              )
        else {
            refresh()
            return
        }
        let engine = RecognitionEngine.allCases[sender.selectedSegment]
        guard state.availableEngines.contains(engine) else {
            refresh()
            return
        }
        actions.selectEngine(engine)
        refresh()
    }

    @objc private func selectDecodingProfile(
        _ sender: NSSegmentedControl
    ) {
        let state = stateProvider()
        guard state.configurationEnabled,
              state.selectedEngine != .whisperKitCoreML,
              DecodingProfile.allCases.indices.contains(
                sender.selectedSegment
              )
        else {
            refresh()
            return
        }
        actions.selectDecodingProfile(
            DecodingProfile.allCases[sender.selectedSegment]
        )
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
        actions.selectRecordingLimit(limit)
        refresh()
    }

    @objc private func selectProcessingMode(
        _ sender: NSSegmentedControl
    ) {
        guard stateProvider().configurationEnabled,
              ModelProcessingMode.allCases.indices.contains(
                sender.selectedSegment
              )
        else {
            refresh()
            return
        }
        actions.selectProcessingMode(
            ModelProcessingMode.allCases[sender.selectedSegment]
        )
        refresh()
    }

    @objc private func updateInternalDictionary(_ sender: NSTokenField) {
        commitInternalDictionary()
    }

    @objc private func toggleLatestDictationRetention(_ sender: NSButton) {
        guard stateProvider().configurationEnabled else {
            refresh()
            return
        }
        actions.setKeepsLatestDictation(sender.state == .on)
        refresh()
    }

    public func controlTextDidEndEditing(_ notification: Notification) {
        guard notification.object as? NSTokenField === internalDictionaryField
        else {
            return
        }
        commitInternalDictionary()
    }

    @objc private func selectTheme(_ sender: NSPopUpButton) {
        guard stateProvider().configurationEnabled,
              let identifier =
                sender.selectedItem?.representedObject as? String,
              let theme = themeSelection(
                identifier: identifier,
                state: stateProvider()
              )
        else {
            refresh()
            return
        }
        actions.selectTheme(theme)
        refresh()
    }

    @objc private func createCustomTheme() {
        showCustomThemeEditor(theme: nil)
    }

    @objc private func editCustomTheme() {
        showCustomThemeEditor(theme: stateProvider().selectedTheme.customTheme)
    }

    private func showCustomThemeEditor(theme: CustomBadgeTheme?) {
        guard stateProvider().configurationEnabled,
              let stack = settingsStack,
              customThemeEditor == nil
        else {
            return
        }
        let editor = CustomThemeEditorViewController(
            theme: theme,
            onSave: { [weak self] savedTheme in
                guard let self else {
                    return
                }
                actions.saveCustomTheme(savedTheme)
                hideCustomThemeEditor()
                refresh()
            },
            onCancel: { [weak self] in
                self?.hideCustomThemeEditor()
            }
        )
        customThemeEditor = editor
        let editorView = editor.view
        editorView.translatesAutoresizingMaskIntoConstraints = false
        let insertionIndex = (appearanceGrid.flatMap {
            stack.arrangedSubviews.firstIndex(of: $0)
        } ?? stack.arrangedSubviews.count - 1) + 1
        stack.insertArrangedSubview(editorView, at: insertionIndex)
        editorView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        editorView.heightAnchor.constraint(
            equalToConstant: CustomThemeEditorViewController.contentHeight
        ).isActive = true
        stack.setCustomSpacing(20, after: editorView)
        expandSettingsWindowForEditor()
        stack.layoutSubtreeIfNeeded()
        settingsScrollView?.contentView.scrollToVisible(editorView.frame)
    }

    private func hideCustomThemeEditor() {
        guard let editor = customThemeEditor else {
            return
        }
        editor.view.removeFromSuperview()
        customThemeEditor = nil
        restoreCollapsedSettingsFrame()
    }

    private func expandSettingsWindowForEditor() {
        guard let window,
              !window.styleMask.contains(.fullScreen),
              collapsedSettingsFrame == nil
        else {
            return
        }
        let original = window.frame
        collapsedSettingsFrame = original
        let availableHeight = window.screen?.visibleFrame.height ?? original.height
        let targetHeight = max(
            original.height,
            min(
                original.height + CustomThemeEditorViewController.contentHeight,
                availableHeight - 40
            )
        )
        let target = CGRect(
            x: original.minX,
            y: original.maxY - targetHeight,
            width: original.width,
            height: targetHeight
        )
        window.setFrame(target, display: true, animate: window.isVisible)
    }

    private func restoreCollapsedSettingsFrame() {
        guard let window, let collapsedSettingsFrame else {
            return
        }
        self.collapsedSettingsFrame = nil
        guard !window.styleMask.contains(.fullScreen) else {
            return
        }
        window.setFrame(
            collapsedSettingsFrame,
            display: true,
            animate: window.isVisible
        )
    }

    private func themeSelection(
        identifier: String,
        state: AdvancedSettingsState
    ) -> BadgeThemeSelection? {
        if let builtIn = BadgeTheme(rawValue: identifier) {
            return .builtIn(builtIn)
        }
        guard identifier.hasPrefix("custom:"),
              let id = UUID(
                uuidString: String(identifier.dropFirst("custom:".count))
              ),
              let custom = state.customThemes.first(where: { $0.id == id })
        else {
            return nil
        }
        return .custom(custom)
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
            actions.loginItemChanged()
        } catch {
            NSSound.beep()
        }
        refresh()
    }

    @objc private func openLoginItemSettings() {
        loginItemManager.openLoginItemsSettings()
    }

    @objc private func toggleUserGuide() {
        userGuidePopover.toggle(relativeTo: helpButton)
    }

    private var dictationModes: [HotkeyActivationMode] {
        [.hold, .toggle, .pause]
    }

    private func configureControls() {
        configure(
            hotkeyPopup,
            values: HotkeyKey.allCases.map {
                ($0.displayName, $0.rawValue)
            },
            action: #selector(selectHotkey(_:))
        )
        configure(
            modeControl,
            labels: dictationModes.map(DictationModePresentation.optionTitle),
            action: #selector(selectDictationMode(_:))
        )
        configure(
            modelControl,
            labels: DictationModel.allCases.map(
                DictationModelPresentation.chipTitle
            ),
            action: #selector(selectModel(_:))
        )
        configure(
            engineControl,
            labels: RecognitionEngine.allCases.map(\.displayName),
            action: #selector(selectEngine(_:))
        )
        configure(
            decodingControl,
            labels: DecodingProfile.allCases.map(\.displayName),
            action: #selector(selectDecodingProfile(_:))
        )
        for (index, profile) in DecodingProfile.allCases.enumerated() {
            decodingControl.setToolTip(
                profile.description,
                forSegment: index
            )
        }
        configure(
            processingModeControl,
            labels: ModelProcessingMode.allCases.map(\.displayName),
            action: #selector(selectProcessingMode(_:))
        )
        for (index, mode) in ModelProcessingMode.allCases.enumerated() {
            processingModeControl.setToolTip(
                mode.description,
                forSegment: index
            )
        }
        processingModeControl.setAccessibilityLabel("Processing")
        internalDictionaryField.delegate = self
        internalDictionaryField.target = self
        internalDictionaryField.action =
            #selector(updateInternalDictionary(_:))
        internalDictionaryField.tokenStyle = .rounded
        internalDictionaryField.tokenizingCharacterSet =
            CharacterSet(charactersIn: ",\n")
        internalDictionaryField.placeholderString =
            "Add words or phrases, then press Return"
        internalDictionaryField.toolTip =
            "Biases local recognition toward these spellings. Separate entries with commas or Return."
        internalDictionaryField.setAccessibilityLabel("Internal Dictionary")
        internalDictionaryField.maximumNumberOfLines = 3
        internalDictionaryField.lineBreakMode = .byWordWrapping
        internalDictionaryField.cell?.wraps = true
        internalDictionaryField.cell?.usesSingleLineMode = false
        configure(
            recordingLimitPopup,
            values: RecordingLimit.allCases.map {
                ($0.displayName, $0.rawValue)
            },
            action: #selector(selectRecordingLimit(_:))
        )
        configureThemePopup()
    }

    private func configureThemePopup() {
        themePopup.target = self
        themePopup.action = #selector(selectTheme(_:))
        themePopup.controlSize = .regular
        newThemeButton.target = self
        newThemeButton.action = #selector(createCustomTheme)
        newThemeButton.controlSize = .small
        editThemeButton.target = self
        editThemeButton.action = #selector(editCustomTheme)
        editThemeButton.controlSize = .small
    }

    private func configurePrivacyControls() {
        keepLatestDictationToggle.target = self
        keepLatestDictationToggle.action =
            #selector(toggleLatestDictationRetention(_:))
        keepLatestDictationToggle.toolTip =
            "Turn off to clear the retained transcript immediately and hide Copy Last Dictation."
        keepLatestDictationToggle.setAccessibilityLabel(
            "Keep latest transcript until quit"
        )
    }

    private func rebuildThemePopup(using state: AdvancedSettingsState) {
        themePopup.removeAllItems()
        for (modeIndex, mode) in BadgeThemeMode.allCases.enumerated() {
            if modeIndex > 0 {
                themePopup.menu?.addItem(.separator())
            }
            let heading = NSMenuItem(
                title: mode.displayName,
                action: nil,
                keyEquivalent: ""
            )
            heading.isEnabled = false
            themePopup.menu?.addItem(heading)
            for theme in BadgeTheme.allCases where theme.mode == mode {
                themePopup.addItem(withTitle: theme.displayName)
                themePopup.lastItem?.representedObject = theme.rawValue
            }
        }
        guard !state.customThemes.isEmpty else {
            return
        }
        themePopup.menu?.addItem(.separator())
        let heading = NSMenuItem(
            title: "Custom",
            action: nil,
            keyEquivalent: ""
        )
        heading.isEnabled = false
        themePopup.menu?.addItem(heading)
        for theme in state.customThemes.sorted(by: {
            $0.name.localizedCaseInsensitiveCompare($1.name)
                == .orderedAscending
        }) {
            themePopup.addItem(withTitle: theme.name)
            themePopup.lastItem?.representedObject =
                BadgeThemeSelection.custom(theme).identifier
        }
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

    private func configure(
        _ control: NSSegmentedControl,
        labels: [String],
        action: Selector
    ) {
        control.segmentCount = labels.count
        control.trackingMode = .selectOne
        control.segmentStyle = .rounded
        control.controlSize = .regular
        control.target = self
        control.action = action
        for (index, label) in labels.enumerated() {
            control.setLabel(label, forSegment: index)
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

    private func configureHelpButton() {
        helpButton.bezelStyle = .helpButton
        helpButton.title = ""
        helpButton.target = self
        helpButton.action = #selector(toggleUserGuide)
        helpButton.toolTip = "Open User Guide"
        helpButton.setAccessibilityLabel("Open User Guide")
        NSLayoutConstraint.activate([
            helpButton.widthAnchor.constraint(equalToConstant: 24),
            helpButton.heightAnchor.constraint(equalToConstant: 24),
        ])
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

    private func commitInternalDictionary() {
        guard stateProvider().configurationEnabled else {
            refresh()
            return
        }
        let rawEntries: [String]
        if let entries = internalDictionaryField.objectValue as? [String] {
            rawEntries = entries
        } else {
            rawEntries = internalDictionaryField.stringValue.components(
                separatedBy: CharacterSet(charactersIn: ",\n")
            )
        }
        let dictionary = InternalDictionary(entries: rawEntries)
        internalDictionaryField.objectValue = dictionary.entries
        guard dictionary.entries
                != stateProvider().internalDictionaryEntries
        else {
            return
        }
        actions.setInternalDictionary(dictionary.entries)
    }

    private func updateSummary(
        using state: AdvancedSettingsState,
        loginStatus: LoginItemStatus
    ) {
        hotkeySummary.stringValue = state.selectedHotkey.displayName
        modeSummary.stringValue = DictationModePresentation.optionTitle(
            for: state.activationMode
        )
        let decodingSummary = state.selectedEngine == .whisperKitCoreML
            ? "Native"
            : state.decodingProfile.displayName
        modelSummary.stringValue =
            "\(DictationModelPresentation.chipTitle(for: state.selectedModel)) "
            + "\(state.selectedEngine.displayName) "
            + "\(decodingSummary) "
            + state.processingMode.displayName
        limitSummary.stringValue = state.recordingLimit.displayName
        themeSummary.stringValue = state.selectedTheme.summaryName
        switch loginStatus {
        case .enabled:
            loginSummary.stringValue = "Login On"
        case .requiresApproval:
            loginSummary.stringValue = "Login Approval"
        case .notRegistered, .notFound:
            loginSummary.stringValue = "Login Off"
        case .unknown:
            loginSummary.stringValue = "Login Unavailable"
        }
    }

    private func applyTheme(_ theme: BadgeThemeSelection) {
        let palette = BadgeThemePalette.palette(for: theme)
        let background = palette.background.withAlphaComponent(1)
        let secondaryText = palette.primaryText.withAlphaComponent(0.72)
        let sectionText = palette.waveform.withAlphaComponent(0.78)
        let appearanceName: NSAppearance.Name =
            theme.mode == .light ? .aqua : .darkAqua

        window?.appearance = NSAppearance(named: appearanceName)
        window?.backgroundColor = background
        settingsRootView?.layer?.backgroundColor = background.cgColor
        themedPrimaryLabels.forEach { $0.textColor = palette.primaryText }
        themedSecondaryLabels.forEach { $0.textColor = secondaryText }
        themedSectionLabels.forEach { $0.textColor = sectionText }
        loginItemToggle.contentTintColor = palette.waveform
        keepLatestDictationToggle.contentTintColor = palette.waveform
        loginItemSettingsButton.contentTintColor = palette.waveform
        helpButton.contentTintColor = palette.waveform
        [
            hotkeySummary,
            modeSummary,
            modelSummary,
            limitSummary,
            themeSummary,
            loginSummary,
        ].forEach { $0.applyTheme(palette) }
        userGuidePopover.applyTheme(theme)
    }

    private func select(rawValue: String, in popup: NSPopUpButton) {
        guard let index = popup.itemArray.firstIndex(where: {
            $0.representedObject as? String == rawValue
        }) else {
            return
        }
        popup.selectItem(at: index)
    }

    private func select(mode: HotkeyActivationMode) {
        guard let index = dictationModes.firstIndex(of: mode) else {
            return
        }
        modeControl.selectedSegment = index
    }

    private func select(model: DictationModel) {
        guard let index = DictationModel.allCases.firstIndex(of: model) else {
            return
        }
        modelControl.selectedSegment = index
    }

    private func select(engine: RecognitionEngine) {
        guard let index = RecognitionEngine.allCases.firstIndex(of: engine)
        else {
            return
        }
        engineControl.selectedSegment = index
    }

    private func select(decodingProfile: DecodingProfile) {
        guard let index = DecodingProfile.allCases.firstIndex(
            of: decodingProfile
        ) else {
            return
        }
        decodingControl.selectedSegment = index
    }

    private func select(processingMode: ModelProcessingMode) {
        guard let index = ModelProcessingMode.allCases.firstIndex(
            of: processingMode
        ) else {
            return
        }
        processingModeControl.selectedSegment = index
    }

    private func makeContentView() -> NSView {
        let root = NSView()
        root.wantsLayer = true
        settingsRootView = root
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)
        settingsScrollView = scrollView

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)
        settingsStack = stack

        let title = NSTextField(labelWithString: "Settings")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        themedPrimaryLabels.append(title)
        stack.addArrangedSubview(title)

        let subtitle = NSTextField(
            wrappingLabelWithString:
                "Dictation preferences apply immediately and stay on this Mac."
        )
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 2
        themedSecondaryLabels.append(subtitle)
        stack.addArrangedSubview(subtitle)
        stack.setCustomSpacing(22, after: subtitle)

        let inputTitle = makeSectionTitle("INPUT")
        stack.addArrangedSubview(inputTitle)
        let inputGrid = makeGrid()
        addRow(to: inputGrid, title: "Dictation key", control: hotkeyPopup)
        addRow(to: inputGrid, title: "Behavior", control: modeControl)
        sizeColumns(in: inputGrid)
        stack.addArrangedSubview(inputGrid)
        stack.setCustomSpacing(20, after: inputGrid)

        let recognitionTitle = makeSectionTitle("RECOGNITION")
        stack.addArrangedSubview(recognitionTitle)
        let recognitionGrid = makeGrid()
        addRow(to: recognitionGrid, title: "Model", control: modelControl)
        addRow(
            to: recognitionGrid,
            title: "Processing",
            control: processingModeControl
        )
        addRow(to: recognitionGrid, title: "Engine", control: engineControl)
        addRow(
            to: recognitionGrid,
            title: "Decoding",
            control: decodingControl
        )
        addRow(
            to: recognitionGrid,
            title: "Internal dictionary",
            control: internalDictionaryField
        )
        internalDictionaryField.heightAnchor.constraint(
            greaterThanOrEqualToConstant: 52
        ).isActive = true
        addRow(
            to: recognitionGrid,
            title: "Recording limit",
            control: recordingLimitPopup
        )
        sizeColumns(in: recognitionGrid)
        stack.addArrangedSubview(recognitionGrid)
        stack.setCustomSpacing(20, after: recognitionGrid)

        let privacyTitle = makeSectionTitle("PRIVACY")
        stack.addArrangedSubview(privacyTitle)
        let privacyGrid = makeGrid()
        addRow(
            to: privacyGrid,
            title: "Copy Last Dictation",
            control: keepLatestDictationToggle
        )
        sizeColumns(in: privacyGrid)
        stack.addArrangedSubview(privacyGrid)
        stack.setCustomSpacing(20, after: privacyGrid)

        let appearanceTitle = makeSectionTitle("APPEARANCE")
        stack.addArrangedSubview(appearanceTitle)
        let appearanceGrid = makeGrid()
        self.appearanceGrid = appearanceGrid
        let themeControls = NSStackView(
            views: [themePopup, newThemeButton, editThemeButton]
        )
        themeControls.orientation = .horizontal
        themeControls.alignment = .centerY
        themeControls.spacing = 6
        themePopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        addRow(to: appearanceGrid, title: "Theme", control: themeControls)
        sizeColumns(in: appearanceGrid)
        stack.addArrangedSubview(appearanceGrid)
        stack.setCustomSpacing(20, after: appearanceGrid)

        let startupTitle = makeSectionTitle("STARTUP")
        stack.addArrangedSubview(startupTitle)

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
        let startupGrid = makeGrid()
        addRow(to: startupGrid, title: "Open at login", control: loginControls)
        sizeColumns(in: startupGrid)
        stack.addArrangedSubview(startupGrid)

        let primarySummaryRow = NSStackView(
            views: [
                hotkeySummary,
                modeSummary,
                modelSummary,
            ]
        )
        primarySummaryRow.orientation = .horizontal
        primarySummaryRow.alignment = .centerY
        primarySummaryRow.spacing = 4

        let secondarySummaryRow = NSStackView(
            views: [
                limitSummary,
                themeSummary,
                loginSummary,
            ]
        )
        secondarySummaryRow.orientation = .horizontal
        secondarySummaryRow.alignment = .centerY
        secondarySummaryRow.spacing = 4

        let summary = NSStackView(
            views: [primarySummaryRow, secondarySummaryRow]
        )
        summary.orientation = .vertical
        summary.alignment = .leading
        summary.spacing = 4

        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        helpButton.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )
        let footer = NSStackView(views: [summary, footerSpacer, helpButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 10
        stack.addArrangedSubview(footer)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -32),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 26),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -24),
            subtitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
            inputGrid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            recognitionGrid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            privacyGrid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            appearanceGrid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            startupGrid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return root
    }

    private func makeSectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        themedSectionLabels.append(label)
        return label
    }

    private func makeGrid() -> NSGridView {
        let grid = NSGridView()
        grid.columnSpacing = 18
        grid.rowSpacing = 12
        grid.xPlacement = .fill
        grid.translatesAutoresizingMaskIntoConstraints = false
        return grid
    }

    private func sizeColumns(in grid: NSGridView) {
        grid.column(at: 0).width = 112
        grid.column(at: 1).width = 426
    }

    private func addRow(
        to grid: NSGridView,
        title: String,
        control: NSView
    ) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        themedPrimaryLabels.append(label)
        grid.addRow(with: [label, control])
    }

    var selectedHotkeyForTesting: HotkeyKey? {
        selectedValue(in: hotkeyPopup)
    }

    var selectedModeForTesting: HotkeyActivationMode? {
        guard dictationModes.indices.contains(modeControl.selectedSegment) else {
            return nil
        }
        return dictationModes[modeControl.selectedSegment]
    }

    var selectedModelForTesting: DictationModel? {
        guard DictationModel.allCases.indices.contains(modelControl.selectedSegment)
        else {
            return nil
        }
        return DictationModel.allCases[modelControl.selectedSegment]
    }

    var selectedEngineForTesting: RecognitionEngine? {
        guard RecognitionEngine.allCases.indices.contains(
            engineControl.selectedSegment
        ) else {
            return nil
        }
        return RecognitionEngine.allCases[engineControl.selectedSegment]
    }

    var selectedDecodingProfileForTesting: DecodingProfile? {
        guard DecodingProfile.allCases.indices.contains(
            decodingControl.selectedSegment
        ) else {
            return nil
        }
        return DecodingProfile.allCases[decodingControl.selectedSegment]
    }

    var selectedLimitForTesting: RecordingLimit? {
        selectedValue(in: recordingLimitPopup)
    }

    var selectedThemeForTesting: BadgeThemeSelection? {
        guard let identifier =
                themePopup.selectedItem?.representedObject as? String
        else {
            return nil
        }
        return themeSelection(
            identifier: identifier,
            state: stateProvider()
        )
    }

    var supportsStandardWindowCommandsForTesting: Bool {
        guard let window else {
            return false
        }
        return window.styleMask.contains(.closable)
            && window.styleMask.contains(.miniaturizable)
            && window.styleMask.contains(.resizable)
            && window.collectionBehavior.contains(.fullScreenPrimary)
    }

    var usesScrollableSettingsContentForTesting: Bool {
        settingsScrollView?.hasVerticalScroller == true
    }

    func openNewThemeEditorForTesting() {
        createCustomTheme()
    }

    var customThemeEditorIsInlineForTesting: Bool {
        guard let editor = customThemeEditor else {
            return false
        }
        return editor.view.superview === settingsStack
            && window?.attachedSheet == nil
    }

    var customThemeEditorExpandedWindowForTesting: Bool {
        guard let collapsedSettingsFrame, let currentFrame = window?.frame else {
            return false
        }
        return currentFrame.height >= collapsedSettingsFrame.height
    }

    func closeCustomThemeEditorForTesting() {
        hideCustomThemeEditor()
    }

    var selectableThemeCountForTesting: Int {
        themePopup.itemArray.filter {
            $0.representedObject is String
        }.count
    }

    var themeSectionTitlesForTesting: [String] {
        themePopup.itemArray.compactMap { item in
            guard !item.isSeparatorItem,
                  item.representedObject == nil
            else {
                return nil
            }
            return item.title
        }
    }

    var windowBackgroundForTesting: NSColor? {
        window?.backgroundColor
    }

    var configurationControlsEnabledForTesting: Bool {
        hotkeyPopup.isEnabled
            && modelControl.isEnabled
            && engineControl.isEnabled
            && decodingControl.isEnabled
            && processingModeControl.isEnabled
            && internalDictionaryField.isEnabled
            && recordingLimitPopup.isEnabled
            && themePopup.isEnabled
            && newThemeButton.isEnabled
    }

    var modeControlEnabledForTesting: Bool {
        modeControl.isEnabled
    }

    var decodingControlEnabledForTesting: Bool {
        decodingControl.isEnabled
    }

    var usesChipSelectionForTesting: Bool {
        modeControl.segmentStyle == .rounded
            && modeControl.trackingMode == .selectOne
            && modelControl.segmentStyle == .rounded
            && modelControl.trackingMode == .selectOne
            && engineControl.segmentStyle == .rounded
            && engineControl.trackingMode == .selectOne
            && decodingControl.segmentStyle == .rounded
            && decodingControl.trackingMode == .selectOne
            && processingModeControl.segmentStyle == .rounded
            && processingModeControl.trackingMode == .selectOne
    }

    var controlsFitWindowForTesting: Bool {
        controlsOutsideWindowForTesting.isEmpty
    }

    var controlsOutsideWindowForTesting: [String] {
        guard let contentView = window?.contentView else {
            return ["contentView"]
        }
        contentView.layoutSubtreeIfNeeded()
        let controls: [(String, NSView)] = [
            ("hotkey", hotkeyPopup),
            ("mode", modeControl),
            ("model", modelControl),
            ("engine", engineControl),
            ("decoding", decodingControl),
            ("processing", processingModeControl),
            ("internal dictionary", internalDictionaryField),
            ("last dictation retention", keepLatestDictationToggle),
            ("limit", recordingLimitPopup),
            ("theme", themePopup),
            ("new theme", newThemeButton),
            ("edit theme", editThemeButton),
            ("login toggle", loginItemToggle),
            ("hotkey summary", hotkeySummary),
            ("mode summary", modeSummary),
            ("model summary", modelSummary),
            ("limit summary", limitSummary),
            ("theme summary", themeSummary),
            ("login summary", loginSummary),
            ("help", helpButton),
        ]
        return controls.compactMap { name, view in
            let frame = view.convert(view.bounds, to: contentView)
            let fits = frame.width > 0
                && frame.height > 0
                && contentView.bounds.contains(frame)
            return fits ? nil : "\(name): \(frame)"
        }
    }

    func modelIsEnabledForTesting(_ model: DictationModel) -> Bool? {
        guard let index = DictationModel.allCases.firstIndex(of: model) else {
            return nil
        }
        return modelControl.isEnabled(forSegment: index)
    }

    func modelTitleForTesting(_ model: DictationModel) -> String? {
        guard let index = DictationModel.allCases.firstIndex(of: model) else {
            return nil
        }
        return modelControl.toolTip(forSegment: index)
    }

    var optionCountsForTesting: [Int] {
        [
            hotkeyPopup.numberOfItems,
            modeControl.segmentCount,
            modelControl.segmentCount,
            engineControl.segmentCount,
            decodingControl.segmentCount,
            processingModeControl.segmentCount,
            recordingLimitPopup.numberOfItems,
            themePopup.numberOfItems,
        ]
    }

    var loginItemIsOnForTesting: Bool {
        loginItemToggle.state == .on
    }

    var keepsLatestDictationForTesting: Bool {
        keepLatestDictationToggle.state == .on
    }

    var loginStatusTextForTesting: String {
        loginItemStatus.stringValue
    }

    var loginSettingsIsVisibleForTesting: Bool {
        !loginItemSettingsButton.isHidden
    }

    var helpAccessibilityLabelForTesting: String? {
        helpButton.accessibilityLabel()
    }

    var helpButtonFrameForTesting: CGRect {
        guard let contentView = window?.contentView else {
            return .zero
        }
        contentView.layoutSubtreeIfNeeded()
        return helpButton.convert(helpButton.bounds, to: contentView)
    }

    var summaryValuesForTesting: [String] {
        [
            hotkeySummary.stringValue,
            modeSummary.stringValue,
            modelSummary.stringValue,
            limitSummary.stringValue,
            themeSummary.stringValue,
            loginSummary.stringValue,
        ]
    }

    var summaryFramesForTesting: [CGRect] {
        guard let contentView = window?.contentView else {
            return []
        }
        contentView.layoutSubtreeIfNeeded()
        return [
            hotkeySummary,
            modeSummary,
            modelSummary,
            limitSummary,
            themeSummary,
            loginSummary,
        ].map { $0.convert($0.bounds, to: contentView) }
    }

    func toggleUserGuideForTesting() {
        toggleUserGuide()
    }

    var userGuideIsShownForTesting: Bool {
        userGuidePopover.isShownForTesting
    }

    func selectHotkeyForTesting(_ hotkey: HotkeyKey) {
        select(rawValue: hotkey.rawValue, in: hotkeyPopup)
        selectHotkey(hotkeyPopup)
    }

    func selectModeForTesting(_ mode: HotkeyActivationMode) {
        select(mode: mode)
        selectDictationMode(modeControl)
    }

    func selectModelForTesting(_ model: DictationModel) {
        select(model: model)
        selectModel(modelControl)
    }

    func selectDecodingProfileForTesting(_ profile: DecodingProfile) {
        select(decodingProfile: profile)
        selectDecodingProfile(decodingControl)
    }

    func selectEngineForTesting(_ engine: RecognitionEngine) {
        select(engine: engine)
        selectEngine(engineControl)
    }

    func selectProcessingModeForTesting(_ mode: ModelProcessingMode) {
        select(processingMode: mode)
        selectProcessingMode(processingModeControl)
    }

    var selectedProcessingModeForTesting: ModelProcessingMode? {
        guard ModelProcessingMode.allCases.indices.contains(
            processingModeControl.selectedSegment
        ) else {
            return nil
        }
        return ModelProcessingMode.allCases[
            processingModeControl.selectedSegment
        ]
    }

    var internalDictionaryEntriesForTesting: [String] {
        internalDictionaryField.objectValue as? [String] ?? []
    }

    func setInternalDictionaryForTesting(_ entries: [String]) {
        internalDictionaryField.objectValue = entries
        updateInternalDictionary(internalDictionaryField)
    }

    func selectLimitForTesting(_ limit: RecordingLimit) {
        select(rawValue: limit.rawValue, in: recordingLimitPopup)
        selectRecordingLimit(recordingLimitPopup)
    }

    func selectThemeForTesting(_ theme: BadgeTheme) {
        select(rawValue: theme.rawValue, in: themePopup)
        selectTheme(themePopup)
    }

    func setLoginItemForTesting(enabled: Bool) {
        loginItemToggle.state = enabled ? .on : .off
        toggleLoginItem(loginItemToggle)
    }

    func setKeepsLatestDictationForTesting(_ enabled: Bool) {
        keepLatestDictationToggle.state = enabled ? .on : .off
        toggleLatestDictationRetention(keepLatestDictationToggle)
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

private final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(
            .deviceIndependentFlagsMask
        )
        switch (event.charactersIgnoringModifiers?.lowercased(), flags) {
        case ("w", [.command]):
            performClose(nil)
            return true
        case ("m", [.command]):
            miniaturize(nil)
            return true
        case ("f", [.command, .control]):
            toggleFullScreen(nil)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

private final class SettingsSummaryChip: NSView {
    private let label = NSTextField(labelWithString: "")
    private var fillColor = NSColor.quaternaryLabelColor

    var stringValue: String {
        get { label.stringValue }
        set {
            label.stringValue = newValue
            invalidateIntrinsicContentSize()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func applyTheme(_ palette: BadgeThemePalette) {
        label.textColor = palette.primaryText.withAlphaComponent(0.78)
        fillColor = palette.primaryText.withAlphaComponent(0.08)
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        let labelSize = label.intrinsicContentSize
        return NSSize(width: labelSize.width + 12, height: 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        fillColor.setFill()
        NSBezierPath(
            roundedRect: bounds,
            xRadius: 7,
            yRadius: 7
        ).fill()
        super.draw(dirtyRect)
    }
}
