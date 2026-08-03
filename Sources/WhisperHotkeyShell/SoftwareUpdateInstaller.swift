import CryptoKit
import Foundation
import WhisperHotkeyCore

public struct PreparedSoftwareUpdate: Equatable, Sendable {
    public let applicationURL: URL
    public let cleanupDirectoryURL: URL

    public init(applicationURL: URL, cleanupDirectoryURL: URL) {
        self.applicationURL = applicationURL
        self.cleanupDirectoryURL = cleanupDirectoryURL
    }
}

public enum SoftwareUpdateInstallError: Error, Equatable {
    case missingReleaseAssets
    case invalidServerResponse
    case invalidChecksum
    case checksumMismatch
    case invalidDiskImage
    case invalidApplication
    case invalidVersion
    case untrustedApplication
    case commandFailed(String)
}

public protocol SoftwareUpdateInstalling: Sendable {
    func prepare(
        release: SoftwareUpdateRelease,
        installedApplicationURL: URL,
        installedVersion: String
    ) async throws -> PreparedSoftwareUpdate
}

public actor SoftwareUpdateInstaller: SoftwareUpdateInstalling {
    private static let applicationName = "whisper_hotkey.app"
    private static let diskImageName = "whisper_hotkey.dmg"
    private static let bundleIdentifier = "local.whisperhotkey.app"

    private let session: URLSession
    private let fileManager: FileManager

    public init(
        session: URLSession = .shared,
        fileManager: FileManager = .default
    ) {
        self.session = session
        self.fileManager = fileManager
    }

    public func prepare(
        release: SoftwareUpdateRelease,
        installedApplicationURL: URL,
        installedVersion: String
    ) async throws -> PreparedSoftwareUpdate {
        guard let diskImageURL = release.diskImageURL,
              let checksumURL = release.checksumURL
        else {
            throw SoftwareUpdateInstallError.missingReleaseAssets
        }
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "whisper-hotkey-update-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )

        do {
            let expectedDigest = try await downloadChecksum(from: checksumURL)
            let diskImage = root.appendingPathComponent(Self.diskImageName)
            try await download(from: diskImageURL, to: diskImage)
            guard try Self.sha256(of: diskImage) == expectedDigest else {
                throw SoftwareUpdateInstallError.checksumMismatch
            }

            let mountedVolume = try Self.mount(diskImage)
            defer { try? Self.unmount(mountedVolume) }
            let candidate = mountedVolume.appendingPathComponent(
                Self.applicationName,
                isDirectory: true
            )
            try Self.verifyApplication(
                candidate,
                installedApplicationURL: installedApplicationURL,
                installedVersion: installedVersion,
                expectedVersion: release.version
            )

            let prepared = root.appendingPathComponent(
                Self.applicationName,
                isDirectory: true
            )
            try Self.run(
                executable: "/usr/bin/ditto",
                arguments: [candidate.path, prepared.path]
            )
            try Self.verifyApplication(
                prepared,
                installedApplicationURL: installedApplicationURL,
                installedVersion: installedVersion,
                expectedVersion: release.version
            )
            try? fileManager.removeItem(at: diskImage)
            return PreparedSoftwareUpdate(
                applicationURL: prepared,
                cleanupDirectoryURL: root
            )
        } catch {
            try? fileManager.removeItem(at: root)
            throw error
        }
    }

    private func downloadChecksum(from url: URL) async throws -> String {
        let (data, response) = try await session.data(from: url)
        try Self.validate(response)
        guard data.count <= 1_024,
              let text = String(data: data, encoding: .utf8),
              let digest = Self.expectedDigest(from: text)
        else {
            throw SoftwareUpdateInstallError.invalidChecksum
        }
        return digest
    }

    private func download(from url: URL, to destination: URL) async throws {
        let (temporaryURL, response) = try await session.download(from: url)
        try Self.validate(response)
        try fileManager.moveItem(at: temporaryURL, to: destination)
    }

    private static func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode)
        else {
            throw SoftwareUpdateInstallError.invalidServerResponse
        }
    }

    static func expectedDigest(from text: String) -> String? {
        let parts = text.split(whereSeparator: \Character.isWhitespace)
        guard parts.count == 2,
              parts[1] == Substring(Self.diskImageName)
        else {
            return nil
        }
        let digest = parts[0].lowercased()
        guard digest.count == 64,
              digest.allSatisfy({ $0.isHexDigit })
        else {
            return nil
        }
        return digest
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576),
              !chunk.isEmpty
        {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map {
            String(format: "%02x", $0)
        }.joined()
    }

    private static func mount(_ diskImage: URL) throws -> URL {
        let result = try run(
            executable: "/usr/bin/hdiutil",
            arguments: [
                "attach", "-nobrowse", "-readonly", "-plist",
                diskImage.path,
            ],
            capturesOutput: true
        )
        guard let propertyList = try? PropertyListSerialization.propertyList(
                from: result.standardOutput,
                options: [],
                format: nil
              ),
              let root = propertyList as? [String: Any],
              let entities = root["system-entities"] as? [[String: Any]],
              let path = entities.compactMap({
                  $0["mount-point"] as? String
              }).last
        else {
            throw SoftwareUpdateInstallError.invalidDiskImage
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static func unmount(_ volume: URL) throws {
        try run(
            executable: "/usr/bin/hdiutil",
            arguments: ["detach", volume.path]
        )
    }

    private static func verifyApplication(
        _ candidate: URL,
        installedApplicationURL: URL,
        installedVersion: String,
        expectedVersion: String
    ) throws {
        guard candidate.pathExtension == "app",
              let bundle = Bundle(url: candidate),
              bundle.bundleIdentifier == bundleIdentifier,
              let candidateVersion = bundle.object(
                  forInfoDictionaryKey: "CFBundleShortVersionString"
              ) as? String,
              candidateVersion == expectedVersion,
              let installed = SemanticVersion(installedVersion),
              let incoming = SemanticVersion(candidateVersion),
              installed < incoming
        else {
            throw SoftwareUpdateInstallError.invalidVersion
        }
        do {
            try run(
                executable: "/usr/bin/codesign",
                arguments: [
                    "--verify", "--deep", "--strict", candidate.path,
                ]
            )
        } catch {
            throw SoftwareUpdateInstallError.invalidApplication
        }

        let installedRequirement = try designatedRequirement(
            of: installedApplicationURL
        )
        let candidateRequirement = try designatedRequirement(of: candidate)
        if installedRequirement == candidateRequirement {
            return
        }
        do {
            try run(
                executable: "/usr/sbin/spctl",
                arguments: [
                    "--assess", "--type", "execute", candidate.path,
                ]
            )
        } catch {
            throw SoftwareUpdateInstallError.untrustedApplication
        }
    }

    private static func designatedRequirement(of application: URL) throws
        -> String
    {
        let result = try run(
            executable: "/usr/bin/codesign",
            arguments: ["--display", "--requirements", "-", application.path],
            capturesOutput: true
        )
        guard let requirement = designatedRequirement(
            standardOutput: result.standardOutput,
            standardError: result.standardError
        ) else {
            throw SoftwareUpdateInstallError.untrustedApplication
        }
        return requirement
    }

    static func designatedRequirement(
        standardOutput: Data,
        standardError: Data
    ) -> String? {
        let text = [standardOutput, standardError]
            .compactMap { String(data: $0, encoding: .utf8) }
            .joined(separator: "\n")
        guard let line = text.split(separator: "\n").first(where: {
            $0.hasPrefix("designated => ")
        }) else {
            return nil
        }
        return String(line.dropFirst("designated => ".count))
    }

    @discardableResult
    private static func run(
        executable: String,
        arguments: [String],
        capturesOutput: Bool = false
    ) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = capturesOutput
            ? standardOutput
            : FileHandle.nullDevice
        process.standardError = capturesOutput
            ? standardError
            : FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw SoftwareUpdateInstallError.commandFailed(executable)
        }
        let result = CommandResult(
            standardOutput: capturesOutput
                ? standardOutput.fileHandleForReading.readDataToEndOfFile()
                : Data(),
            standardError: capturesOutput
                ? standardError.fileHandleForReading.readDataToEndOfFile()
                : Data()
        )
        guard process.terminationReason == .exit,
              process.terminationStatus == 0
        else {
            throw SoftwareUpdateInstallError.commandFailed(executable)
        }
        return result
    }

    private struct CommandResult {
        let standardOutput: Data
        let standardError: Data
    }
}
