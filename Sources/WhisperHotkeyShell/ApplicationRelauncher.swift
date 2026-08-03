import Foundation
import WhisperHotkeyCore

public enum ApplicationRelaunchError: Error, Equatable {
    case missingBundledLauncher
    case invalidProcessIdentifier
    case invalidPreparedUpdate
}

@MainActor
public struct ApplicationRelauncher {
    typealias Launch = (URL, [String]) throws -> Void

    private let launcherURL: URL?
    private let processIdentifier: Int32
    private let launch: Launch

    public init(
        bundle: Bundle = .main,
        processIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier
    ) {
        launcherURL = bundle.url(
            forAuxiliaryExecutable: "WhisperHotkeyLoginLauncher"
        )
        self.processIdentifier = processIdentifier
        launch = Self.launch
    }

    init(
        launcherURL: URL?,
        processIdentifier: Int32,
        launch: @escaping Launch
    ) {
        self.launcherURL = launcherURL
        self.processIdentifier = processIdentifier
        self.launch = launch
    }

    public func schedule() throws {
        guard let launcherURL else {
            throw ApplicationRelaunchError.missingBundledLauncher
        }
        guard processIdentifier > 0 else {
            throw ApplicationRelaunchError.invalidProcessIdentifier
        }
        try launch(
            launcherURL,
            ["--wait-for-pid", String(processIdentifier)]
        )
    }

    public func scheduleUpdate(
        _ update: PreparedSoftwareUpdate,
        version: String
    ) throws {
        guard let launcherURL else {
            throw ApplicationRelaunchError.missingBundledLauncher
        }
        guard processIdentifier > 0 else {
            throw ApplicationRelaunchError.invalidProcessIdentifier
        }
        guard update.applicationURL.pathExtension == "app",
              update.applicationURL.deletingLastPathComponent()
                .standardizedFileURL
                == update.cleanupDirectoryURL.standardizedFileURL,
              SemanticVersion(version) != nil
        else {
            throw ApplicationRelaunchError.invalidPreparedUpdate
        }
        try launch(
            launcherURL,
            [
                "--install-update", update.applicationURL.path,
                "--cleanup-directory", update.cleanupDirectoryURL.path,
                "--version", version,
                "--wait-for-pid", String(processIdentifier),
            ]
        )
    }

    private static func launch(
        _ executableURL: URL,
        arguments: [String]
    ) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}
