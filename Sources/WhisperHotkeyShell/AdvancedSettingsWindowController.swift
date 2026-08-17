import AppKit
import WhisperHotkeyCore
import WhisperHotkeySystem

public struct AdvancedSettingsState: Equatable, Sendable {
    public let selectedHotkey: HotkeyKey
    public let activationMode: HotkeyActivationMode
    public let selectedModel: DictationModel
    /// Parakeet's own selection, kept beside the whisper one so switching
    /// engines never overwrites the other engine's choice.
    public let selectedParakeetVariant: ParakeetVariant
    /// Which preset the current configuration represents, or `.custom`.
    /// Derived, never stored: the advanced controls remain the source of truth.
    public var recognitionPreset: RecognitionPreset {
        RecognitionPreset.matching(
            engine: selectedEngine,
            parakeetVariant: selectedParakeetVariant,
            processingMode: processingMode
        )
    }
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
    public let automaticallyChecksForUpdates: Bool
    public let softwareUpdateStatus: SoftwareUpdateStatus
    public let postProcessingEnabled: Bool
    public let postProcessingProfile: SemanticProfileID
    public let postProcessingModel: String
    public let postProcessingThinkingEnabled: Bool
    public let postProcessingReasoningEffort: String
    public let postProcessingCustomPrompt: String
    public let postProcessingCustomPromptNames: [String]
    public let postProcessingSelectedCustomPrompt: Int
    /// Outcome of the most recent enhancement, or nil when none has run.
    public let postProcessingLastRun: String?

    public init(
        selectedHotkey: HotkeyKey,
        activationMode: HotkeyActivationMode,
        selectedModel: DictationModel,
        selectedParakeetVariant: ParakeetVariant = .defaultVariant,
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
        configurationEnabled: Bool,
        automaticallyChecksForUpdates: Bool = false,
        softwareUpdateStatus: SoftwareUpdateStatus = .idle,
        postProcessingEnabled: Bool = false,
        postProcessingProfile: SemanticProfileID = .clarity,
        postProcessingModel: String = PostProcessingPreference.defaultModel,
        postProcessingThinkingEnabled: Bool = false,
        postProcessingCustomPrompt: String =
            PostProcessingPreference.defaultCustomPrompt,
        postProcessingCustomPromptNames: [String] = ["My prompt"],
        postProcessingSelectedCustomPrompt: Int = 0,
        postProcessingLastRun: String? = nil,
        postProcessingReasoningEffort: String =
            PostProcessingPreference.defaultReasoningEffort
    ) {
        self.selectedHotkey = selectedHotkey
        self.activationMode = activationMode
        self.selectedModel = selectedModel
        self.selectedParakeetVariant = selectedParakeetVariant
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
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        self.softwareUpdateStatus = softwareUpdateStatus
        self.postProcessingEnabled = postProcessingEnabled
        self.postProcessingProfile = postProcessingProfile
        self.postProcessingModel = postProcessingModel
        self.postProcessingThinkingEnabled = postProcessingThinkingEnabled
        self.postProcessingReasoningEffort = postProcessingReasoningEffort
        self.postProcessingCustomPrompt = postProcessingCustomPrompt
        self.postProcessingCustomPromptNames = postProcessingCustomPromptNames
        self.postProcessingSelectedCustomPrompt =
            postProcessingSelectedCustomPrompt
        self.postProcessingLastRun = postProcessingLastRun
    }
}

@MainActor
public struct AdvancedSettingsActions {
    public var selectDictationMode: (HotkeyActivationMode) -> Void
    public var selectHotkey: (HotkeyKey) -> Void
    public var selectModel: (DictationModel) -> Void
    public var selectParakeetVariant: (ParakeetVariant) -> Void
    public var selectRecognitionPreset: (RecognitionPreset) -> Void
    public var selectRecognitionChoice: (RecognitionChoice) -> Void
    public var selectEngine: (RecognitionEngine) -> Void
    public var selectDecodingProfile: (DecodingProfile) -> Void
    public var selectProcessingMode: (ModelProcessingMode) -> Void
    public var addInternalDictionaryEntries: ([String]) -> Void
    public var removeInternalDictionaryEntry: (String) -> Void
    public var setKeepsLatestDictation: (Bool) -> Void
    public var selectRecordingLimit: (RecordingLimit) -> Void
    public var selectTheme: (BadgeThemeSelection) -> Void
    public var saveCustomTheme: (CustomBadgeTheme) -> Void
    public var loginItemChanged: () -> Void
    public var setAutomaticallyChecksForUpdates: (Bool) -> Void
    public var checkForUpdates: () -> Void
    public var installUpdate: () -> Void
    /// Aborts an in-flight model install started from this window.
    public var cancelModelInstall: () -> Void
    public var setPostProcessingEnabled: (Bool) -> Void
    public var selectPostProcessingProfile: (SemanticProfileID) -> Void
    public var selectPostProcessingModel: (String) -> Void
    public var setPostProcessingThinkingEnabled: (Bool) -> Void
    public var selectPostProcessingReasoningEffort: (String) -> Void
    public var setPostProcessingCustomPrompt: (String) -> Void
    public var selectPostProcessingCustomPrompt: (Int) -> Void
    public var addPostProcessingCustomPrompt: () -> Void
    public var removePostProcessingCustomPrompt: () -> Void

    public init(
        selectDictationMode: @escaping (HotkeyActivationMode) -> Void,
        selectHotkey: @escaping (HotkeyKey) -> Void,
        selectModel: @escaping (DictationModel) -> Void,
        selectParakeetVariant: @escaping (ParakeetVariant) -> Void = { _ in },
        selectRecognitionPreset: @escaping (RecognitionPreset) -> Void = { _ in },
        selectRecognitionChoice: @escaping (RecognitionChoice) -> Void = { _ in },
        selectEngine: @escaping (RecognitionEngine) -> Void = { _ in },
        selectDecodingProfile: @escaping (DecodingProfile) -> Void = { _ in },
        selectProcessingMode: @escaping (ModelProcessingMode) -> Void = { _ in },
        addInternalDictionaryEntries: @escaping ([String]) -> Void = { _ in },
        removeInternalDictionaryEntry: @escaping (String) -> Void = { _ in },
        setKeepsLatestDictation: @escaping (Bool) -> Void = { _ in },
        selectRecordingLimit: @escaping (RecordingLimit) -> Void,
        selectTheme: @escaping (BadgeThemeSelection) -> Void = { _ in },
        saveCustomTheme: @escaping (CustomBadgeTheme) -> Void = { _ in },
        loginItemChanged: @escaping () -> Void = {},
        setAutomaticallyChecksForUpdates: @escaping (Bool) -> Void = { _ in },
        checkForUpdates: @escaping () -> Void = {},
        installUpdate: @escaping () -> Void = {},
        cancelModelInstall: @escaping () -> Void = {},
        setPostProcessingEnabled: @escaping (Bool) -> Void = { _ in },
        selectPostProcessingProfile:
            @escaping (SemanticProfileID) -> Void = { _ in },
        selectPostProcessingModel: @escaping (String) -> Void = { _ in },
        setPostProcessingThinkingEnabled:
            @escaping (Bool) -> Void = { _ in },
        selectPostProcessingReasoningEffort:
            @escaping (String) -> Void = { _ in },
        setPostProcessingCustomPrompt: @escaping (String) -> Void = { _ in },
        selectPostProcessingCustomPrompt: @escaping (Int) -> Void = { _ in },
        addPostProcessingCustomPrompt: @escaping () -> Void = {},
        removePostProcessingCustomPrompt: @escaping () -> Void = {}
    ) {
        self.selectDictationMode = selectDictationMode
        self.selectHotkey = selectHotkey
        self.selectModel = selectModel
        self.selectParakeetVariant = selectParakeetVariant
        self.selectRecognitionPreset = selectRecognitionPreset
        self.selectRecognitionChoice = selectRecognitionChoice
        self.selectEngine = selectEngine
        self.selectDecodingProfile = selectDecodingProfile
        self.selectProcessingMode = selectProcessingMode
        self.addInternalDictionaryEntries = addInternalDictionaryEntries
        self.removeInternalDictionaryEntry = removeInternalDictionaryEntry
        self.setKeepsLatestDictation = setKeepsLatestDictation
        self.selectRecordingLimit = selectRecordingLimit
        self.selectTheme = selectTheme
        self.saveCustomTheme = saveCustomTheme
        self.loginItemChanged = loginItemChanged
        self.setAutomaticallyChecksForUpdates =
            setAutomaticallyChecksForUpdates
        self.checkForUpdates = checkForUpdates
        self.installUpdate = installUpdate
        self.cancelModelInstall = cancelModelInstall
        self.setPostProcessingEnabled = setPostProcessingEnabled
        self.selectPostProcessingProfile = selectPostProcessingProfile
        self.selectPostProcessingModel = selectPostProcessingModel
        self.setPostProcessingThinkingEnabled =
            setPostProcessingThinkingEnabled
        self.selectPostProcessingReasoningEffort =
            selectPostProcessingReasoningEffort
        self.setPostProcessingCustomPrompt = setPostProcessingCustomPrompt
        self.selectPostProcessingCustomPrompt =
            selectPostProcessingCustomPrompt
        self.addPostProcessingCustomPrompt = addPostProcessingCustomPrompt
        self.removePostProcessingCustomPrompt =
            removePostProcessingCustomPrompt
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
        case .largeV3TurboQ5:
            "Turbo"
        }
    }
}

enum PostProcessingSettingsPresentation {
    static let processorModels: [(title: String, rawValue: String)] = [
        ("DeepSeek V4 Flash", "deepseek-v4-flash"),
        ("DeepSeek V4 Pro", "deepseek-v4-pro"),
    ]
    static let reasoningEfforts: [(title: String, rawValue: String)] = [
        ("Low", "low"),
        ("Medium", "medium"),
        ("High", "high"),
        ("X-High", "xhigh"),
        ("Max", "max"),
    ]
}

@MainActor
public final class AdvancedSettingsWindowController:
    NSWindowController,
    NSWindowDelegate,
    NSTextFieldDelegate
{
    public typealias StateProvider = () -> AdvancedSettingsState

    private let stateProvider: StateProvider
    private let actions: AdvancedSettingsActions
    private let loginItemManager: LoginItemManager
    private let hotkeyPopup = NSPopUpButton()
    private let modeControl = NSSegmentedControl()
    /// One grouped list in place of the engine and model rows. Those two
    /// described a matrix whose cells are not all valid; this names the real
    /// configurations.
    private let recognitionChoicePopup = NSPopUpButton()
    private let presetControl = NSSegmentedControl()
    private let installProgress = NSProgressIndicator()
    private let installStatusLabel = NSTextField(labelWithString: "")
    private let installCancelButton = NSButton()
    private var installRow: NSGridRow?
    /// Drives the estimated portion of the bar. Core ML compilation reports no
    /// byte count, so the segment is advanced on a timer instead of freezing.
    private var installEstimateTimer: Timer?
    private var installEstimateStart: Date?
    private var installEstimatedSeconds: TimeInterval = 1
    private var installEstimateRange: ClosedRange<Double> = 0...1
    /// A labelled button rather than a disclosure triangle: a bare triangle
    /// renders as a stray glyph beside the preset chips and says nothing about
    /// what it opens.
    private let decodingControl = NSSegmentedControl()
    /// Held so the Decoding row can be hidden outright on engines that have no
    /// beam search. A disabled segmented control still paints its selection,
    /// which reads as "this is on".
    private var decodingRow: NSGridRow?
    /// Held so the whole vocabulary row can be hidden on an engine that
    /// accepts no prompt.
    private var internalDictionaryRow: NSGridRow?
    /// Which chip set the Model row currently shows, so `refresh` only rebuilds
    /// the control when the engine actually changes what belongs there.
    /// Row order of the RECOGNITION section, recorded as the grid is built so
    /// a test can assert the section reads in dependency order.
    private var recognitionRowTitles: [String] = []

    private enum ModelRowKind: Equatable {
        case whisper
        case parakeet

        init(engine: RecognitionEngine) {
            self = engine == .parakeetCoreML ? .parakeet : .whisper
        }
    }
    private let processingModeControl = NSSegmentedControl()
    private let internalDictionaryDraftField = NSTextField()
    private let internalDictionaryPreviewLabel = NSTextField(labelWithString: "")
    private let internalDictionaryAddButton = NSButton(
        title: "Add",
        target: nil,
        action: nil
    )
    private let internalDictionaryExistingStack = NSStackView()
    /// The one width the labelled two-column rows are laid out for.
    static let settingsContentWidth: CGFloat = 620
    /// Padding above and below the settings stack inside the document view.
    private static let settingsContentInsets: CGFloat = 26 + 24
    /// Breathing room kept between the window and the edges of the display.
    private static let settingsScreenMargin: CGFloat = 40

    private let internalDictionaryExistingScrollView = NSScrollView()
    private lazy var internalDictionaryControl = makeInternalDictionaryControl()
    private let keepLatestDictationToggle = NSButton(
        checkboxWithTitle: "Keep latest dictation",
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
    private let checkForUpdatesButton = NSButton(
        title: "Check for Updates",
        target: nil,
        action: nil
    )
    private let automaticUpdateCheckToggle = NSButton(
        checkboxWithTitle: "Check automatically",
        target: nil,
        action: nil
    )
    private let softwareUpdateStatusLabel = NSTextField(labelWithString: "")
    private let postProcessingToggle = NSButton(
        checkboxWithTitle: "Enhance transcripts",
        target: nil,
        action: nil
    )
    private let postProcessingProfileControl = NSSegmentedControl()
    private let postProcessingModelPopup = NSPopUpButton()
    private let postProcessingCustomPromptField = NSTextField()
    private let postProcessingCustomPromptPopup = NSPopUpButton()
    private let postProcessingCustomPromptAddButton = NSButton(
        title: "New",
        target: nil,
        action: nil
    )
    private let postProcessingCustomPromptRemoveButton = NSButton(
        title: "Delete",
        target: nil,
        action: nil
    )
    private let postProcessingLastRunLabel = NSTextField(labelWithString: "")
    private var postProcessingCustomPromptRow: NSGridRow?
    private let postProcessingThinkingToggle = NSButton(
        checkboxWithTitle: "Think before rewriting",
        target: nil,
        action: nil
    )
    private let postProcessingReasoningControl = NSSegmentedControl()
    private var postProcessingReasoningRow: NSGridRow?
    private let postProcessingAPIKeyField = NSSecureTextField()
    private let postProcessingAPIKeyPasteButton = NSButton(
        title: "Paste",
        target: nil,
        action: nil
    )
    private let postProcessingAPIKeyTestButton = NSButton(
        title: "Test",
        target: nil,
        action: nil
    )
    private let postProcessingAPIKeySaveButton = NSButton(
        title: "Save",
        target: nil,
        action: nil
    )
    private let postProcessingAPIKeyClearButton = NSButton(
        title: "Clear",
        target: nil,
        action: nil
    )
    private let postProcessingAPIKeyStatus = NSTextField(labelWithString: "")
    private var postProcessingKeyCheckTask: Task<Void, Never>?
    private var postProcessingKeyStatusTask: Task<Void, Never>?
    private var postProcessingKeyRevertTask: Task<Void, Never>?
    private var postProcessingKeyCheckInFlight = false
    private let versionLabel = NSTextField(labelWithString: "")
    private let githubButton = NSButton()
    private let helpButton = NSButton()
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
        configureUpdateControls()
        configurePostProcessingControls()
        configureProjectMetadata()
        configureHelpButton()

        let window = SettingsWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Self.settingsContentWidth,
                height: 744
            ),
            // Not resizable: the content is a fixed-width column of labelled
            // rows, so every width but one either stranded the controls or
            // clipped them. The height is chosen to fit the content instead.
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings for whisper_hotkey"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .utilityWindow
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        // The controller is built once and reused, so without this the window
        // stays on whichever Space it was first opened on: activating the app
        // either yanked the user to that Space or appeared to do nothing at
        // all. Moving it to the active Space makes Settings open where the
        // user is looking.
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.delegate = self
        window.contentView = makeContentView()
        self.window = window
        sizeWindowToFitContent()

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
        // A miniaturized window ignores makeKeyAndOrderFront, so the menu item
        // silently did nothing once Settings had been sent to the Dock.
        if window?.isMiniaturized == true {
            window?.deminiaturize(nil)
        }
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    // MARK: - In-window install progress

    /// Shows the progress row and takes the bar to zero.
    ///
    /// `estimatedSeconds` covers the phases that report no byte count, so the
    /// bar keeps moving through them instead of freezing at a number. The
    /// estimate never runs past its segment: it eases toward the segment's top
    /// and only reaches it when the phase actually ends.
    public func beginModelInstall(title: String) {
        installStatusLabel.stringValue = title
        installProgress.doubleValue = 0
        installRow?.isHidden = false
        installCancelButton.isEnabled = true
        stopInstallEstimate()
    }

    /// Reports a phase with a real measurement. `fraction` is that phase's own
    /// completion; `range` is the slice of the overall bar it owns.
    public func updateModelInstall(
        fraction: Double,
        in range: ClosedRange<Double>,
        detail: String
    ) {
        stopInstallEstimate()
        let clamped = min(max(fraction, 0), 1)
        installProgress.doubleValue =
            range.lowerBound
                + clamped * (range.upperBound - range.lowerBound)
        installStatusLabel.stringValue = detail
    }

    /// Reports a phase with no measurement available, advancing its slice on a
    /// timer against a typical duration. The bar still moves and still ends
    /// where the next phase begins, so it never reports backwards.
    public func estimateModelInstall(
        over seconds: TimeInterval,
        in range: ClosedRange<Double>,
        detail: String
    ) {
        installStatusLabel.stringValue = detail
        installEstimateRange = range
        installEstimatedSeconds = max(seconds, 0.5)
        installEstimateStart = Date()
        installEstimateTimer?.invalidate()
        installEstimateTimer = Timer.scheduledTimer(
            withTimeInterval: 0.1,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.advanceInstallEstimate()
            }
        }
    }

    public func finishModelInstall() {
        stopInstallEstimate()
        installProgress.doubleValue = 1
        installRow?.isHidden = true
        installStatusLabel.stringValue = ""
    }

    private func advanceInstallEstimate() {
        guard let start = installEstimateStart else { return }
        let elapsed = Date().timeIntervalSince(start)
        // Eases toward the top of the slice without arriving: an estimate that
        // hits 100% and then waits is worse than one that visibly slows down.
        let progress = 1 - exp(-elapsed / installEstimatedSeconds)
        let span =
            installEstimateRange.upperBound - installEstimateRange.lowerBound
        let value = installEstimateRange.lowerBound + progress * span * 0.98
        installProgress.doubleValue = max(installProgress.doubleValue, value)
    }

    private func stopInstallEstimate() {
        installEstimateTimer?.invalidate()
        installEstimateTimer = nil
        installEstimateStart = nil
    }

    @objc private func cancelModelInstall(_ sender: NSButton) {
        installCancelButton.isEnabled = false
        installStatusLabel.stringValue = "Cancelling…"
        actions.cancelModelInstall()
    }

    var modelInstallVisibleForTesting: Bool {
        installRow?.isHidden == false
    }

    var modelInstallFractionForTesting: Double {
        installProgress.doubleValue
    }

    var modelInstallStatusForTesting: String {
        installStatusLabel.stringValue
    }

    public func refreshIfVisible() {
        guard window?.isVisible == true else {
            return
        }
        refresh()
    }

    public var internalDictionaryDraftIsFocused: Bool {
        guard window?.isVisible == true else {
            return false
        }
        let responder = window?.firstResponder
        return responder === internalDictionaryDraftField
            || responder === internalDictionaryDraftField.currentEditor()
    }

    public func appendDictatedInternalDictionaryDraft(_ transcript: String) {
        let value = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return
        }
        if internalDictionaryDraftField.stringValue.isEmpty {
            internalDictionaryDraftField.stringValue = value
        } else {
            internalDictionaryDraftField.stringValue += ", " + value
        }
        updateInternalDictionaryDraftPreview()
    }

    public func refresh() {
        let state = stateProvider()
        select(rawValue: state.selectedHotkey.rawValue, in: hotkeyPopup)
        select(mode: state.activationMode)
        // The Model row has to carry the right family's chips before a
        // selection is applied to it. Selecting first meant returning from
        // Parakeet asked a two-segment control for segment three.
        let preset = state.recognitionPreset
        rebuildRecognitionChoicePopup(for: state)
        if let index = presetSegments.firstIndex(of: preset) {
            presetControl.selectedSegment = index
        }
        presetControl.isEnabled = state.configurationEnabled
        select(decodingProfile: state.decodingProfile)
        select(processingMode: state.processingMode)
        rebuildInternalDictionaryEntries(state.internalDictionaryEntries)
        updateInternalDictionaryDraftPreview()
        keepLatestDictationToggle.state =
            state.keepsLatestDictation ? .on : .off
        automaticUpdateCheckToggle.state =
            state.automaticallyChecksForUpdates ? .on : .off
        softwareUpdateStatusLabel.stringValue =
            state.softwareUpdateStatus.displayText
        switch state.softwareUpdateStatus {
        case .available(_, true):
            checkForUpdatesButton.title = "Update and Restart"
            checkForUpdatesButton.setAccessibilityLabel(
                "Update and Restart"
            )
        default:
            checkForUpdatesButton.title = "Check for Updates"
            checkForUpdatesButton.setAccessibilityLabel(
                "Check for Updates"
            )
        }
        checkForUpdatesButton.isEnabled =
            state.configurationEnabled
                && !state.softwareUpdateStatus.isBusy
        select(rawValue: state.recordingLimit.rawValue, in: recordingLimitPopup)
        rebuildThemePopup(using: state)
        select(rawValue: state.selectedTheme.identifier, in: themePopup)

        hotkeyPopup.isEnabled = state.configurationEnabled
        modeControl.isEnabled = state.configurationEnabled
        decodingControl.isEnabled = state.configurationEnabled
        // Hidden rather than greyed: an engine with no beam search has no
        // decoding profile, so showing one selected would be a lie.
        decodingRow?.isHidden = !state.selectedEngine.usesWhisperDecoding
        processingModeControl.isEnabled = state.configurationEnabled
        // Hidden, like Decoding, rather than shown disabled under a sentence
        // explaining why it does nothing. An engine that accepts no prompt has
        // no vocabulary setting; entries stay saved for the whisper engines.
        internalDictionaryRow?.isHidden =
            !state.selectedEngine.supportsPromptConditioning
        internalDictionaryDraftField.isEnabled = state.configurationEnabled
        internalDictionaryAddButton.isEnabled = state.configurationEnabled
            && !currentInternalDictionaryDraftResult.candidates.isEmpty
        internalDictionaryExistingStack.arrangedSubviews
            .compactMap { $0 as? NSButton }
            .forEach {
                $0.isEnabled = state.configurationEnabled
            }
        keepLatestDictationToggle.isEnabled = state.configurationEnabled
        recordingLimitPopup.isEnabled = state.configurationEnabled
        themePopup.isEnabled = state.configurationEnabled
        newThemeButton.isEnabled = state.configurationEnabled
        editThemeButton.isEnabled =
            state.configurationEnabled
                && state.selectedTheme.customTheme != nil

        for (index, mode) in dictationModes.enumerated() {
            modeControl.setEnabled(
                state.configurationEnabled
                    && (mode != .hold || !state.selectedHotkey.requiresToggleMode),
                forSegment: index
            )
        }

        let loginStatus = loginItemManager.status
        updateLoginItemControls(loginStatus)
        applyTheme(state.selectedTheme)
        loginItemToggle.isEnabled =
            state.configurationEnabled && loginStatus != .unknown
        loginItemSettingsButton.isEnabled = state.configurationEnabled
        automaticUpdateCheckToggle.isEnabled = state.configurationEnabled

        postProcessingToggle.state = state.postProcessingEnabled ? .on : .off
        postProcessingToggle.isEnabled = state.configurationEnabled
        select(profile: state.postProcessingProfile)
        postProcessingProfileControl.isEnabled = state.configurationEnabled
        postProcessingCustomPromptRow?.isHidden =
            state.postProcessingProfile != .custom
        if postProcessingCustomPromptField.currentEditor() == nil {
            postProcessingCustomPromptField.stringValue =
                state.postProcessingCustomPrompt
        }
        postProcessingCustomPromptField.isEnabled = state.configurationEnabled
        postProcessingCustomPromptPopup.removeAllItems()
        postProcessingCustomPromptPopup.addItems(
            withTitles: state.postProcessingCustomPromptNames
        )
        if state.postProcessingCustomPromptNames.indices
            .contains(state.postProcessingSelectedCustomPrompt)
        {
            postProcessingCustomPromptPopup.selectItem(
                at: state.postProcessingSelectedCustomPrompt
            )
        }
        postProcessingCustomPromptPopup.isEnabled = state.configurationEnabled
        postProcessingCustomPromptAddButton.isEnabled =
            state.configurationEnabled
        postProcessingCustomPromptRemoveButton.isEnabled =
            state.configurationEnabled
        postProcessingLastRunLabel.stringValue =
            state.postProcessingLastRun ?? "No enhancement has run yet"
        select(rawValue: state.postProcessingModel, in: postProcessingModelPopup)
        postProcessingModelPopup.isEnabled = state.configurationEnabled
        postProcessingThinkingToggle.state =
            state.postProcessingThinkingEnabled ? .on : .off
        postProcessingThinkingToggle.isEnabled = state.configurationEnabled
        postProcessingReasoningRow?.isHidden =
            !state.postProcessingThinkingEnabled
        select(reasoningEffort: state.postProcessingReasoningEffort)
        postProcessingReasoningControl.isEnabled =
            state.configurationEnabled && state.postProcessingThinkingEnabled
        postProcessingAPIKeyField.isEnabled = state.configurationEnabled
        postProcessingAPIKeySaveButton.isEnabled = state.configurationEnabled
        postProcessingAPIKeyClearButton.isEnabled = state.configurationEnabled
        updatePostProcessingAPIKeyStatus()

        sizeWindowToFitContent()
    }

    public func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)
        internalDictionaryDraftField.stringValue = ""
        updateInternalDictionaryDraftPreview()
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

    @objc private func selectRecognitionPreset(_ sender: NSSegmentedControl) {
        let state = stateProvider()
        guard state.configurationEnabled,
              RecognitionPreset.selectable.indices.contains(
                sender.selectedSegment
              )
        else {
            refresh()
            return
        }
        actions.selectRecognitionPreset(
            RecognitionPreset.selectable[sender.selectedSegment]
        )
        refresh()
    }


    @objc private func selectDecodingProfile(
        _ sender: NSSegmentedControl
    ) {
        let state = stateProvider()
        guard state.configurationEnabled,
              state.selectedEngine.usesWhisperDecoding,
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

    @objc private func toggleLatestDictationRetention(_ sender: NSButton) {
        guard stateProvider().configurationEnabled else {
            refresh()
            return
        }
        actions.setKeepsLatestDictation(sender.state == .on)
        refresh()
    }

    public func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSTextField
                === internalDictionaryDraftField
        else {
            return
        }
        updateInternalDictionaryDraftPreview()
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

    /// Fits the window to the settings content rather than to a fixed height.
    ///
    /// Rows appear and disappear with the selected engine, so a hardcoded
    /// height was always wrong in one direction: empty space when rows were
    /// hidden, a scrollbar when they were not. The scroll view stays as the
    /// fallback for a display too short to show everything.
    private func sizeWindowToFitContent() {
        guard let window,
              let stack = settingsStack,
              collapsedSettingsFrame == nil,
              !window.styleMask.contains(.fullScreen)
        else {
            return
        }
        window.contentView?.layoutSubtreeIfNeeded()
        var height = (stack.fittingSize.height + Self.settingsContentInsets)
            .rounded(.up)
        // The screen only ever shrinks the window, and only once there is a
        // screen to measure against. Folding the margin into the unclamped
        // case made the window 40pt shorter than its own content wherever no
        // display was reported, which put the footer outside the frame.
        if window.isVisible,
           let visible = (window.screen ?? NSScreen.main)?.visibleFrame.height,
           height > visible - Self.settingsScreenMargin {
            height = visible - Self.settingsScreenMargin
        }
        guard abs(height - window.contentLayoutRect.height) > 0.5 else {
            return
        }
        let wasVisible = window.isVisible
        window.setContentSize(
            NSSize(width: Self.settingsContentWidth, height: height)
        )
        if !wasVisible {
            window.center()
        }
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

    @objc private func toggleAutomaticUpdateChecks(_ sender: NSButton) {
        guard stateProvider().configurationEnabled else {
            refresh()
            return
        }
        actions.setAutomaticallyChecksForUpdates(sender.state == .on)
        refresh()
    }

    @objc private func checkForUpdates() {
        guard stateProvider().configurationEnabled else {
            refresh()
            return
        }
        if case .available(_, true) = stateProvider().softwareUpdateStatus {
            actions.installUpdate()
        } else {
            actions.checkForUpdates()
        }
        refresh()
    }

    @objc private func toggleUserGuide() {
        userGuidePopover.toggle(relativeTo: helpButton)
    }

    @objc private func togglePostProcessing(_ sender: NSButton) {
        guard stateProvider().configurationEnabled else {
            refresh()
            return
        }
        actions.setPostProcessingEnabled(sender.state == .on)
        refresh()
    }

    @objc private func selectPostProcessingProfile(
        _ sender: NSSegmentedControl
    ) {
        let state = stateProvider()
        guard state.configurationEnabled,
              SemanticProfileID.allCases.indices.contains(
                  sender.selectedSegment
              )
        else {
            refresh()
            return
        }
        actions.selectPostProcessingProfile(
            SemanticProfileID.allCases[sender.selectedSegment]
        )
        refresh()
    }

    @objc private func selectPostProcessingModel(_ sender: NSPopUpButton) {
        guard stateProvider().configurationEnabled,
              let rawValue = sender.selectedItem?.representedObject
                  as? String
        else {
            refresh()
            return
        }
        actions.selectPostProcessingModel(rawValue)
        refresh()
    }

    @objc private func togglePostProcessingThinking(_ sender: NSButton) {
        guard stateProvider().configurationEnabled else {
            refresh()
            return
        }
        actions.setPostProcessingThinkingEnabled(sender.state == .on)
        refresh()
    }

    @objc private func selectPostProcessingReasoningEffort(
        _ sender: NSSegmentedControl
    ) {
        guard stateProvider().configurationEnabled,
              PostProcessingSettingsPresentation.reasoningEfforts.indices
                  .contains(sender.selectedSegment)
        else {
            refresh()
            return
        }
        actions.selectPostProcessingReasoningEffort(
            PostProcessingSettingsPresentation.reasoningEfforts[
                sender.selectedSegment
            ].rawValue
        )
        refresh()
    }

    /// Commits the owner's custom-profile prompt. Blank input clears the
    /// stored prompt, which restores the built-in default text.
    @objc private func commitPostProcessingCustomPrompt(
        _ sender: NSTextField
    ) {
        guard stateProvider().configurationEnabled else {
            refresh()
            return
        }
        actions.setPostProcessingCustomPrompt(sender.stringValue)
        refresh()
    }

    @objc private func selectPostProcessingCustomPrompt(
        _ sender: NSPopUpButton
    ) {
        guard stateProvider().configurationEnabled else {
            refresh()
            return
        }
        actions.selectPostProcessingCustomPrompt(sender.indexOfSelectedItem)
        refresh()
    }

    @objc private func addPostProcessingCustomPrompt() {
        guard stateProvider().configurationEnabled else { return }
        actions.addPostProcessingCustomPrompt()
        refresh()
    }

    @objc private func removePostProcessingCustomPrompt() {
        guard stateProvider().configurationEnabled else { return }
        actions.removePostProcessingCustomPrompt()
        refresh()
    }

    @objc private func pastePostProcessingAPIKey() {
        guard stateProvider().configurationEnabled,
              !postProcessingKeyCheckInFlight
        else {
            return
        }
        let pasted = NSPasteboard.general
            .string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pasted, !pasted.isEmpty else {
            showPostProcessingKeyFeedback(
                success: false,
                text: "Clipboard has no text"
            )
            return
        }
        postProcessingAPIKeyField.stringValue = pasted
        updatePostProcessingAPIKeyStatus()
    }

    /// Validates the typed key against the API with the currently selected
    /// model, then stores it in the keychain only on success. A failed check
    /// never overwrites a working stored key.
    @objc private func savePostProcessingAPIKey() {
        validatePostProcessingKey(persist: true)
    }

    /// Validates the typed key without storing anything.
    @objc private func testPostProcessingAPIKey() {
        validatePostProcessingKey(persist: false)
    }

    @objc private func clearPostProcessingAPIKey() {
        guard stateProvider().configurationEnabled else {
            refresh()
            return
        }
        postProcessingKeyCheckTask?.cancel()
        postProcessingKeyRevertTask?.cancel()
        do {
            try ProcessorKeychain.delete()
            postProcessingAPIKeyField.stringValue = ""
        } catch {
            postProcessingAPIKeyStatus.stringValue = "Clear failed"
            return
        }
        updatePostProcessingAPIKeyStatus()
    }

    private func validatePostProcessingKey(persist: Bool) {
        guard stateProvider().configurationEnabled,
              !postProcessingKeyCheckInFlight
        else {
            return
        }
        let key = postProcessingAPIKeyField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            updatePostProcessingAPIKeyStatus()
            return
        }
        let model = stateProvider().postProcessingModel
        postProcessingKeyCheckInFlight = true
        postProcessingKeyRevertTask?.cancel()
        setPostProcessingKeyControlsEnabled(false)
        setPostProcessingKeyStatus(text: "Testing…", color: .secondaryLabelColor)

        let processor = DeepSeekTranscriptProcessor(
            apiKeyProvider: { key },
            configuration: DeepSeekConfiguration(model: model)
        )
        postProcessingKeyCheckTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.postProcessingKeyCheckInFlight = false
                self.setPostProcessingKeyControlsEnabled(true)
            }
            do {
                try await processor.validateCredentials()
            } catch {
                self.showPostProcessingKeyFeedback(
                    success: false,
                    text: Self.postProcessingKeyFailureText(error)
                )
                return
            }
            guard persist else {
                self.showPostProcessingKeyFeedback(
                    success: true,
                    text: "Key works"
                )
                return
            }
            do {
                try ProcessorKeychain.store(apiKey: key)
                self.postProcessingAPIKeyField.stringValue = ""
            } catch {
                self.showPostProcessingKeyFeedback(
                    success: false,
                    text: "Save failed"
                )
                return
            }
            self.showPostProcessingKeyFeedback(
                success: true,
                text: "Key verified and saved"
            )
        }
    }

    private func setPostProcessingKeyControlsEnabled(_ enabled: Bool) {
        let effective = enabled && stateProvider().configurationEnabled
        postProcessingAPIKeyPasteButton.isEnabled = effective
        postProcessingAPIKeyTestButton.isEnabled = effective
        postProcessingAPIKeySaveButton.isEnabled = effective
        postProcessingAPIKeyClearButton.isEnabled = effective
    }

    /// Temporary ✓/✗ feedback; the status reverts to Stored/Not stored after
    /// a short delay unless a newer feedback replaces it.
    private func showPostProcessingKeyFeedback(success: Bool, text: String) {
        setPostProcessingKeyStatus(
            text: "\(success ? "✓" : "✗") \(text)",
            color: success ? .systemGreen : .systemRed
        )
        postProcessingKeyRevertTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.updatePostProcessingAPIKeyStatus()
        }
    }

    private func setPostProcessingKeyStatus(text: String, color: NSColor) {
        let value = NSMutableAttributedString(string: text)
        value.addAttribute(
            .foregroundColor,
            value: color,
            range: NSRange(location: 0, length: value.length)
        )
        postProcessingAPIKeyStatus.attributedStringValue = value
    }

    private static func postProcessingKeyFailureText(_ error: Error) -> String {
        switch error {
        case ProcessorError.missingKey:
            return "Key is empty"
        case ProcessorError.httpStatus(401):
            return "Key rejected (401)"
        case ProcessorError.httpStatus(403):
            return "Key rejected (403)"
        case ProcessorError.httpStatus(let code):
            return "API error (\(code))"
        case ProcessorError.transport:
            return "Network error"
        default:
            return "Key check failed"
        }
    }

    private func updatePostProcessingAPIKeyStatus() {
        postProcessingKeyRevertTask?.cancel()
        postProcessingKeyRevertTask = nil
        postProcessingKeyStatusTask?.cancel()
        // The keychain read can stall on a restricted ACL; never let it
        // block refresh() or the main thread. The label updates when the
        // read settles.
        postProcessingKeyStatusTask = Task.detached { [weak self] in
            let state: String
            do {
                state = try ProcessorKeychain.read() == nil
                    ? "Not stored"
                    : "Stored"
            } catch {
                state = "Unavailable"
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.postProcessingAPIKeyStatus.stringValue = state
            }
        }
    }

    private var dictationModes: [HotkeyActivationMode] {
        [.hold, .toggle, .pause]
    }

    private func configureControls() {
        configure(
            hotkeyPopup,
            values: HotkeyKey.allCases.map {
                ($0.menuTitle, $0.rawValue)
            },
            action: #selector(selectHotkey(_:))
        )
        configure(
            modeControl,
            labels: dictationModes.map(DictationModePresentation.optionTitle),
            action: #selector(selectDictationMode(_:))
        )
        // Custom is a real, permanently disabled third segment rather than a
        // state with nothing selected, which read as a broken control.
        configure(
            presetControl,
            labels: presetSegments.map(\.displayName),
            action: #selector(selectRecognitionPreset(_:))
        )
        for (index, preset) in presetSegments.enumerated() {
            presetControl.setToolTip(preset.summary, forSegment: index)
        }
        presetControl.setEnabled(false, forSegment: presetSegments.count - 1)
        recognitionChoicePopup.target = self
        recognitionChoicePopup.action = #selector(selectRecognitionChoice(_:))
        recognitionChoicePopup.setAccessibilityLabel("Recognition model")
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
        internalDictionaryDraftField.delegate = self
        internalDictionaryDraftField.target = self
        internalDictionaryDraftField.action =
            #selector(addInternalDictionaryDraft)
        internalDictionaryDraftField.placeholderString =
            "Type or dictate a comma-separated list"
        internalDictionaryDraftField.toolTip =
            "Draft entries stay unsaved until you choose Add."
        internalDictionaryDraftField.setAccessibilityLabel(
            "Add internal dictionary entries"
        )
        internalDictionaryDraftField.maximumNumberOfLines = 3
        internalDictionaryDraftField.lineBreakMode = .byWordWrapping
        internalDictionaryDraftField.cell?.wraps = true
        internalDictionaryDraftField.cell?.usesSingleLineMode = false
        internalDictionaryAddButton.target = self
        internalDictionaryAddButton.action =
            #selector(addInternalDictionaryDraft)
        internalDictionaryAddButton.bezelStyle = .rounded
        internalDictionaryAddButton.setAccessibilityLabel(
            "Add parsed dictionary entries"
        )
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
        keepLatestDictationToggle.setAccessibilityLabel(
            "Keep latest dictation"
        )
    }

    /// Adds a non-selectable section heading to a grouped popup.
    ///
    /// `isEnabled = false` alone is not enough: `NSMenu.autoenablesItems`
    /// defaults to true, which makes AppKit recompute every item's state from
    /// its target and action and discard what was set here. A heading with no
    /// action came back enabled, so it highlighted on hover and could be
    /// clicked, which read as a model that silently refused to be chosen.
    /// Callers must also turn autoenabling off on the menu.
    ///
    /// The title is styled rather than merely disabled so the heading reads as
    /// a category at a glance instead of as an unavailable option.
    private func addSectionHeading(
        _ title: String,
        to popup: NSPopUpButton
    ) {
        let heading = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        heading.isEnabled = false
        heading.attributedTitle = NSAttributedString(
            string: title.uppercased(),
            attributes: [
                .font: NSFont.systemFont(
                    ofSize: NSFont.smallSystemFontSize,
                    weight: .semibold
                ),
                .foregroundColor: NSColor.secondaryLabelColor,
                .kern: 0.6,
            ]
        )
        popup.menu?.addItem(heading)
    }

    private func rebuildThemePopup(using state: AdvancedSettingsState) {
        themePopup.removeAllItems()
        themePopup.menu?.autoenablesItems = false
        for (modeIndex, mode) in BadgeThemeMode.allCases.enumerated() {
            if modeIndex > 0 {
                themePopup.menu?.addItem(.separator())
            }
            addSectionHeading(mode.displayName, to: themePopup)
            for theme in BadgeTheme.allCases where theme.mode == mode {
                themePopup.addItem(withTitle: theme.displayName)
                themePopup.lastItem?.representedObject = theme.rawValue
                themePopup.lastItem?.indentationLevel = 1
            }
        }
        guard !state.customThemes.isEmpty else {
            return
        }
        themePopup.menu?.addItem(.separator())
        addSectionHeading("Custom", to: themePopup)
        for theme in state.customThemes.sorted(by: {
            $0.name.localizedCaseInsensitiveCompare($1.name)
                == .orderedAscending
        }) {
            themePopup.addItem(withTitle: theme.name)
            themePopup.lastItem?.representedObject =
                BadgeThemeSelection.custom(theme).identifier
            themePopup.lastItem?.indentationLevel = 1
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

    private func configureUpdateControls() {
        checkForUpdatesButton.target = self
        checkForUpdatesButton.action = #selector(checkForUpdates)
        checkForUpdatesButton.bezelStyle = .rounded
        checkForUpdatesButton.controlSize = .small
        checkForUpdatesButton.setAccessibilityLabel("Check for Updates")
        automaticUpdateCheckToggle.target = self
        automaticUpdateCheckToggle.action =
            #selector(toggleAutomaticUpdateChecks(_:))
        automaticUpdateCheckToggle.setAccessibilityLabel(
            "Check for updates automatically"
        )
        softwareUpdateStatusLabel.font = .systemFont(
            ofSize: 11,
            weight: .regular
        )
        softwareUpdateStatusLabel.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        themedSecondaryLabels.append(softwareUpdateStatusLabel)
    }

    private func configurePostProcessingControls() {
        postProcessingToggle.target = self
        postProcessingToggle.action = #selector(togglePostProcessing(_:))
        postProcessingToggle.setAccessibilityLabel("Post-processing")
        configure(
            postProcessingProfileControl,
            labels: SemanticProfileID.allCases.map {
                SemanticProfileCatalog.profile($0).name
            },
            action: #selector(selectPostProcessingProfile(_:))
        )
        postProcessingProfileControl.setAccessibilityLabel(
            "Post-processing profile"
        )
        configure(
            postProcessingModelPopup,
            values: PostProcessingSettingsPresentation.processorModels,
            action: #selector(selectPostProcessingModel(_:))
        )
        postProcessingModelPopup.setAccessibilityLabel(
            "Post-processing model"
        )
        postProcessingCustomPromptField.target = self
        postProcessingCustomPromptField.action =
            #selector(commitPostProcessingCustomPrompt(_:))
        postProcessingCustomPromptField.placeholderString =
            PostProcessingPreference.defaultCustomPrompt
        postProcessingCustomPromptField.lineBreakMode = .byTruncatingTail
        postProcessingCustomPromptField.setAccessibilityLabel(
            "Post-processing custom prompt"
        )
        postProcessingCustomPromptPopup.target = self
        postProcessingCustomPromptPopup.action =
            #selector(selectPostProcessingCustomPrompt(_:))
        postProcessingCustomPromptPopup.setAccessibilityLabel(
            "Custom prompt selection"
        )
        for button in [
            postProcessingCustomPromptAddButton,
            postProcessingCustomPromptRemoveButton,
        ] {
            button.bezelStyle = .rounded
            button.controlSize = .small
        }
        postProcessingCustomPromptAddButton.target = self
        postProcessingCustomPromptAddButton.action =
            #selector(addPostProcessingCustomPrompt)
        postProcessingCustomPromptRemoveButton.target = self
        postProcessingCustomPromptRemoveButton.action =
            #selector(removePostProcessingCustomPrompt)
        postProcessingLastRunLabel.font = .systemFont(
            ofSize: 11,
            weight: .regular
        )
        postProcessingLastRunLabel.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        themedSecondaryLabels.append(postProcessingLastRunLabel)
        postProcessingThinkingToggle.target = self
        postProcessingThinkingToggle.action =
            #selector(togglePostProcessingThinking(_:))
        postProcessingThinkingToggle.setAccessibilityLabel(
            "Post-processing thinking"
        )
        configure(
            postProcessingReasoningControl,
            labels: PostProcessingSettingsPresentation.reasoningEfforts
                .map(\.title),
            action: #selector(selectPostProcessingReasoningEffort(_:))
        )
        postProcessingReasoningControl.setAccessibilityLabel(
            "Post-processing reasoning effort"
        )
        postProcessingAPIKeyField.placeholderString = "DeepSeek API key"
        postProcessingAPIKeyField.setAccessibilityLabel("DeepSeek API key")
        postProcessingAPIKeyPasteButton.target = self
        postProcessingAPIKeyPasteButton.action =
            #selector(pastePostProcessingAPIKey)
        postProcessingAPIKeyPasteButton.bezelStyle = .rounded
        postProcessingAPIKeyPasteButton.controlSize = .small
        postProcessingAPIKeyPasteButton.setAccessibilityLabel(
            "Paste API key"
        )
        postProcessingAPIKeyTestButton.target = self
        postProcessingAPIKeyTestButton.action =
            #selector(testPostProcessingAPIKey)
        postProcessingAPIKeyTestButton.bezelStyle = .rounded
        postProcessingAPIKeyTestButton.controlSize = .small
        postProcessingAPIKeyTestButton.setAccessibilityLabel(
            "Test API key"
        )
        postProcessingAPIKeySaveButton.target = self
        postProcessingAPIKeySaveButton.action =
            #selector(savePostProcessingAPIKey)
        postProcessingAPIKeySaveButton.bezelStyle = .rounded
        postProcessingAPIKeySaveButton.controlSize = .small
        postProcessingAPIKeyClearButton.target = self
        postProcessingAPIKeyClearButton.action =
            #selector(clearPostProcessingAPIKey)
        postProcessingAPIKeyClearButton.bezelStyle = .rounded
        postProcessingAPIKeyClearButton.controlSize = .small
        postProcessingAPIKeyStatus.font = .systemFont(ofSize: 11)
        postProcessingAPIKeyStatus.textColor = .secondaryLabelColor
    }

    private func configureProjectMetadata() {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Development"
        versionLabel.stringValue = "Version \(version)"
        versionLabel.font = .monospacedSystemFont(
            ofSize: 10,
            weight: .regular
        )
        versionLabel.setAccessibilityLabel("whisper_hotkey version \(version)")
        themedSecondaryLabels.append(versionLabel)

        githubButton.title = "GitHub ↗"
        githubButton.font = .systemFont(ofSize: 11, weight: .medium)
        githubButton.bezelStyle = .inline
        githubButton.isBordered = false
        githubButton.target = self
        githubButton.action = #selector(openRepository)
        githubButton.toolTip = "Open the whisper_hotkey repository"
        githubButton.setAccessibilityLabel("Open whisper_hotkey on GitHub")
    }

    @objc private func openRepository() {
        guard let url = URL(
            string: "https://github.com/nikhi1g/whisper_hotkey"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
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

    private var currentInternalDictionaryDraftResult:
        InternalDictionaryDraftParseResult
    {
        InternalDictionaryDraftParser.parse(
            internalDictionaryDraftField.stringValue,
            existingEntries: stateProvider().internalDictionaryEntries
        )
    }

    @objc private func addInternalDictionaryDraft() {
        guard stateProvider().configurationEnabled else {
            refresh()
            return
        }
        let result = currentInternalDictionaryDraftResult
        guard !result.candidates.isEmpty else {
            updateInternalDictionaryDraftPreview()
            return
        }
        actions.addInternalDictionaryEntries(result.candidates)
        internalDictionaryDraftField.stringValue = ""
        updateInternalDictionaryDraftPreview()
    }

    @objc private func removeInternalDictionaryEntry(_ sender: NSButton) {
        guard stateProvider().configurationEnabled,
              stateProvider().internalDictionaryEntries.indices.contains(
                sender.tag
              )
        else {
            refresh()
            return
        }
        actions.removeInternalDictionaryEntry(
            stateProvider().internalDictionaryEntries[sender.tag]
        )
    }

    private func updateInternalDictionaryDraftPreview() {
        let result = currentInternalDictionaryDraftResult
        var parts: [String] = []
        if !result.candidates.isEmpty {
            parts.append("Ready: " + result.candidates.joined(separator: " · "))
        }
        if !result.duplicates.isEmpty {
            parts.append("Already saved: \(result.duplicates.count)")
        }
        if !result.rejected.isEmpty {
            parts.append("Could not add: \(result.rejected.count)")
        }
        internalDictionaryPreviewLabel.stringValue = parts.joined(
            separator: "   "
        )
        internalDictionaryAddButton.title = result.candidates.isEmpty
            ? "Add"
            : "Add \(result.candidates.count)"
        internalDictionaryAddButton.isEnabled =
            stateProvider().configurationEnabled
                && !result.candidates.isEmpty
    }

    private func rebuildInternalDictionaryEntries(_ entries: [String]) {
        internalDictionaryExistingStack.arrangedSubviews.forEach { view in
            internalDictionaryExistingStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        if entries.isEmpty {
            let empty = NSTextField(labelWithString: "No saved entries")
            empty.textColor = .secondaryLabelColor
            empty.font = .systemFont(ofSize: 11)
            internalDictionaryExistingStack.addArrangedSubview(empty)
            return
        }
        for (index, entry) in entries.enumerated() {
            let button = NSButton(
                title: "\(entry)  ×",
                target: self,
                action: #selector(removeInternalDictionaryEntry(_:))
            )
            button.tag = index
            button.bezelStyle = .rounded
            button.alignment = .left
            button.setContentCompressionResistancePriority(
                .defaultLow,
                for: .horizontal
            )
            button.cell?.lineBreakMode = .byTruncatingMiddle
            button.setAccessibilityLabel("Remove \(entry)")
            button.toolTip = "Remove \(entry)"
            button.isEnabled = stateProvider().configurationEnabled
            internalDictionaryExistingStack.addArrangedSubview(button)
            button.widthAnchor.constraint(
                lessThanOrEqualTo: internalDictionaryExistingStack.widthAnchor
            ).isActive = true
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
        automaticUpdateCheckToggle.contentTintColor = palette.waveform
        checkForUpdatesButton.contentTintColor = palette.waveform
        loginItemSettingsButton.contentTintColor = palette.waveform
        githubButton.contentTintColor = palette.waveform
        helpButton.contentTintColor = palette.waveform
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

    /// Swaps the Model row between whisper's four sizes and Parakeet's two.
    /// Parakeet is a different model family, not a fourth way to run whisper,
    /// so reusing whisper's names for its checkpoints would misreport what is
    /// selected.
    /// Fast and Accurate are selectable; Custom is a reported state.
    private var presetSegments: [RecognitionPreset] {
        RecognitionPreset.selectable + [.custom]
    }

    /// Grouped like the theme popup: a disabled heading per family, then its
    /// options. Unavailable options stay visible but disabled with a reason,
    /// which is how the engine chips behaved.
    private func rebuildRecognitionChoicePopup(
        for state: AdvancedSettingsState
    ) {
        recognitionChoicePopup.removeAllItems()
        recognitionChoicePopup.menu?.autoenablesItems = false
        for (index, group) in RecognitionChoice.Group.allCases.enumerated() {
            if index > 0 {
                recognitionChoicePopup.menu?.addItem(.separator())
            }
            addSectionHeading(group.displayName, to: recognitionChoicePopup)
            for choice in RecognitionChoice.allCases where choice.group == group {
                let available = state.availableEngines.contains(choice.engine)
                var title = choice.displayName
                if let size = choice.downloadDescription {
                    // A size, not a claim that it still needs downloading:
                    // the option may already be installed.
                    title += " (\(size))"
                }
                recognitionChoicePopup.addItem(withTitle: title)
                let item = recognitionChoicePopup.lastItem
                item?.representedObject = choice.rawValue
                item?.isEnabled = available && state.configurationEnabled
                // Indented under its heading so the two levels read as
                // category and member rather than as a flat list.
                item?.indentationLevel = 1
                item?.toolTip = available
                    ? nil
                    : "Required local files are not installed"
            }
        }
        let selected = RecognitionChoice.matching(
            engine: state.selectedEngine,
            model: state.selectedModel,
            parakeetVariant: state.selectedParakeetVariant
        )
        if let selected,
           let index = recognitionChoicePopup.itemArray.firstIndex(where: {
               $0.representedObject as? String == selected.rawValue
           }) {
            recognitionChoicePopup.selectItem(at: index)
        }
        recognitionChoicePopup.isEnabled = state.configurationEnabled
    }

    @objc private func selectRecognitionChoice(_ sender: NSPopUpButton) {
        let state = stateProvider()
        guard state.configurationEnabled,
              let rawValue = sender.selectedItem?.representedObject as? String,
              let choice = RecognitionChoice(rawValue: rawValue)
        else {
            refresh()
            return
        }
        actions.selectRecognitionChoice(choice)
        refresh()
    }




    /// The Model row changes length with the engine, so every write goes
    /// through here. Assigning an index past the current count raises
    /// NSRangeException from inside AppKit rather than being ignored.


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

    private func select(profile: SemanticProfileID) {
        guard let index = SemanticProfileID.allCases.firstIndex(
            of: profile
        ) else {
            return
        }
        postProcessingProfileControl.selectedSegment = index
    }

    private func select(reasoningEffort: String) {
        guard let index = PostProcessingSettingsPresentation.reasoningEfforts
            .firstIndex(where: { $0.rawValue == reasoningEffort })
        else {
            return
        }
        postProcessingReasoningControl.selectedSegment = index
    }

    private func makeInternalDictionaryControl() -> NSView {
        let addStack = NSStackView()
        addStack.orientation = .vertical
        addStack.alignment = .leading
        addStack.spacing = 6
        addStack.edgeInsets = NSEdgeInsets(
            top: 8,
            left: 8,
            bottom: 8,
            right: 8
        )
        internalDictionaryDraftField.translatesAutoresizingMaskIntoConstraints =
            false
        internalDictionaryDraftField.heightAnchor.constraint(
            greaterThanOrEqualToConstant: 44
        ).isActive = true
        internalDictionaryDraftField.widthAnchor.constraint(
            greaterThanOrEqualToConstant: 176
        ).isActive = true
        internalDictionaryPreviewLabel.font = .systemFont(ofSize: 10)
        internalDictionaryPreviewLabel.textColor = .secondaryLabelColor
        internalDictionaryPreviewLabel.maximumNumberOfLines = 1
        internalDictionaryPreviewLabel.lineBreakMode = .byTruncatingTail
        internalDictionaryPreviewLabel.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        addStack.addArrangedSubview(internalDictionaryDraftField)
        addStack.addArrangedSubview(internalDictionaryPreviewLabel)
        addStack.addArrangedSubview(internalDictionaryAddButton)

        let addBox = NSBox()
        addBox.title = "Add"
        addBox.titlePosition = .atTop
        addBox.boxType = .primary
        addBox.contentView = addStack

        internalDictionaryExistingStack.orientation = .vertical
        internalDictionaryExistingStack.alignment = .leading
        internalDictionaryExistingStack.spacing = 5
        internalDictionaryExistingStack.edgeInsets = NSEdgeInsets(
            top: 4,
            left: 4,
            bottom: 4,
            right: 4
        )
        internalDictionaryExistingStack.translatesAutoresizingMaskIntoConstraints =
            false
        internalDictionaryExistingScrollView.drawsBackground = false
        internalDictionaryExistingScrollView.hasVerticalScroller = true
        internalDictionaryExistingScrollView.autohidesScrollers = true
        internalDictionaryExistingScrollView.borderType = .noBorder
        internalDictionaryExistingScrollView.documentView =
            internalDictionaryExistingStack
        internalDictionaryExistingStack.widthAnchor.constraint(
            equalTo: internalDictionaryExistingScrollView.contentView.widthAnchor
        ).isActive = true
        internalDictionaryExistingScrollView.heightAnchor.constraint(
            greaterThanOrEqualToConstant: 88
        ).isActive = true

        let existingBox = NSBox()
        existingBox.title = "Existing"
        existingBox.titlePosition = .atTop
        existingBox.boxType = .primary
        existingBox.contentView = internalDictionaryExistingScrollView

        let panes = NSStackView(views: [addBox, existingBox])
        panes.orientation = .horizontal
        panes.alignment = .top
        panes.spacing = 10
        panes.distribution = .fillEqually
        panes.translatesAutoresizingMaskIntoConstraints = false
        panes.heightAnchor.constraint(greaterThanOrEqualToConstant: 132).isActive =
            true

        let column = NSStackView(views: [panes])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6
        column.translatesAutoresizingMaskIntoConstraints = false
        return column
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

        // A clip view is not flipped, so a document view shorter than the
        // window is pinned to the bottom and the settings appeared to float
        // under a band of empty space. Flipping it anchors the content to the
        // top, which is where it belongs whether or not it scrolls.
        let documentView = FlippedView()
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
        stack.setCustomSpacing(22, after: title)

        let inputTitle = makeSectionTitle("INPUT")
        stack.addArrangedSubview(inputTitle)
        let inputGrid = makeGrid()
        addRow(to: inputGrid, title: "Dictation key", control: hotkeyPopup)
        addRow(to: inputGrid, title: "Behavior", control: modeControl)
        addRow(
            to: inputGrid,
            title: "Last dictation",
            control: keepLatestDictationToggle
        )
        sizeColumns(in: inputGrid)
        stack.addArrangedSubview(inputGrid)
        stack.setCustomSpacing(20, after: inputGrid)

        let recognitionTitle = makeSectionTitle("RECOGNITION")
        stack.addArrangedSubview(recognitionTitle)
        let recognitionGrid = makeGrid()
        // Engine leads because it decides which models exist and whether
        // Decoding applies at all. Reading top to bottom now follows the
        // dependency rather than cutting across it.
        recognitionRowTitles = [
            "Quality", "Model", "Decoding", "Processing",
            "Internal dictionary", "Recording limit",
        ]
        // "Quality" rather than "Recognition": the row sat inside a section
        // already called RECOGNITION and repeated it.
        addRow(
            to: recognitionGrid,
            title: "Quality",
            control: presetControl
        )
        addRow(
            to: recognitionGrid,
            title: "Model",
            control: recognitionChoicePopup
        )
        // Progress lives in the window that started the work, directly under
        // the control that started it. A floating utility panel was a second
        // window to manage, could be dragged away from its context, and read
        // as a system dialog rather than as part of this app.
        installProgress.isIndeterminate = false
        installProgress.minValue = 0
        installProgress.maxValue = 1
        installProgress.doubleValue = 0
        installProgress.style = .bar
        installProgress.controlSize = .small
        installStatusLabel.font = .systemFont(ofSize: 11)
        installStatusLabel.textColor = .secondaryLabelColor
        installCancelButton.title = "Cancel"
        installCancelButton.bezelStyle = .rounded
        installCancelButton.controlSize = .small
        installCancelButton.target = self
        installCancelButton.action = #selector(cancelModelInstall(_:))
        let installText = NSStackView(
            views: [installStatusLabel, installCancelButton]
        )
        installText.orientation = .horizontal
        installText.alignment = .centerY
        installText.spacing = 8
        let installStack = NSStackView(views: [installProgress, installText])
        installStack.orientation = .vertical
        installStack.alignment = .leading
        installStack.spacing = 4
        installProgress.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            installProgress.widthAnchor.constraint(equalToConstant: 320),
        ])
        installRow = addRow(
            to: recognitionGrid,
            title: "Installing",
            control: installStack
        )
        installRow?.isHidden = true

        decodingRow = addRow(
            to: recognitionGrid,
            title: "Decoding",
            control: decodingControl
        )
        addRow(
            to: recognitionGrid,
            title: "Processing",
            control: processingModeControl
        )
        internalDictionaryRow = addRow(
            to: recognitionGrid,
            title: "Internal dictionary",
            control: internalDictionaryControl
        )
        addRow(
            to: recognitionGrid,
            title: "Recording limit",
            control: recordingLimitPopup
        )
        sizeColumns(in: recognitionGrid)
        stack.addArrangedSubview(recognitionGrid)
        stack.setCustomSpacing(20, after: recognitionGrid)

        let postProcessingTitle = makeSectionTitle("POST-PROCESSING")
        stack.addArrangedSubview(postProcessingTitle)
        let postProcessingGrid = makeGrid()
        addRow(
            to: postProcessingGrid,
            title: "Post-processing",
            control: postProcessingToggle
        )
        addRow(
            to: postProcessingGrid,
            title: "Profile",
            control: postProcessingProfileControl
        )
        let customPromptControls = NSStackView(
            views: [
                postProcessingCustomPromptPopup,
                postProcessingCustomPromptField,
                postProcessingCustomPromptAddButton,
                postProcessingCustomPromptRemoveButton,
            ]
        )
        customPromptControls.orientation = .horizontal
        customPromptControls.alignment = .centerY
        customPromptControls.spacing = 6
        postProcessingCustomPromptField.setContentHuggingPriority(
            .defaultLow,
            for: .horizontal
        )
        postProcessingCustomPromptRow = addRow(
            to: postProcessingGrid,
            title: "Custom prompt",
            control: customPromptControls
        )
        addRow(
            to: postProcessingGrid,
            title: "Processor",
            control: postProcessingModelPopup
        )
        addRow(
            to: postProcessingGrid,
            title: "Thinking",
            control: postProcessingThinkingToggle
        )
        postProcessingReasoningRow = addRow(
            to: postProcessingGrid,
            title: "Reasoning effort",
            control: postProcessingReasoningControl
        )
        let apiKeyControls = NSStackView(
            views: [
                postProcessingAPIKeyField,
                postProcessingAPIKeyPasteButton,
                postProcessingAPIKeyTestButton,
                postProcessingAPIKeySaveButton,
                postProcessingAPIKeyClearButton,
                postProcessingAPIKeyStatus,
            ]
        )
        apiKeyControls.orientation = .horizontal
        apiKeyControls.alignment = .centerY
        apiKeyControls.spacing = 6
        postProcessingAPIKeyField.setContentHuggingPriority(
            .defaultLow,
            for: .horizontal
        )
        postProcessingAPIKeyStatus.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        addRow(
            to: postProcessingGrid,
            title: "API key",
            control: apiKeyControls
        )
        addRow(
            to: postProcessingGrid,
            title: "Last run",
            control: postProcessingLastRunLabel
        )
        sizeColumns(in: postProcessingGrid)
        stack.addArrangedSubview(postProcessingGrid)
        stack.setCustomSpacing(20, after: postProcessingGrid)

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
        let updateControls = NSStackView(
            views: [
                checkForUpdatesButton,
                automaticUpdateCheckToggle,
                softwareUpdateStatusLabel,
            ]
        )
        updateControls.orientation = .horizontal
        updateControls.alignment = .centerY
        updateControls.spacing = 8
        addRow(to: startupGrid, title: "Updates", control: updateControls)
        sizeColumns(in: startupGrid)
        stack.addArrangedSubview(startupGrid)

        // The summary chips that used to sit here repeated six values that are
        // each already visible in a row above, so they added length without
        // adding information.
        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        helpButton.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )
        let projectMetadata = NSStackView(views: [versionLabel, githubButton])
        projectMetadata.orientation = .vertical
        projectMetadata.alignment = .leading
        projectMetadata.spacing = 0
        projectMetadata.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )
        let footer = NSStackView(
            views: [footerSpacer, projectMetadata, helpButton]
        )
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
            inputGrid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            recognitionGrid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            postProcessingGrid.widthAnchor.constraint(
                equalTo: stack.widthAnchor
            ),
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
        grid.column(at: 0).width = 128
        grid.column(at: 1).width = 410
    }

    @discardableResult
    private func addRow(
        to grid: NSGridView,
        title: String,
        control: NSView
    ) -> NSGridRow {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        themedPrimaryLabels.append(label)
        return grid.addRow(with: [label, control])
    }

    var postProcessingCustomPromptVisibleForTesting: Bool {
        postProcessingCustomPromptRow.map { !$0.isHidden } ?? false
    }

    var postProcessingCustomPromptNamesForTesting: [String] {
        postProcessingCustomPromptPopup.itemTitles
    }

    func addPostProcessingCustomPromptForTesting() {
        addPostProcessingCustomPrompt()
    }

    func removePostProcessingCustomPromptForTesting() {
        removePostProcessingCustomPrompt()
    }

    var postProcessingLastRunForTesting: String {
        postProcessingLastRunLabel.stringValue
    }

    var postProcessingCustomPromptTextForTesting: String {
        postProcessingCustomPromptField.stringValue
    }

    /// Drives the custom-prompt field the way a user committing an edit does.
    func commitPostProcessingCustomPromptForTesting(_ prompt: String) {
        postProcessingCustomPromptField.stringValue = prompt
        commitPostProcessingCustomPrompt(postProcessingCustomPromptField)
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

    var selectedRecognitionChoiceForTesting: RecognitionChoice? {
        guard let raw = recognitionChoicePopup.selectedItem?
            .representedObject as? String else {
            return nil
        }
        return RecognitionChoice(rawValue: raw)
    }

    var selectedModelForTesting: DictationModel? {
        selectedRecognitionChoiceForTesting?.model
    }

    var selectedEngineForTesting: RecognitionEngine? {
        selectedRecognitionChoiceForTesting?.engine
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
            && !window.styleMask.contains(.resizable)
    }

    /// The window fits its content when nothing has to be scrolled to reach it.
    var settingsFitWithoutScrollingForTesting: Bool {
        guard let scrollView = settingsScrollView,
              let documentView = scrollView.documentView
        else {
            return false
        }
        scrollView.layoutSubtreeIfNeeded()
        return documentView.fittingSize.height
            <= scrollView.contentView.bounds.height + 0.5
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
            && recognitionChoicePopup.isEnabled
            && decodingControl.isEnabled
            && processingModeControl.isEnabled
            && internalDictionaryDraftField.isEnabled
            && recordingLimitPopup.isEnabled
            && themePopup.isEnabled
            && newThemeButton.isEnabled
    }

    var modeControlEnabledForTesting: Bool {
        modeControl.isEnabled
    }

    var presetChipLabelsForTesting: [String] {
        (0..<presetControl.segmentCount).compactMap {
            presetControl.label(forSegment: $0)
        }
    }

    var selectedPresetForTesting: RecognitionPreset? {
        guard presetSegments.indices.contains(
            presetControl.selectedSegment
        ) else {
            return nil
        }
        return presetSegments[presetControl.selectedSegment]
    }

    var decodingRowVisibleForTesting: Bool {
        decodingRow.map { !$0.isHidden } ?? false
    }

    var internalDictionaryRowVisibleForTesting: Bool {
        internalDictionaryRow.map { !$0.isHidden } ?? false
    }

    var internalDictionaryControlsEnabledForTesting: Bool {
        internalDictionaryDraftField.isEnabled
            && internalDictionaryExistingStack.arrangedSubviews
                .compactMap { $0 as? NSButton }
                .allSatisfy(\.isEnabled)
    }

    /// Selectable options only — the group headings are disabled menu items.
    var recognitionChoiceLabelsForTesting: [String] {
        recognitionChoicePopup.itemArray
            .filter { $0.representedObject != nil }
            .map(\.title)
    }

    var recognitionChoiceHeadingsForTesting: [String] {
        recognitionChoicePopup.itemArray
            .filter { $0.representedObject == nil && !$0.isSeparatorItem }
            .map(\.title)
    }

    /// Headings that AppKit would still let a user click. Must always be
    /// empty: a heading names a family, not something to select.
    var selectableRecognitionHeadingsForTesting: [String] {
        recognitionChoicePopup.itemArray
            .filter {
                $0.representedObject == nil
                    && !$0.isSeparatorItem
                    && $0.isEnabled
            }
            .map(\.title)
    }

    var recognitionChoiceSeparatorCountForTesting: Int {
        recognitionChoicePopup.itemArray.filter(\.isSeparatorItem).count
    }

    var selectableThemeHeadingsForTesting: [String] {
        themePopup.itemArray
            .filter {
                $0.representedObject == nil
                    && !$0.isSeparatorItem
                    && $0.isEnabled
            }
            .map(\.title)
    }

    var recognitionRowTitlesForTesting: [String] {
        recognitionRowTitles
    }

    var decodingControlEnabledForTesting: Bool {
        decodingControl.isEnabled
    }

    var usesChipSelectionForTesting: Bool {
        modeControl.segmentStyle == .rounded
            && modeControl.trackingMode == .selectOne
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
            ("decoding", decodingControl),
            ("processing", processingModeControl),
            ("internal dictionary", internalDictionaryControl),
            ("last dictation retention", keepLatestDictationToggle),
            ("limit", recordingLimitPopup),
            ("theme", themePopup),
            ("new theme", newThemeButton),
            ("edit theme", editThemeButton),
            ("login toggle", loginItemToggle),
            ("check for updates", checkForUpdatesButton),
            ("automatic update checks", automaticUpdateCheckToggle),
            ("version", versionLabel),
            ("github", githubButton),
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

    func recognitionChoiceIsEnabledForTesting(
        _ choice: RecognitionChoice
    ) -> Bool? {
        recognitionChoicePopup.itemArray.first {
            $0.representedObject as? String == choice.rawValue
        }?.isEnabled
    }

    var optionCountsForTesting: [Int] {
        [
            hotkeyPopup.numberOfItems,
            modeControl.segmentCount,
            presetControl.segmentCount,
            recognitionChoicePopup.numberOfItems,
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

    var versionTextForTesting: String {
        versionLabel.stringValue
    }

    var githubAccessibilityLabelForTesting: String? {
        githubButton.accessibilityLabel()
    }

    var automaticallyChecksForUpdatesForTesting: Bool {
        automaticUpdateCheckToggle.state == .on
    }

    var softwareUpdateStatusForTesting: String {
        softwareUpdateStatusLabel.stringValue
    }

    var checkForUpdatesIsEnabledForTesting: Bool {
        checkForUpdatesButton.isEnabled
    }

    var checkForUpdatesTitleForTesting: String {
        checkForUpdatesButton.title
    }

    var helpButtonFrameForTesting: CGRect {
        guard let contentView = window?.contentView else {
            return .zero
        }
        contentView.layoutSubtreeIfNeeded()
        return helpButton.convert(helpButton.bounds, to: contentView)
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


    func selectDecodingProfileForTesting(_ profile: DecodingProfile) {
        select(decodingProfile: profile)
        selectDecodingProfile(decodingControl)
    }

    func selectRecognitionChoiceForTesting(_ choice: RecognitionChoice) {
        guard let index = recognitionChoicePopup.itemArray.firstIndex(where: {
            $0.representedObject as? String == choice.rawValue
        }) else {
            return
        }
        recognitionChoicePopup.selectItem(at: index)
        selectRecognitionChoice(recognitionChoicePopup)
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
        stateProvider().internalDictionaryEntries
    }

    func setInternalDictionaryForTesting(_ entries: [String]) {
        internalDictionaryDraftField.stringValue = entries.joined(
            separator: ", "
        )
        addInternalDictionaryDraft()
    }

    var internalDictionaryDraftForTesting: String {
        internalDictionaryDraftField.stringValue
    }

    var internalDictionaryPreviewForTesting: String {
        internalDictionaryPreviewLabel.stringValue
    }

    func addInternalDictionaryDraftForTesting() {
        addInternalDictionaryDraft()
    }

    func focusInternalDictionaryDraftForTesting() {
        window?.orderFront(nil)
        window?.makeFirstResponder(internalDictionaryDraftField)
    }

    var internalDictionaryDraftAddsOnReturnForTesting: Bool {
        internalDictionaryDraftField.target === self
            && internalDictionaryDraftField.action
                == #selector(addInternalDictionaryDraft)
    }

    func selectAllInternalDictionaryDraftForTesting() -> NSRange? {
        focusInternalDictionaryDraftForTesting()
        guard let window,
              let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .command,
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "a",
                charactersIgnoringModifiers: "a",
                isARepeat: false,
                keyCode: 0
              )
        else {
            return nil
        }
        _ = window.performKeyEquivalent(with: event)
        return internalDictionaryDraftField.currentEditor()?.selectedRange
    }

    var internalDictionaryExistingEntryCountForTesting: Int {
        stateProvider().internalDictionaryEntries.count
    }

    func removeInternalDictionaryEntryForTesting(at index: Int) {
        guard internalDictionaryExistingStack.arrangedSubviews.indices.contains(
            index
        ), let button = internalDictionaryExistingStack.arrangedSubviews[index]
            as? NSButton
        else {
            return
        }
        removeInternalDictionaryEntry(button)
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

    func setAutomaticUpdateChecksForTesting(_ enabled: Bool) {
        automaticUpdateCheckToggle.state = enabled ? .on : .off
        toggleAutomaticUpdateChecks(automaticUpdateCheckToggle)
    }

    func checkForUpdatesForTesting() {
        checkForUpdates()
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

/// Top-anchored container for the settings scroll view's document view.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
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
