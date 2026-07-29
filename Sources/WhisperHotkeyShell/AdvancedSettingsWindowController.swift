import AppKit
import WhisperHotkeyCore
import WhisperHotkeySystem

public struct AdvancedSettingsState: Equatable, Sendable {
    public let selectedHotkey: HotkeyKey
    public let activationMode: HotkeyActivationMode
    public let selectedModel: DictationModel
    public let keepModelReady: Bool
    public let recordingLimit: RecordingLimit
    public let selectedTheme: BadgeTheme
    public let availableModels: Set<DictationModel>
    public let configurationEnabled: Bool

    public init(
        selectedHotkey: HotkeyKey,
        activationMode: HotkeyActivationMode,
        selectedModel: DictationModel,
        keepModelReady: Bool = false,
        recordingLimit: RecordingLimit,
        selectedTheme: BadgeTheme = .defaultTheme,
        availableModels: Set<DictationModel>,
        configurationEnabled: Bool
    ) {
        self.selectedHotkey = selectedHotkey
        self.activationMode = activationMode
        self.selectedModel = selectedModel
        self.keepModelReady = keepModelReady
        self.recordingLimit = recordingLimit
        self.selectedTheme = selectedTheme
        self.availableModels = availableModels
        self.configurationEnabled = configurationEnabled
    }
}

@MainActor
public struct AdvancedSettingsActions {
    public var selectDictationMode: (HotkeyActivationMode) -> Void
    public var selectHotkey: (HotkeyKey) -> Void
    public var selectModel: (DictationModel) -> Void
    public var setKeepModelReady: (Bool) -> Void
    public var selectRecordingLimit: (RecordingLimit) -> Void
    public var selectTheme: (BadgeTheme) -> Void
    public var loginItemChanged: () -> Void

    public init(
        selectDictationMode: @escaping (HotkeyActivationMode) -> Void,
        selectHotkey: @escaping (HotkeyKey) -> Void,
        selectModel: @escaping (DictationModel) -> Void,
        setKeepModelReady: @escaping (Bool) -> Void = { _ in },
        selectRecordingLimit: @escaping (RecordingLimit) -> Void,
        selectTheme: @escaping (BadgeTheme) -> Void = { _ in },
        loginItemChanged: @escaping () -> Void = {}
    ) {
        self.selectDictationMode = selectDictationMode
        self.selectHotkey = selectHotkey
        self.selectModel = selectModel
        self.setKeepModelReady = setKeepModelReady
        self.selectRecordingLimit = selectRecordingLimit
        self.selectTheme = selectTheme
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
    NSWindowDelegate
{
    public typealias StateProvider = () -> AdvancedSettingsState

    private let stateProvider: StateProvider
    private let actions: AdvancedSettingsActions
    private let loginItemManager: LoginItemManager
    private let hotkeyPopup = NSPopUpButton()
    private let modeControl = NSSegmentedControl()
    private let modelControl = NSSegmentedControl()
    private let keepModelReadySwitch = NSSwitch()
    private let keepModelReadyLabel = NSTextField(
        labelWithString: "Keep model ready"
    )
    private let recordingLimitPopup = NSPopUpButton()
    private let themePopup = NSPopUpButton()
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
        stateProvider: stateProvider
    )
    private weak var settingsRootView: NSView?
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
        configureLoginItemControls()
        configureHelpButton()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 540),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings for whisper_hotkey"
        window.titlebarAppearsTransparent = true
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
        select(mode: state.activationMode)
        select(model: state.selectedModel)
        keepModelReadySwitch.state = state.keepModelReady ? .on : .off
        select(rawValue: state.recordingLimit.rawValue, in: recordingLimitPopup)
        select(rawValue: state.selectedTheme.rawValue, in: themePopup)

        hotkeyPopup.isEnabled = state.configurationEnabled
        modeControl.isEnabled = state.configurationEnabled
        modelControl.isEnabled = state.configurationEnabled
        keepModelReadySwitch.isEnabled = state.configurationEnabled
        keepModelReadyLabel.textColor = state.configurationEnabled
            ? .labelColor
            : .disabledControlTextColor
        recordingLimitPopup.isEnabled = state.configurationEnabled
        themePopup.isEnabled = state.configurationEnabled

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

    @objc private func toggleKeepModelReady(_ sender: NSSwitch) {
        guard stateProvider().configurationEnabled else {
            refresh()
            return
        }
        actions.setKeepModelReady(sender.state == .on)
        refresh()
    }

    @objc private func selectTheme(_ sender: NSPopUpButton) {
        guard stateProvider().configurationEnabled,
              let rawValue = sender.selectedItem?.representedObject as? String,
              let theme = BadgeTheme(rawValue: rawValue)
        else {
            refresh()
            return
        }
        actions.selectTheme(theme)
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
        keepModelReadySwitch.target = self
        keepModelReadySwitch.action = #selector(toggleKeepModelReady(_:))
        keepModelReadySwitch.toolTip =
            "Keeps the selected Whisper model loaded for the fastest transcription."
        keepModelReadySwitch.setAccessibilityLabel("Keep Model Ready")
        configure(
            recordingLimitPopup,
            values: RecordingLimit.allCases.map {
                ($0.displayName, $0.rawValue)
            },
            action: #selector(selectRecordingLimit(_:))
        )
        configure(
            themePopup,
            values: BadgeTheme.allCases.map {
                ($0.displayName, $0.rawValue)
            },
            action: #selector(selectTheme(_:))
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

    private func updateSummary(
        using state: AdvancedSettingsState,
        loginStatus: LoginItemStatus
    ) {
        hotkeySummary.stringValue = state.selectedHotkey.displayName
        modeSummary.stringValue = DictationModePresentation.optionTitle(
            for: state.activationMode
        )
        modelSummary.stringValue =
            "\(DictationModelPresentation.chipTitle(for: state.selectedModel)) "
            + (state.keepModelReady ? "Ready" : "On Demand")
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

    private func applyTheme(_ theme: BadgeTheme) {
        let palette = BadgeThemePalette.palette(for: theme)
        let background = palette.background.withAlphaComponent(1)
        let secondaryText = palette.primaryText.withAlphaComponent(0.72)
        let sectionText = palette.waveform.withAlphaComponent(0.78)
        let appearanceName: NSAppearance.Name =
            theme == .lightFrost ? .aqua : .darkAqua

        window?.appearance = NSAppearance(named: appearanceName)
        window?.backgroundColor = background
        settingsRootView?.layer?.backgroundColor = background.cgColor
        themedPrimaryLabels.forEach { $0.textColor = palette.primaryText }
        themedSecondaryLabels.forEach { $0.textColor = secondaryText }
        themedSectionLabels.forEach { $0.textColor = sectionText }
        keepModelReadyLabel.textColor = stateProvider().configurationEnabled
            ? palette.primaryText
            : secondaryText.withAlphaComponent(0.48)

        loginItemToggle.contentTintColor = palette.waveform
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

    private func makeContentView() -> NSView {
        let root = NSView()
        root.wantsLayer = true
        settingsRootView = root
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

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
        let readinessControls = NSStackView(
            views: [keepModelReadySwitch, keepModelReadyLabel]
        )
        readinessControls.orientation = .horizontal
        readinessControls.alignment = .centerY
        readinessControls.spacing = 8
        addRow(
            to: recognitionGrid,
            title: "Model readiness",
            control: readinessControls
        )
        addRow(
            to: recognitionGrid,
            title: "Recording limit",
            control: recordingLimitPopup
        )
        sizeColumns(in: recognitionGrid)
        stack.addArrangedSubview(recognitionGrid)
        stack.setCustomSpacing(20, after: recognitionGrid)

        let appearanceTitle = makeSectionTitle("APPEARANCE")
        stack.addArrangedSubview(appearanceTitle)
        let appearanceGrid = makeGrid()
        addRow(to: appearanceGrid, title: "Theme", control: themePopup)
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

        let summary = NSStackView(
            views: [
                hotkeySummary,
                modeSummary,
                modelSummary,
                limitSummary,
                themeSummary,
                loginSummary,
            ]
        )
        summary.orientation = .horizontal
        summary.alignment = .centerY
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
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -32),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 26),
            stack.bottomAnchor.constraint(
                lessThanOrEqualTo: root.bottomAnchor,
                constant: -24
            ),
            subtitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
            inputGrid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            recognitionGrid.widthAnchor.constraint(equalTo: stack.widthAnchor),
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

    var selectedLimitForTesting: RecordingLimit? {
        selectedValue(in: recordingLimitPopup)
    }

    var selectedThemeForTesting: BadgeTheme? {
        selectedValue(in: themePopup)
    }

    var windowBackgroundForTesting: NSColor? {
        window?.backgroundColor
    }

    var configurationControlsEnabledForTesting: Bool {
        hotkeyPopup.isEnabled
            && modelControl.isEnabled
            && keepModelReadySwitch.isEnabled
            && recordingLimitPopup.isEnabled
            && themePopup.isEnabled
    }

    var modeControlEnabledForTesting: Bool {
        modeControl.isEnabled
    }

    var usesChipSelectionForTesting: Bool {
        modeControl.segmentStyle == .rounded
            && modeControl.trackingMode == .selectOne
            && modelControl.segmentStyle == .rounded
            && modelControl.trackingMode == .selectOne
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
            ("readiness switch", keepModelReadySwitch),
            ("readiness label", keepModelReadyLabel),
            ("limit", recordingLimitPopup),
            ("theme", themePopup),
            ("login toggle", loginItemToggle),
            ("hotkey summary", hotkeySummary),
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
            recordingLimitPopup.numberOfItems,
            themePopup.numberOfItems,
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

    func setKeepModelReadyForTesting(_ enabled: Bool) {
        keepModelReadySwitch.state = enabled ? .on : .off
        toggleKeepModelReady(keepModelReadySwitch)
    }

    var keepModelReadyForTesting: Bool {
        keepModelReadySwitch.state == .on
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
