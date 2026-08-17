import Foundation

public enum DictationPhase: String, Codable, CaseIterable, Sendable {
    case idle
    case preparing
    case listening
    case transcribing
    case reviewing
    case inserting
    case cancelled
    case failed

    public var isBusy: Bool {
        switch self {
        case .preparing, .listening, .transcribing, .reviewing, .inserting:
            true
        case .idle, .cancelled, .failed:
            false
        }
    }
}

public enum HotkeyAction: Equatable, Sendable {
    /// Starts private provisional capture on the physical key-down edge. The
    /// recording is adopted only if the gesture is later accepted.
    case primeCapture
    /// Discards provisional audio when a gesture becomes a shortcut, pointer
    /// chord, or rejected quick tap.
    case cancelPrimedCapture
    case pressed
    case released
    case stopAndInsert
    case insertAndSubmit
    case cancel
}

public enum BadgePresentation: Equatable, Sendable {
    case listening
    case transcribing
    case busy
    case error(String)
    case hidden
}

public struct RuntimeStatus: Codable, Equatable, Sendable {
    public var running: Bool
    public var phase: DictationPhase
    public var microphoneGranted: Bool
    public var accessibilityGranted: Bool
    public var inputMonitoringGranted: Bool
    public var loginItemEnabled: Bool
    public var helperAvailable: Bool
    public var modelAvailable: Bool
    public var hotkey: String?
    public var hotkeyMode: String?
    public var model: String?
    public var recordingLimit: String?
    public var threadCount: Int?
    public var lastError: String?

    public init(
        running: Bool,
        phase: DictationPhase,
        microphoneGranted: Bool,
        accessibilityGranted: Bool,
        inputMonitoringGranted: Bool,
        loginItemEnabled: Bool,
        helperAvailable: Bool,
        modelAvailable: Bool,
        hotkey: String? = nil,
        hotkeyMode: String? = nil,
        model: String? = nil,
        recordingLimit: String? = nil,
        threadCount: Int? = nil,
        lastError: String? = nil
    ) {
        self.running = running
        self.phase = phase
        self.microphoneGranted = microphoneGranted
        self.accessibilityGranted = accessibilityGranted
        self.inputMonitoringGranted = inputMonitoringGranted
        self.loginItemEnabled = loginItemEnabled
        self.helperAvailable = helperAvailable
        self.modelAvailable = modelAvailable
        self.hotkey = hotkey
        self.hotkeyMode = hotkeyMode
        self.model = model
        self.recordingLimit = recordingLimit
        self.threadCount = threadCount
        self.lastError = lastError
    }

    /// Input Monitoring is required, matching `SetupReadiness.isReady`. A tap
    /// holding only the Accessibility grant receives `flagsChanged` but not
    /// `keyDown`, so without this the dictation modifier works while Return
    /// and Escape silently do nothing.
    public var setupIsVerified: Bool {
        running
            && microphoneGranted
            && accessibilityGranted
            && inputMonitoringGranted
            && loginItemEnabled
            && helperAvailable
            && modelAvailable
    }
}

public enum ControlCommand: String, Codable, CaseIterable, Sendable {
    case stop
    case restart
    case status
    case cancel
    case setup
    case enableLogin = "enable-login"
    case disableLogin = "disable-login"
}

public struct ControlRequest: Codable, Equatable, Sendable {
    public let command: ControlCommand

    public init(command: ControlCommand) {
        self.command = command
    }
}

public struct ControlResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let message: String
    public let status: RuntimeStatus?

    public init(ok: Bool, message: String, status: RuntimeStatus? = nil) {
        self.ok = ok
        self.message = message
        self.status = status
    }
}

public enum WhisperHotkeyPaths {
    public static let bundleIdentifier = "local.whisperhotkey.app"
    public static let appName = "whisper_hotkey"
    public static let whisperCLIPath = "/opt/homebrew/bin/whisper-cli"

    public static func modelURL(
        for model: DictationModel,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent(".cache/whisper", isDirectory: true)
            .appendingPathComponent(model.fileName)
            .standardizedFileURL
    }

    /// Where FluidAudio caches a Parakeet checkpoint. This is reported for
    /// display and diagnostics only: FluidAudio owns the directory and creates
    /// it on first download, so nothing here should treat it as a precondition.
    public static func parakeetModelURL(
        for variant: ParakeetVariant,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent(
                "Library/Application Support/FluidAudio/Models",
                isDirectory: true
            )
            .appendingPathComponent(variant.cacheFolderName, isDirectory: true)
            .standardizedFileURL
    }

    public static var modelPath: String {
        modelURL(for: DictationModel.selected()).path
    }

    public static var applicationSupportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/whisper_hotkey", isDirectory: true)
    }

    public static var controlSocket: URL {
        applicationSupportDirectory.appendingPathComponent("control.sock")
    }
}
