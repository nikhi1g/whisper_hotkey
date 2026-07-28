import AppKit

public struct SetupReadiness: Equatable, Sendable {
    public var microphoneGranted: Bool
    public var accessibilityGranted: Bool
    public var inputMonitoringGranted: Bool
    public var modelAvailable: Bool
    public var helperAvailable: Bool

    public init(
        microphoneGranted: Bool,
        accessibilityGranted: Bool,
        inputMonitoringGranted: Bool,
        modelAvailable: Bool,
        helperAvailable: Bool
    ) {
        self.microphoneGranted = microphoneGranted
        self.accessibilityGranted = accessibilityGranted
        self.inputMonitoringGranted = inputMonitoringGranted
        self.modelAvailable = modelAvailable
        self.helperAvailable = helperAvailable
    }

    public var isReady: Bool {
        microphoneGranted
            && accessibilityGranted
            && inputMonitoringGranted
            && modelAvailable
            && helperAvailable
    }
}

@MainActor
public struct SetupActions {
    public var requestMicrophone: () -> Void
    public var openAccessibilitySettings: () -> Void
    public var openInputMonitoringSettings: () -> Void
    public var revealModelLocation: () -> Void
    public var revealHelperLocation: () -> Void

    public init(
        requestMicrophone: @escaping () -> Void,
        openAccessibilitySettings: @escaping () -> Void,
        openInputMonitoringSettings: @escaping () -> Void,
        revealModelLocation: @escaping () -> Void,
        revealHelperLocation: @escaping () -> Void
    ) {
        self.requestMicrophone = requestMicrophone
        self.openAccessibilitySettings = openAccessibilitySettings
        self.openInputMonitoringSettings = openInputMonitoringSettings
        self.revealModelLocation = revealModelLocation
        self.revealHelperLocation = revealHelperLocation
    }
}

@MainActor
public protocol SetupCompletionStoring: AnyObject {
    var isComplete: Bool { get set }
}

@MainActor
public final class UserDefaultsSetupCompletionStore: SetupCompletionStoring {
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "setupCompleted"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public var isComplete: Bool {
        get { defaults.bool(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }
}

@MainActor
public final class SetupWindowController: NSWindowController, NSWindowDelegate {
    public typealias ReadinessProvider = () -> SetupReadiness

    private enum Row: Int, CaseIterable {
        case microphone
        case accessibility
        case inputMonitoring
        case model
        case helper
        case loginItem
    }

    private struct RowControls {
        let status: NSTextField
        let button: NSButton
    }

    private let readinessProvider: ReadinessProvider
    private let actions: SetupActions
    private let loginItemManager: LoginItemManager
    private let completionStore: any SetupCompletionStoring
    private var rowControls: [Row: RowControls] = [:]
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private var attemptedAutomaticLoginRegistration = false

    public init(
        readinessProvider: @escaping ReadinessProvider,
        actions: SetupActions,
        loginItemManager: LoginItemManager = LoginItemManager(),
        completionStore: any SetupCompletionStoring = UserDefaultsSetupCompletionStore()
    ) {
        self.readinessProvider = readinessProvider
        self.actions = actions
        self.loginItemManager = loginItemManager
        self.completionStore = completionStore
        super.init(window: nil)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 390),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Set Up whisper_hotkey"
        window.isReleasedWhenClosed = false
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
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Returns whether the setup window was shown. A completed setup remains
    /// one-time unless `force` is used by the `setup` control command.
    @discardableResult
    public func showIfNeeded(force: Bool = false) -> Bool {
        refresh()
        if !force, completionStore.isComplete {
            return false
        }

        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        return true
    }

    public func showSetup() {
        _ = showIfNeeded(force: true)
    }

    public func refresh() {
        let readiness = readinessProvider()
        automaticallyEnableLoginItemIfReady(readiness)
        let loginStatus = loginItemManager.status

        update(
            .microphone,
            ready: readiness.microphoneGranted,
            missingText: "Permission needed",
            actionTitle: "Request"
        )
        update(
            .accessibility,
            ready: readiness.accessibilityGranted,
            missingText: "Permission needed",
            actionTitle: "Open Settings"
        )
        update(
            .inputMonitoring,
            ready: readiness.inputMonitoringGranted,
            missingText: "Permission needed",
            actionTitle: "Open Settings"
        )
        update(
            .model,
            ready: readiness.modelAvailable,
            missingText: "Base English model not found",
            actionTitle: "Show Location"
        )
        update(
            .helper,
            ready: readiness.helperAvailable,
            missingText: "Helper not found",
            actionTitle: "Show Location"
        )
        updateLoginItem(loginStatus)

        if readiness.isReady, loginStatus == .enabled {
            completionStore.isComplete = true
            detailLabel.stringValue = "Ready. Hold Right Command anywhere text can be entered."
            detailLabel.textColor = .secondaryLabelColor
        } else if loginStatus == .requiresApproval {
            detailLabel.stringValue = "Approve whisper_hotkey in Login Items to finish setup."
            detailLabel.textColor = .systemOrange
        } else {
            detailLabel.stringValue = "Complete each item. No audio or transcript leaves this Mac."
            detailLabel.textColor = .secondaryLabelColor
        }
    }

    public func windowWillClose(_ notification: Notification) {
        NSApp.deactivate()
    }

    @objc private func applicationDidBecomeActive() {
        guard window?.isVisible == true else {
            return
        }
        refresh()
    }

    @objc private func performAction(_ sender: NSButton) {
        guard let row = Row(rawValue: sender.tag) else {
            return
        }

        switch row {
        case .microphone:
            actions.requestMicrophone()
        case .accessibility:
            actions.openAccessibilitySettings()
        case .inputMonitoring:
            actions.openInputMonitoringSettings()
        case .model:
            actions.revealModelLocation()
        case .helper:
            actions.revealHelperLocation()
        case .loginItem:
            performLoginItemAction()
        }

        refresh()
    }

    private func performLoginItemAction() {
        do {
            switch loginItemManager.status {
            case .requiresApproval:
                loginItemManager.openLoginItemsSettings()
            case .enabled:
                break
            case .notRegistered, .notFound, .unknown:
                _ = try loginItemManager.register()
            }
        } catch {
            detailLabel.stringValue = "Could not enable the Login Item: \(error.localizedDescription)"
            detailLabel.textColor = .systemRed
        }
    }

    private func automaticallyEnableLoginItemIfReady(_ readiness: SetupReadiness) {
        guard readiness.isReady,
              loginItemManager.status == .notRegistered
                || loginItemManager.status == .notFound,
              !attemptedAutomaticLoginRegistration
        else {
            return
        }

        attemptedAutomaticLoginRegistration = true
        do {
            _ = try loginItemManager.enableAutomaticallyIfReady(true)
        } catch {
            detailLabel.stringValue = "Could not enable the Login Item: \(error.localizedDescription)"
            detailLabel.textColor = .systemRed
        }
    }

    private func update(
        _ row: Row,
        ready: Bool,
        missingText: String,
        actionTitle: String
    ) {
        guard let controls = rowControls[row] else {
            return
        }
        controls.status.stringValue = ready ? "Ready" : missingText
        controls.status.textColor = ready ? .systemGreen : .secondaryLabelColor
        controls.button.title = actionTitle
        controls.button.isHidden = ready
        controls.button.isEnabled = !ready
    }

    private func updateLoginItem(_ status: LoginItemStatus) {
        guard let controls = rowControls[.loginItem] else {
            return
        }

        switch status {
        case .enabled:
            controls.status.stringValue = "Ready"
            controls.status.textColor = .systemGreen
            controls.button.isHidden = true
        case .requiresApproval:
            controls.status.stringValue = "Approval needed"
            controls.status.textColor = .systemOrange
            controls.button.title = "Open Settings"
            controls.button.isHidden = false
        case .notRegistered:
            controls.status.stringValue = "Not enabled"
            controls.status.textColor = .secondaryLabelColor
            controls.button.title = "Enable"
            controls.button.isHidden = false
        case .notFound:
            controls.status.stringValue = "Not enabled"
            controls.status.textColor = .secondaryLabelColor
            controls.button.title = "Enable"
            controls.button.isHidden = false
        case .unknown:
            controls.status.stringValue = "Status unavailable"
            controls.status.textColor = .secondaryLabelColor
            controls.button.title = "Try Again"
            controls.button.isHidden = false
        }
        controls.button.isEnabled = status != .enabled
    }

    private func makeContentView() -> NSView {
        let root = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        let title = NSTextField(labelWithString: "Private, local dictation")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        stack.addArrangedSubview(title)

        let subtitle = NSTextField(
            wrappingLabelWithString: "whisper_hotkey needs these local permissions and files. Its menu-bar icon shows status; it has no Dock icon."
        )
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 2
        stack.addArrangedSubview(subtitle)

        let grid = NSGridView()
        grid.columnSpacing = 12
        grid.rowSpacing = 10
        grid.xPlacement = .fill
        grid.translatesAutoresizingMaskIntoConstraints = false

        let names: [(Row, String)] = [
            (.microphone, "Microphone"),
            (.accessibility, "Accessibility"),
            (.inputMonitoring, "Input Monitoring"),
            (.model, "Base English model"),
            (.helper, "Whisper helper"),
            (.loginItem, "Login Item"),
        ]

        for (row, name) in names {
            let nameLabel = NSTextField(labelWithString: name)
            nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
            let statusLabel = NSTextField(labelWithString: "")
            statusLabel.lineBreakMode = .byTruncatingTail
            let button = NSButton(
                title: "Action",
                target: self,
                action: #selector(performAction(_:))
            )
            button.bezelStyle = .rounded
            button.tag = row.rawValue
            button.controlSize = .small
            grid.addRow(with: [nameLabel, statusLabel, button])
            rowControls[row] = RowControls(status: statusLabel, button: button)
        }

        grid.column(at: 0).width = 135
        grid.column(at: 1).width = 175
        grid.column(at: 2).width = 100
        stack.addArrangedSubview(grid)

        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 2
        stack.addArrangedSubview(detailLabel)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -20),
            subtitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
            detailLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return root
    }
}
