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
    static func sections(for state: AdvancedSettingsState) -> [UserGuideSection] {
        [
            UserGuideSection(
                title: "DICTATION",
                rows: dictationRows(for: state)
            ),
            UserGuideSection(
                title: "WHILE LISTENING",
                rows: [
                    UserGuideRow(
                        key: "esc",
                        title: "Discard",
                        detail: "Stops dictation and inserts nothing."
                    ),
                    UserGuideRow(
                        key: "return",
                        title: "Insert and send",
                        detail: "Return or keypad Enter transcribes, inserts, then sends once."
                    ),
                    UserGuideRow(
                        key: "■",
                        title: "Stop and insert",
                        detail: "The dark HUD button inserts without sending."
                    ),
                    UserGuideRow(
                        key: "↑",
                        title: "Insert and send",
                        detail: "The light HUD button inserts and presses Return."
                    ),
                    UserGuideRow(
                        key: "drag",
                        title: "Move the HUD",
                        detail: "Drag its waveform or timer to lock it for this session."
                    ),
                    UserGuideRow(
                        key: "focus",
                        title: "Choose the destination",
                        detail: "Text inserts at the current focus and replaces its selection."
                    ),
                ]
            ),
            UserGuideSection(
                title: "BEHAVIOR OPTIONS",
                rows: [
                    UserGuideRow(
                        key: "hold",
                        title: "Press and Hold",
                        detail: "Hold the dictation key to listen. Release to insert."
                    ),
                    UserGuideRow(
                        key: "toggle",
                        title: "Toggle",
                        detail: "Tap once to start and once more to finish and insert."
                    ),
                    UserGuideRow(
                        key: "pause",
                        title: "Pause Mode",
                        detail: "Natural pauses insert phrases while recording continues."
                    ),
                    UserGuideRow(
                        key: "caps",
                        title: "Caps Lock behavior",
                        detail: "Caps Lock supports Toggle and Pause Mode, not Press and Hold."
                    ),
                ]
            ),
            UserGuideSection(
                title: "MODEL OPTIONS",
                rows: [
                    UserGuideRow(
                        key: "base",
                        title: "Base",
                        detail: "Fastest and smallest: 141 MB."
                    ),
                    UserGuideRow(
                        key: "small",
                        title: "Small",
                        detail: "More accurate with moderate cost: 465 MB."
                    ),
                    UserGuideRow(
                        key: "medium",
                        title: "Medium",
                        detail: "High accuracy with the largest memory cost: 1.5 GB."
                    ),
                    UserGuideRow(
                        key: "turbo",
                        title: "Turbo",
                        detail: "Best speed and accuracy balance: 547 MB."
                    ),
                    UserGuideRow(
                        key: "muted",
                        title: "Unavailable models",
                        detail: "A muted chip means its local model file is not installed."
                    ),
                    UserGuideRow(
                        key: "metal",
                        title: "whisper.cpp Metal",
                        detail: "Default path: fast GPU decoding with the smallest app overhead."
                    ),
                    UserGuideRow(
                        key: "core ml",
                        title: "whisper.cpp Core ML Encoder",
                        detail: "Runs the audio encoder on Core ML while whisper.cpp decodes the text."
                    ),
                    UserGuideRow(
                        key: "ane",
                        title: "WhisperKit",
                        detail: "Native Core ML path optimized for Apple GPU and Neural Engine execution."
                    ),
                    UserGuideRow(
                        key: state.selectedEngine.displayName.lowercased(),
                        title: "Selected engine",
                        detail: state.selectedEngine.menuTitle
                    ),
                    UserGuideRow(
                        key: "precision",
                        title: "Precision decoding",
                        detail: DecodingProfile.precision.description
                    ),
                    UserGuideRow(
                        key: "smart",
                        title: "Smart Decode",
                        detail: DecodingProfile.adaptive.description
                    ),
                    UserGuideRow(
                        key: state.decodingProfile.displayName.lowercased(),
                        title: "Selected decoding",
                        detail: state.decodingProfile.description
                    ),
                    UserGuideRow(
                        key: "after recording",
                        title: ModelProcessingMode.afterRecording.displayName,
                        detail: ModelProcessingMode.afterRecording.description
                    ),
                    UserGuideRow(
                        key: "model ready",
                        title: ModelProcessingMode.modelReady.displayName,
                        detail: ModelProcessingMode.modelReady.description
                    ),
                    UserGuideRow(
                        key: "decode while speaking",
                        title:
                            ModelProcessingMode.decodeWhileSpeaking.displayName,
                        detail:
                            ModelProcessingMode.decodeWhileSpeaking.description
                    ),
                    UserGuideRow(
                        key: state.processingMode.rawValue,
                        title: "Selected processing",
                        detail: state.processingMode.description
                    ),
                    UserGuideRow(
                        key: "terms",
                        title: "Internal dictionary",
                        detail: "Add names and technical phrases to bias recognition toward their exact spelling. Use commas or Return to create tokens."
                    ),
                ]
            ),
            UserGuideSection(
                title: "OTHER SETTINGS",
                rows: [
                    UserGuideRow(
                        key: "key",
                        title: "Dictation key",
                        detail: "Chooses the left or right modifier that controls dictation."
                    ),
                    UserGuideRow(
                        key: "limit",
                        title: "Recording limit",
                        detail: "Automatically finishes when the selected duration is reached."
                    ),
                    UserGuideRow(
                        key: "theme",
                        title: "Theme",
                        detail: "Chooses from grouped dark and light color presets for the floating HUD."
                    ),
                    UserGuideRow(
                        key: "login",
                        title: "Open at Login",
                        detail: "Keeps dictation ready after signing in to this Mac."
                    ),
                ]
            ),
            UserGuideSection(
                title: "MENU ACTIONS",
                rows: [
                    UserGuideRow(
                        key: "copy",
                        title: "Copy Last Dictation",
                        detail: "Copies the latest successful transcript normally."
                    ),
                    UserGuideRow(
                        key: "setup",
                        title: "Open Setup",
                        detail: "Checks permissions, model files, helper, and login readiness."
                    ),
                    UserGuideRow(
                        key: "settings",
                        title: "Settings",
                        detail: "Opens the preferences and this User Guide."
                    ),
                    UserGuideRow(
                        key: "cancel",
                        title: "Cancel and Discard",
                        detail: "Aborts the active recording without inserting."
                    ),
                    UserGuideRow(
                        key: "restart",
                        title: "Restart",
                        detail: "Cleanly quits and reopens whisper_hotkey."
                    ),
                    UserGuideRow(
                        key: "quit",
                        title: "Quit",
                        detail: "Stops the agent and releases all active resources."
                    ),
                ]
            ),
            UserGuideSection(
                title: "PRIVACY",
                rows: [
                    UserGuideRow(
                        key: "local",
                        title: "On-device only",
                        detail: "Audio stays local and is deleted after each dictation."
                    ),
                ]
            ),
        ]
    }

    private static func dictationRows(
        for state: AdvancedSettingsState
    ) -> [UserGuideRow] {
        let key = state.selectedHotkey.displayName
        let interaction: UserGuideRow
        switch state.activationMode {
        case .hold:
            interaction = UserGuideRow(
                key: key,
                title: "Hold to dictate",
                detail: "Hold to listen. Release to transcribe and insert."
            )
        case .toggle:
            interaction = UserGuideRow(
                key: key,
                title: "Tap to start or stop",
                detail: "Tap once to listen and again to transcribe and insert."
            )
        case .pause:
            interaction = UserGuideRow(
                key: key,
                title: "Pause Mode",
                detail: "Tap to listen. Natural pauses insert phrases while it stays active."
            )
        }
        return [
            interaction,
            UserGuideRow(
                key: "shortcut",
                title: "Modifier shortcuts pass through",
                detail: "\(key) still works normally when combined with another key or click."
            ),
        ]
    }
}

@MainActor
final class UserGuidePopoverController {
    typealias StateProvider = () -> AdvancedSettingsState

    private let stateProvider: StateProvider
    private let popover = NSPopover()
    private var selectedTheme = BadgeTheme.defaultTheme

    init(stateProvider: @escaping StateProvider) {
        self.stateProvider = stateProvider
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
            sections: UserGuideContent.sections(for: stateProvider()),
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

    func applyTheme(_ theme: BadgeTheme) {
        selectedTheme = theme
        let appearanceName: NSAppearance.Name =
            theme == .lightFrost ? .aqua : .darkAqua
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
    private var theme: BadgeTheme
    private var textView: NSTextView!
    private var titleLabel: NSTextField!
    private var subtitleLabel: NSTextField!

    init(
        sections: [UserGuideSection],
        theme: BadgeTheme = .defaultTheme
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

        let subtitle = NSTextField(
            labelWithString: "Everything you can do while dictating."
        )
        subtitle.textColor = .secondaryLabelColor
        subtitleLabel = subtitle
        header.addArrangedSubview(subtitle)
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

    func applyTheme(_ theme: BadgeTheme) {
        self.theme = theme
        loadViewIfNeeded()
        let palette = BadgeThemePalette.palette(for: theme)
        let background = palette.background.withAlphaComponent(1)
        view.layer?.backgroundColor = background.cgColor
        titleLabel.textColor = palette.primaryText
        subtitleLabel.textColor = palette.primaryText.withAlphaComponent(0.72)
        textView.backgroundColor = background
        textView.textStorage?.setAttributedString(makeGuideText())
    }

    var appliedThemeForTesting: BadgeTheme {
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
