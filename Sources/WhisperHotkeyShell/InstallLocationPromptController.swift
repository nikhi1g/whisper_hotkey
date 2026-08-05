import AppKit
import Foundation
import WhisperHotkeyCore

public enum InstallLocationMoveError: Error, Equatable {
    case copyFailed(String)
    case launchFailed(String)
}

/// Offers, on first run only, to install the download into `/Applications`.
///
/// The ZIP download replaces the disk image that macOS 15 blocks before it
/// mounts, so there is no Finder window with an Applications alias to drag
/// into. This restores the same outcome from inside the app.
@MainActor
public struct InstallLocationPromptController {
    private let bundleURL: URL
    private let location: ApplicationInstallLocation
    private let fileManager: FileManager

    public init(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) {
        bundleURL = bundle.bundleURL
        location = ApplicationInstallLocator.locate(bundleURL: bundleURL)
        self.fileManager = fileManager
    }

    public var shouldOffer: Bool {
        location.needsInstallOffer
    }

    /// Returns `true` when the app has been relaunched from `/Applications`
    /// and the caller should stop configuring this instance.
    @discardableResult
    public func runIfNeeded() -> Bool {
        guard shouldOffer else {
            return false
        }
        let destination = ApplicationInstallLocator.destinationURL(
            for: bundleURL
        )
        guard presentOffer(destination: destination) else {
            return false
        }
        do {
            try install(to: destination)
            try launch(destination)
            NSApp.terminate(nil)
            return true
        } catch {
            presentFailure(error, destination: destination)
            return false
        }
    }

    private func presentOffer(destination: URL) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Move whisper_hotkey to Applications?"
        if fileManager.fileExists(atPath: destination.path) {
            alert.informativeText = """
                whisper_hotkey is running from outside your Applications \
                folder. Moving it there replaces the existing copy, keeps \
                future updates working, and stops macOS from asking about it \
                again.
                """
        } else {
            alert.informativeText = """
                whisper_hotkey is running from outside your Applications \
                folder. Moving it there keeps updates working and stops macOS \
                from asking about it again.
                """
        }
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func install(to destination: URL) throws {
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            // A translocated bundle is readable, so the running copy is always
            // a valid source even though it cannot be moved.
            try fileManager.copyItem(at: bundleURL, to: destination)
        } catch {
            throw InstallLocationMoveError.copyFailed(
                error.localizedDescription
            )
        }
        clearQuarantine(at: destination)
    }

    /// The user already cleared Gatekeeper for this exact build to reach this
    /// prompt, so the installed copy inherits that decision instead of
    /// demanding a second Open Anyway approval.
    private func clearQuarantine(at destination: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = [
            "-d", "-r", "com.apple.quarantine", destination.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    /// Starts the installed copy's own bundled launcher, which waits for this
    /// process to exit before opening its containing bundle. Launching the new
    /// copy directly would race this one for the control socket, and the loser
    /// starts with no runtime at all.
    private func launch(_ destination: URL) throws {
        let launcher = destination
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("WhisperHotkeyLoginLauncher")
        guard fileManager.isExecutableFile(atPath: launcher.path) else {
            throw InstallLocationMoveError.launchFailed(
                "The installed copy has no bundled launcher."
            )
        }
        let process = Process()
        process.executableURL = launcher
        process.arguments = [
            "--wait-for-pid",
            String(ProcessInfo.processInfo.processIdentifier),
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw InstallLocationMoveError.launchFailed(
                error.localizedDescription
            )
        }
    }

    private func presentFailure(_ error: Error, destination: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "whisper_hotkey could not be moved."
        alert.informativeText = """
            Drag whisper_hotkey into your Applications folder manually, then \
            open it from there.

            \(error.localizedDescription)
            """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
