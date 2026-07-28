import AppKit
import Darwin
import Dispatch
import Foundation

private let mainApplicationBundleIdentifier = "local.whisperhotkey.app"
private let launchTimeout: DispatchTimeInterval = .seconds(10)

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

guard let launcherURL = executableURL() else {
    fail("could not resolve its executable")
}
guard let applicationURL = containingApplicationURL(for: launcherURL) else {
    fail("could not resolve its signed containing application")
}

private let completion = DispatchSemaphore(value: 0)
private let result = LaunchResult()
private let configuration = NSWorkspace.OpenConfiguration()
configuration.activates = false
NSWorkspace.shared.openApplication(
    at: applicationURL,
    configuration: configuration
) { application, error in
    result.record(application: application, error: error)
    completion.signal()
}

guard completion.wait(timeout: .now() + launchTimeout) == .success,
      result.succeeded
else {
    fail("LaunchServices did not open the application")
}
exit(EXIT_SUCCESS)
