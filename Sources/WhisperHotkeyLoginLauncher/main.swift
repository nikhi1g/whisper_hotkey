import AppKit
import Darwin
import Foundation

private let mainApplicationBundleIdentifier = "local.whisperhotkey.app"

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
    guard applicationURL.pathExtension == "app",
          Bundle(url: applicationURL)?.bundleIdentifier
            == mainApplicationBundleIdentifier
    else {
        return nil
    }
    return applicationURL
}

guard let launcherURL = executableURL(),
      let applicationURL = containingApplicationURL(for: launcherURL)
else {
    exit(EXIT_FAILURE)
}

exit(NSWorkspace.shared.open(applicationURL) ? EXIT_SUCCESS : EXIT_FAILURE)
