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
        popover.contentViewController = UserGuideViewController(
            sections: UserGuideContent.sections(for: stateProvider())
        )
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .maxY
        )
    }

    func close() {
        popover.performClose(nil)
    }

    var isShownForTesting: Bool {
        popover.isShown
    }
}

@MainActor
private final class UserGuideViewController: NSViewController {
    private let sections: [UserGuideSection]

    init(sections: [UserGuideSection]) {
        self.sections = sections
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let root = NSView()
        let header = NSStackView()
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 4
        header.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "User Guide")
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        header.addArrangedSubview(title)

        let subtitle = NSTextField(
            labelWithString: "Everything you can do while dictating."
        )
        subtitle.textColor = .secondaryLabelColor
        header.addArrangedSubview(subtitle)
        root.addSubview(header)

        let document = NSStackView()
        document.orientation = .vertical
        document.alignment = .leading
        document.spacing = 18
        document.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 12, right: 0)
        document.translatesAutoresizingMaskIntoConstraints = false

        for section in sections {
            document.addArrangedSubview(makeSection(section))
        }

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = document
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
            document.widthAnchor.constraint(
                equalTo: scrollView.contentView.widthAnchor,
                constant: -10
            ),
        ])
        view = root
    }

    private func makeSection(_ section: UserGuideSection) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10

        let heading = NSTextField(labelWithString: section.title)
        heading.font = .systemFont(ofSize: 10, weight: .semibold)
        heading.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(heading)

        for row in section.rows {
            let rowView = makeRow(row)
            stack.addArrangedSubview(rowView)
            rowView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    private func makeRow(_ row: UserGuideRow) -> NSView {
        let key = NSTextField(labelWithString: row.key)
        key.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        key.alignment = .center
        key.textColor = .secondaryLabelColor
        key.wantsLayer = true
        key.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        key.layer?.cornerRadius = 6
        key.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: row.title)
        title.font = .systemFont(ofSize: 13, weight: .medium)

        let detail = NSTextField(wrappingLabelWithString: row.detail)
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 2

        let copy = NSStackView(views: [title, detail])
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 2

        let rowStack = NSStackView(views: [key, copy])
        rowStack.orientation = .horizontal
        rowStack.alignment = .top
        rowStack.spacing = 12

        NSLayoutConstraint.activate([
            key.widthAnchor.constraint(equalToConstant: 82),
            key.heightAnchor.constraint(equalToConstant: 24),
        ])
        return rowStack
    }
}
