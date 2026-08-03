import AppKit
import Darwin
import Dispatch
import Foundation

private let mainApplicationBundleIdentifier = "local.whisperhotkey.app"
private let launchTimeout: DispatchTimeInterval = .seconds(10)
private let processExitTimeout: TimeInterval = 30
private let processPollIntervalMicroseconds: useconds_t = 50_000

private enum LauncherError: Error {
    case commandFailed
}

private func fail(_ message: String) -> Never {
    let line = "whisper_hotkey login launcher: \(message)\n"
    FileHandle.standardError.write(Data(line.utf8))
    exit(EXIT_FAILURE)
}

private final class LaunchResult: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func record(application: NSRunningApplication?, error: Error?) {
        lock.lock()
        value = application != nil && error == nil
        lock.unlock()
    }

    var succeeded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private func executableURL() -> URL? {
    var size: UInt32 = 0
    _ = _NSGetExecutablePath(nil, &size)
    guard size > 0 else {
        return nil
    }

    var buffer = [CChar](repeating: 0, count: Int(size))
    let result = buffer.withUnsafeMutableBufferPointer {
        _NSGetExecutablePath($0.baseAddress, &size)
    }
    guard result == 0 else {
        return nil
    }
    let pathBytes = buffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:))
    let path = String(decoding: pathBytes, as: UTF8.self)
    return URL(fileURLWithPath: path)
        .resolvingSymlinksInPath()
}

private func containingApplicationURL(for executableURL: URL) -> URL? {
    let macOSDirectory = executableURL.deletingLastPathComponent()
    guard macOSDirectory.lastPathComponent == "MacOS" else {
        return nil
    }

    let contentsDirectory = macOSDirectory.deletingLastPathComponent()
    guard contentsDirectory.lastPathComponent == "Contents" else {
        return nil
    }

    let applicationURL = contentsDirectory.deletingLastPathComponent()
    // This executable embeds its own Info.plist for code-signing identity, so
    // read the outer app metadata directly instead of consulting Bundle caches.
    let infoURL = contentsDirectory.appendingPathComponent("Info.plist")
    guard let infoData = try? Data(contentsOf: infoURL),
          let propertyList = try? PropertyListSerialization.propertyList(
              from: infoData,
              options: [],
              format: nil
          ),
          let info = propertyList as? [String: Any]
    else {
        return nil
    }
    guard applicationURL.pathExtension == "app",
          info["CFBundleIdentifier"] as? String
            == mainApplicationBundleIdentifier
    else {
        return nil
    }
    return applicationURL
}

private func waitForProcessToExit(_ processIdentifier: pid_t?) {
    guard let processIdentifier else {
        return
    }
    guard processIdentifier > 0,
          processIdentifier != getpid()
    else {
        fail("invalid relaunch arguments")
    }

    let deadline = Date().addingTimeInterval(processExitTimeout)
    while Date() < deadline {
        errno = 0
        if kill(processIdentifier, 0) == -1 {
            if errno == ESRCH {
                return
            }
            if errno != EINTR {
                fail("could not observe the exiting application")
            }
        }
        usleep(processPollIntervalMicroseconds)
    }
    fail("timed out waiting for the application to exit")
}

private struct UpdateRequest {
    let applicationURL: URL
    let cleanupDirectoryURL: URL
    let version: String
}

private struct LaunchRequest {
    let processIdentifier: pid_t?
    let update: UpdateRequest?
}

private func parseRequest(_ arguments: ArraySlice<String>) -> LaunchRequest? {
    if arguments.isEmpty {
        return LaunchRequest(processIdentifier: nil, update: nil)
    }
    if arguments.count == 2,
       arguments.first == "--wait-for-pid",
       let rawPID = arguments.last,
       let processIdentifier = pid_t(rawPID)
    {
        return LaunchRequest(
            processIdentifier: processIdentifier,
            update: nil
        )
    }
    let values = Array(arguments)
    guard values.count == 8,
          values[0] == "--install-update",
          values[2] == "--cleanup-directory",
          values[4] == "--version",
          values[6] == "--wait-for-pid",
          let processIdentifier = pid_t(values[7])
    else {
        return nil
    }
    return LaunchRequest(
        processIdentifier: processIdentifier,
        update: UpdateRequest(
            applicationURL: URL(fileURLWithPath: values[1], isDirectory: true),
            cleanupDirectoryURL: URL(
                fileURLWithPath: values[3],
                isDirectory: true
            ),
            version: values[5]
        )
    )
}

private func run(_ executable: String, arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationReason == .exit,
          process.terminationStatus == 0
    else {
        throw LauncherError.commandFailed
    }
}

private func verifyApplication(_ applicationURL: URL, version: String) throws {
    let infoURL = applicationURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("Info.plist")
    let infoData = try Data(contentsOf: infoURL)
    let propertyList = try PropertyListSerialization.propertyList(
        from: infoData,
        options: [],
        format: nil
    )
    guard applicationURL.pathExtension == "app",
          let info = propertyList as? [String: Any],
          info["CFBundleIdentifier"] as? String
            == mainApplicationBundleIdentifier,
          info["CFBundleShortVersionString"] as? String == version
    else {
        throw CocoaError(.fileReadCorruptFile)
    }
    try run(
        "/usr/bin/codesign",
        arguments: ["--verify", "--deep", "--strict", applicationURL.path]
    )
}

private func installUpdate(
    _ request: UpdateRequest,
    replacing applicationURL: URL
) throws {
    let fileManager = FileManager.default
    let source = request.applicationURL.standardizedFileURL
    let cleanup = request.cleanupDirectoryURL.standardizedFileURL
    guard source.deletingLastPathComponent() == cleanup,
          source.pathExtension == "app",
          source.path != applicationURL.standardizedFileURL.path,
          cleanup.path.hasPrefix(
              fileManager.temporaryDirectory.standardizedFileURL.path
          )
    else {
        throw CocoaError(.fileReadInvalidFileName)
    }
    try verifyApplication(source, version: request.version)

    let parent = applicationURL.deletingLastPathComponent()
    let token = UUID().uuidString
    let incoming = parent.appendingPathComponent(
        ".whisper_hotkey-incoming-\(token).app",
        isDirectory: true
    )
    let backup = parent.appendingPathComponent(
        ".whisper_hotkey-backup-\(token).app",
        isDirectory: true
    )
    defer {
        try? fileManager.removeItem(at: incoming)
        try? fileManager.removeItem(at: cleanup)
    }

    try run(
        "/usr/bin/ditto",
        arguments: [source.path, incoming.path]
    )
    try verifyApplication(incoming, version: request.version)
    try fileManager.moveItem(at: applicationURL, to: backup)
    do {
        try fileManager.moveItem(at: incoming, to: applicationURL)
        try verifyApplication(applicationURL, version: request.version)
        try fileManager.removeItem(at: backup)
    } catch {
        try? fileManager.removeItem(at: applicationURL)
        try? fileManager.moveItem(at: backup, to: applicationURL)
        throw error
    }
}

private func launchApplication(at applicationURL: URL) -> Bool {
    let completion = DispatchSemaphore(value: 0)
    let result = LaunchResult()
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    NSWorkspace.shared.openApplication(
        at: applicationURL,
        configuration: configuration
    ) { application, error in
        result.record(application: application, error: error)
        completion.signal()
    }
    return completion.wait(timeout: .now() + launchTimeout) == .success
        && result.succeeded
}

guard let launcherURL = executableURL() else {
    fail("could not resolve its executable")
}
guard let applicationURL = containingApplicationURL(for: launcherURL) else {
    fail("could not resolve its signed containing application")
}
guard let request = parseRequest(CommandLine.arguments.dropFirst()) else {
    fail("invalid relaunch arguments")
}
waitForProcessToExit(request.processIdentifier)
if let update = request.update {
    do {
        try installUpdate(update, replacing: applicationURL)
    } catch {
        _ = launchApplication(at: applicationURL)
        fail("could not install the verified update")
    }
}
guard launchApplication(at: applicationURL) else {
    fail("LaunchServices did not open the application")
}
exit(EXIT_SUCCESS)
