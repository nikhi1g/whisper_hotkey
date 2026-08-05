import AppKit
import WhisperHotkeyCore
import WhisperHotkeySystem

struct UserGuideRow: Equatable {
    let key: String
    let title: String
    let detail: String
}

struct UserGuideSection: Equatable {
    let title: String
    let rows: [UserGuideRow]
}

enum UserGuideContent {
    static func sections(
        for state: AdvancedSettingsState,
        loginItemEnabled: Bool = false
    ) -> [UserGuideSection] {
        [
            UserGuideSection(
                title: "YOUR CURRENT PATH",
                rows: currentRows(
                    for: state,
                    loginItemEnabled: loginItemEnabled
                )
            ),
            UserGuideSection(
                title: "OTHER OPTIONS",
                rows: alternativeRows(
                    for: state,
                    loginItemEnabled: loginItemEnabled
                )
            ),
        ]
    }

    private static func currentRows(
        for state: AdvancedSettingsState,
        loginItemEnabled: Bool
    ) -> [UserGuideRow] {
        let hotkey = state.selectedHotkey.displayName
        let behavior = DictationModePresentation.optionTitle(
            for: state.activationMode
        )
        let model = engineModelName(for: state)
        var rows = [
            UserGuideRow(
                key: "active",
                title: "\(hotkey): \(behavior): \(model)",
                detail: activePathDetail(for: state)
            ),
            UserGuideRow(
                key: "key",
                title: hotkey,
                detail:
                    "\(hotkey) controls dictation alone and still passes through in ordinary shortcuts."
            ),
            UserGuideRow(
                key: "behavior",
                title: behavior,
                detail: activationDescription(state.activationMode)
            ),
            UserGuideRow(
                key: "model",
                title: model,
                detail: engineModelDescription(for: state)
            ),
            UserGuideRow(
                key: "engine",
                title: state.selectedEngine.displayName,
                detail: state.selectedEngine.menuTitle
            ),
            UserGuideRow(
                key: "processing",
                title: state.processingMode.displayName,
                detail: state.processingMode.description
            ),
            UserGuideRow(
                key: "limit",
                title: state.recordingLimit.displayName,
                detail: "Dictation finishes automatically at this duration."
            ),
            UserGuideRow(
                key: "theme",
                title: state.selectedTheme.displayName,
                detail: "This palette controls the HUD, Settings, and User Guide."
            ),
            UserGuideRow(
                key: "startup",
                title: loginItemEnabled ? "Open at Login" : "Manual Start",
                detail: loginItemEnabled
                    ? "whisper_hotkey starts automatically after sign-in."
                    : "whisper_hotkey starts only when you launch it."
            ),
            UserGuideRow(
                key: "dictionary",
                title: dictionaryTitle(state.internalDictionaryEntries),
                detail: dictionaryDetail(state.internalDictionaryEntries)
            ),
            UserGuideRow(
                key: "last-dictation",
                title: state.keepsLatestDictation
                    ? "Copy Last Dictation On"
                    : "Copy Last Dictation Off",
                detail: state.keepsLatestDictation
                    ? "Keeps only the latest successful transcript in memory until quit."
                    : "Successful transcripts are not retained after insertion."
            ),
            UserGuideRow(
                key: "esc",
                title: "Discard",
                detail: "Stops dictation and inserts nothing."
            ),
            UserGuideRow(
                key: "return",
                title: "Insert and send",
                detail:
                    "Return or keypad Enter transcribes, inserts, then sends once."
            ),
            UserGuideRow(
                key: "■",
                title: "Stop and insert",
                detail: "The Stop HUD button inserts without sending."
            ),
            UserGuideRow(
                key: "↑",
                title: "Insert and send",
                detail: "The Send HUD button inserts and presses Return."
            ),
            UserGuideRow(
                key: "drag",
                title: "Move the HUD",
                detail:
                    "Drag its waveform or timer to lock it for this session."
            ),
            UserGuideRow(
                key: "focus",
                title: "Choose the destination",
                detail:
                    "Text inserts at the current focus and replaces its selection."
            ),
            UserGuideRow(
                key: "local",
                title: "On-device only",
                detail: "Audio stays local and is deleted after each dictation."
            ),
        ]
        if state.selectedEngine.usesWhisperDecoding,
           let engineIndex = rows.firstIndex(where: { $0.key == "engine" }) {
            // Positioned relative to the engine row rather than at a fixed
            // index, so adding a row above it cannot silently move Decoding.
            rows.insert(
                UserGuideRow(
                    key: "decoding",
                    title: state.decodingProfile.displayName,
                    detail: state.decodingProfile.description
                ),
                at: rows.index(after: engineIndex)
            )
        }
        if state.selectedHotkey == .capsLock {
            rows.insert(
                UserGuideRow(
                    key: "caps",
                    title: "Caps Lock restriction",
                    detail:
                        "Caps Lock supports Toggle and Pause Mode, not Press and Hold."
                ),
                at: 3
            )
        }
        return rows
    }

    private static func alternativeRows(
        for state: AdvancedSettingsState,
        loginItemEnabled: Bool
    ) -> [UserGuideRow] {
        let otherKeys = HotkeyKey.allCases
            .filter { $0 != state.selectedHotkey }
            .map(\.displayName)
            .joined(separator: ", ")
        let otherLimits = RecordingLimit.allCases
            .filter { $0 != state.recordingLimit }
            .map(\.displayName)
            .joined(separator: ", ")
        let selectedThemeID = state.selectedTheme.identifier
        let otherThemes =
            BadgeTheme.allCases.map {
                (identifier: BadgeThemeSelection.builtIn($0).identifier,
                 name: $0.displayName)
            }
            + state.customThemes.map {
                (identifier: BadgeThemeSelection.custom($0).identifier,
                 name: $0.name)
            }
        var rows = [
            UserGuideRow(
                key: "keys",
                title: "Other dictation keys",
                detail: otherKeys
            ),
        ]
        rows.append(
            contentsOf: [
                HotkeyActivationMode.hold,
                .toggle,
                .pause,
            ]
            .filter { $0 != state.activationMode }
            .map {
                UserGuideRow(
                    key: "behavior",
                    title: DictationModePresentation.optionTitle(for: $0),
                    detail: activationDescription($0)
                )
            }
        )
        if state.selectedEngine == .parakeetCoreML {
            rows.append(
                contentsOf: ParakeetVariant.allCases
                    .filter { $0 != state.selectedParakeetVariant }
                    .map {
                        UserGuideRow(
                            key: "model",
                            title: $0.displayName,
                            detail: $0.menuTitle
                        )
                    }
            )
        } else {
            rows.append(
                contentsOf: DictationModel.allCases
                    .filter { $0 != state.selectedModel }
                    .map {
                        UserGuideRow(
                            key: "model",
                            title: DictationModelPresentation.chipTitle(for: $0),
                            detail: modelDescription($0)
                        )
                    }
            )
        }
        rows.append(
            contentsOf: RecognitionEngine.allCases
                .filter { $0 != state.selectedEngine }
                .map {
                    let availability = state.availableEngines.contains($0)
                        ? ""
                        : " Required local files are not installed."
                    return UserGuideRow(
                        key: "engine",
                        title: $0.displayName,
                        detail: $0.menuTitle + availability
                    )
                }
        )
        if state.selectedEngine.usesWhisperDecoding {
            rows.append(
                contentsOf: DecodingProfile.allCases
                    .filter { $0 != state.decodingProfile }
                    .map {
                        UserGuideRow(
                            key: "decoding",
                            title: $0.displayName,
                            detail: $0.description
                        )
                    }
            )
        }
        rows.append(
            contentsOf: ModelProcessingMode.allCases
                .filter { $0 != state.processingMode }
                .map {
                    UserGuideRow(
                        key: "processing",
                        title: $0.displayName,
                        detail: $0.description
                    )
                }
        )
        rows.append(
            UserGuideRow(
                key: "limits",
                title: "Other recording limits",
                detail: otherLimits
            )
        )
        rows.append(
            UserGuideRow(
                key: "themes",
                title: "Other themes",
                detail: otherThemes
                    .filter { $0.identifier != selectedThemeID }
                    .map { $0.name }
                    .joined(separator: ", ")
            )
        )
        rows.append(
            UserGuideRow(
                key: "startup",
                title: loginItemEnabled ? "Manual Start" : "Open at Login",
                detail: loginItemEnabled
                    ? "Disable automatic launch and start the app yourself."
                    : "Start whisper_hotkey automatically after sign-in."
            )
        )
        rows.append(
            UserGuideRow(
                key: "last-dictation",
                title: state.keepsLatestDictation
                    ? "Disable Copy Last Dictation"
                    : "Enable Copy Last Dictation",
                detail: state.keepsLatestDictation
                    ? "Clear the retained transcript and stop keeping later dictations."
                    : "Keep only the next latest successful transcript in memory until quit."
            )
        )
        return rows
    }

    private static func activePathDetail(
        for state: AdvancedSettingsState
    ) -> String {
        let model = engineModelName(for: state)
        switch state.activationMode {
        case .hold:
            return "Hold \(state.selectedHotkey.displayName) to listen, then release to transcribe and insert with \(model)."
        case .toggle:
            return "Tap \(state.selectedHotkey.displayName) to listen, then tap again to transcribe and insert with \(model)."
        case .pause:
            return "Tap \(state.selectedHotkey.displayName) to listen. Natural pauses insert \(model) phrases while recording continues."
        }
    }

    /// Names the checkpoint actually running: the whisper model chip for
    /// whisper.cpp and WhisperKit, or the Parakeet variant when Parakeet is
    /// selected, since Parakeet does not run a whisper model at all.
    private static func engineModelName(
        for state: AdvancedSettingsState
    ) -> String {
        state.selectedEngine == .parakeetCoreML
            ? state.selectedParakeetVariant.displayName
            : DictationModelPresentation.chipTitle(for: state.selectedModel)
    }

    private static func engineModelDescription(
        for state: AdvancedSettingsState
    ) -> String {
        state.selectedEngine == .parakeetCoreML
            ? state.selectedParakeetVariant.menuTitle
            : modelDescription(state.selectedModel)
    }

    private static func activationDescription(
        _ mode: HotkeyActivationMode
    ) -> String {
        switch mode {
        case .hold:
            "Hold the dictation key to listen. Release to insert."
        case .toggle:
            "Tap once to start and once more to finish and insert."
        case .pause:
            "Natural pauses insert phrases while recording continues."
        }
    }

    private static func modelDescription(_ model: DictationModel) -> String {
        switch model {
        case .baseEnglish:
            "Fastest and smallest: 141 MB."
        case .smallEnglish:
            "More accurate with moderate cost: 465 MB."
        case .mediumEnglish:
            "High accuracy with the largest memory cost: 1.5 GB."
        case .largeV3TurboQ5:
            "Best speed and accuracy balance: 547 MB."
        }
    }

    private static func dictionaryTitle(_ entries: [String]) -> String {
        entries.isEmpty
            ? "No custom terms"
            : "\(entries.count) custom \(entries.count == 1 ? "term" : "terms")"
    }

    private static func dictionaryDetail(_ entries: [String]) -> String {
        entries.isEmpty
            ? "Add names and technical phrases in Settings to bias spelling."
            : entries.joined(separator: ", ")
    }
}

@MainActor
final class UserGuidePopoverController {
    typealias StateProvider = () -> AdvancedSettingsState
    typealias LoginItemEnabledProvider = () -> Bool

    private let stateProvider: StateProvider
    private let loginItemEnabledProvider: LoginItemEnabledProvider
    private let popover = NSPopover()
    private var selectedTheme = BadgeThemeSelection.defaultSelection

    init(
        stateProvider: @escaping StateProvider,
        loginItemEnabledProvider: @escaping LoginItemEnabledProvider = {
            false
        }
    ) {
        self.stateProvider = stateProvider
        self.loginItemEnabledProvider = loginItemEnabledProvider
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 440, height: 540)
    }

    func toggle(relativeTo button: NSButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        let contentController = UserGuideViewController(
            sections: UserGuideContent.sections(
                for: stateProvider(),
                loginItemEnabled: loginItemEnabledProvider()
            ),
            theme: selectedTheme
        )
        contentController.preferredContentSize = NSSize(width: 440, height: 540)
        popover.contentViewController = contentController
        popover.contentSize = contentController.preferredContentSize
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .maxY
        )
    }

    func close() {
        popover.performClose(nil)
    }

    func applyTheme(_ theme: BadgeThemeSelection) {
        selectedTheme = theme
        let appearanceName: NSAppearance.Name =
            theme.mode == .light ? .aqua : .darkAqua
        popover.appearance = NSAppearance(named: appearanceName)
        (popover.contentViewController as? UserGuideViewController)?
            .applyTheme(theme)
    }

    var isShownForTesting: Bool {
        popover.isShown
    }
}

@MainActor
final class UserGuideViewController: NSViewController {
    private let sections: [UserGuideSection]
    private var theme: BadgeThemeSelection
    private var textView: NSTextView!
    private var titleLabel: NSTextField!

    init(
        sections: [UserGuideSection],
        theme: BadgeThemeSelection = .defaultSelection
    ) {
        self.sections = sections
        self.theme = theme
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        let header = NSStackView()
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 4
        header.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "User Guide")
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel = title
        header.addArrangedSubview(title)

        root.addSubview(header)

        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        guard let documentTextView = scrollView.documentView as? NSTextView else {
            preconditionFailure("AppKit did not create a scrollable text view")
        }
        textView = documentTextView
        configureTextView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(
                equalTo: root.leadingAnchor,
                constant: 22
            ),
            scrollView.trailingAnchor.constraint(
                equalTo: root.trailingAnchor,
                constant: -12
            ),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
        ])
        view = root
        applyTheme(theme)
    }

    private func configureTextView() {
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textStorage?.setAttributedString(makeGuideText())
    }

    private func makeGuideText() -> NSAttributedString {
        let palette = BadgeThemePalette.palette(for: theme)
        let secondaryText = palette.primaryText.withAlphaComponent(0.72)
        let result = NSMutableAttributedString()
        let headingStyle = NSMutableParagraphStyle()
        headingStyle.paragraphSpacingBefore = 6
        headingStyle.paragraphSpacing = 8
        let titleStyle = NSMutableParagraphStyle()
        titleStyle.paragraphSpacing = 2
        let detailStyle = NSMutableParagraphStyle()
        detailStyle.paragraphSpacing = 12

        for section in sections {
            result.append(
                NSAttributedString(
                    string: "\(section.title)\n",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                        .foregroundColor: palette.waveform.withAlphaComponent(0.78),
                        .paragraphStyle: headingStyle,
                    ]
                )
            )
            for row in section.rows {
                let title = NSMutableAttributedString(
                    string: "\(row.key.uppercased())  ",
                    attributes: [
                        .font: NSFont.monospacedSystemFont(
                            ofSize: 11,
                            weight: .medium
                        ),
                        .foregroundColor: palette.waveform,
                        .paragraphStyle: titleStyle,
                    ]
                )
                title.append(
                    NSAttributedString(
                        string: "\(row.title)\n",
                        attributes: [
                            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                            .foregroundColor: palette.primaryText,
                            .paragraphStyle: titleStyle,
                        ]
                    )
                )
                result.append(title)
                result.append(
                    NSAttributedString(
                        string: "\(row.detail)\n",
                        attributes: [
                            .font: NSFont.systemFont(ofSize: 12),
                            .foregroundColor: secondaryText,
                            .paragraphStyle: detailStyle,
                        ]
                    )
                )
            }
        }
        return result
    }

    func applyTheme(_ theme: BadgeThemeSelection) {
        self.theme = theme
        loadViewIfNeeded()
        let palette = BadgeThemePalette.palette(for: theme)
        let background = palette.background.withAlphaComponent(1)
        view.layer?.backgroundColor = background.cgColor
        titleLabel.textColor = palette.primaryText
        textView.backgroundColor = background
        textView.textStorage?.setAttributedString(makeGuideText())
    }

    var appliedThemeForTesting: BadgeThemeSelection {
        theme
    }

    var backgroundIsOpaqueForTesting: Bool {
        loadViewIfNeeded()
        return textView.backgroundColor.alphaComponent == 1
            && view.layer?.backgroundColor?.alpha == 1
    }

    var renderedTextForTesting: String {
        loadViewIfNeeded()
        return textView.string
    }

    var renderedTextHasVisibleFrameForTesting: Bool {
        loadViewIfNeeded()
        view.frame = NSRect(origin: .zero, size: preferredContentSize)
        view.layoutSubtreeIfNeeded()
        return textView.frame.width > 0
            && (textView.enclosingScrollView?.frame.width ?? 0) > 0
            && (textView.enclosingScrollView?.frame.height ?? 0) > 0
    }
}
