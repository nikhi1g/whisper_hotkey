import Foundation

public enum DictationPhase: String, Codable, CaseIterable, Sendable {
    case idle
    case preparing
    case listening
    case transcribing
    case inserting
    case cancelled
    case failed

    public var isBusy: Bool {
        switch self {
        case .preparing, .listening, .transcribing, .inserting:
            true
        case .idle, .cancelled, .failed:
            false
        }
    }
}

public enum HotkeyAction: Equatable, Sendable {
    case pressed
    case released
    case cancel
}

public enum BadgePresentation: Equatable, Sendable {
    case listening
    case transcribing
    case busy
    case error(String)
    case hidden
}

public enum DeliveryDisposition: String, Codable, Equatable, Sendable {
    case inserted
    case clipboardLease
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
    public var clipboardLeaseActive: Bool
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
        clipboardLeaseActive: Bool,
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
        self.clipboardLeaseActive = clipboardLeaseActive
        self.lastError = lastError
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
    public static let modelPath = NSString(
        string: "~/.cache/whisper/ggml-base.en.bin"
    ).expandingTildeInPath
    public static let whisperCLIPath = "/opt/homebrew/bin/whisper-cli"

    public static var applicationSupportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/whisper_hotkey", isDirectory: true)
    }

    public static var controlSocket: URL {
        applicationSupportDirectory.appendingPathComponent("control.sock")
    }
}
