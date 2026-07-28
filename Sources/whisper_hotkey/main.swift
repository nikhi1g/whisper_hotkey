import AppKit
import Darwin
import Foundation
import WhisperHotkeyCore

private enum ExitCode {
    static let success: Int32 = 0
    static let usage: Int32 = 64
    static let unavailable: Int32 = 69
    static let software: Int32 = 70
    static let ioError: Int32 = 74
}

private struct Controller {
    private let socketURL = WhisperHotkeyPaths.controlSocket
    private let installedApplication = URL(
        fileURLWithPath: "/Applications/whisper_hotkey.app",
        isDirectory: true
    )

    func run(arguments: [String]) -> Int32 {
        let command: CLICommand
        do {
            command = try CLICommandParser.parse(arguments)
        } catch {
            writeError(parseErrorMessage(error))
            writeError(usage)
            return ExitCode.usage
        }

        switch command {
        case .help:
            writeOutput(usage)
            return ExitCode.success
        case .start:
            return start()
        case .restart:
            return restart()
        case .logs:
            return showLogs()
        case let .control(command):
            return send(command)
        }
    }

    private func start() -> Int32 {
        if let response = try? SocketControlClient(socketURL: socketURL).send(.status),
           response.ok
        {
            writeOutput("whisper_hotkey is already running.")
            if let status = response.status {
                writeOutput(format(status))
            }
            return ExitCode.success
        }

        guard FileManager.default.fileExists(atPath: installedApplication.path) else {
            writeError("whisper_hotkey is not installed at \(installedApplication.path).")
            return ExitCode.unavailable
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", "-j", installedApplication.path]
        process.standardOutput = FileHandle.nullDevice
        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            writeError("Could not launch whisper_hotkey: \(error.localizedDescription)")
            return ExitCode.unavailable
        }

        guard process.terminationStatus == 0 else {
            let details = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            writeError(details?.isEmpty == false ? details! : "The application could not be opened.")
            return ExitCode.unavailable
        }

        let deadline = Date().addingTimeInterval(3)
        repeat {
            if let response = try? SocketControlClient(
                socketURL: socketURL,
                timeout: 0.25
            ).send(.status), response.ok {
                writeOutput("whisper_hotkey started.")
                if let status = response.status {
                    writeOutput(format(status))
                }
                return ExitCode.success
            }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline

        writeError("whisper_hotkey was opened, but its control socket did not become ready.")
        return ExitCode.unavailable
    }

    private func send(_ command: ControlCommand) -> Int32 {
        do {
            let response = try SocketControlClient(socketURL: socketURL).send(command)
            if command == .status, let status = response.status {
                writeOutput(format(status))
            } else if !response.message.isEmpty {
                (response.ok ? writeOutput : writeError)(response.message)
            }
            return response.ok ? ExitCode.success : ExitCode.software
        } catch let error as SocketClientError {
            if error.isUnavailable {
                writeError("whisper_hotkey is not running.")
                return ExitCode.unavailable
            }
            writeError(error.localizedDescription)
            return ExitCode.ioError
        } catch {
            writeError("Control request failed: \(error.localizedDescription)")
            return ExitCode.ioError
        }
    }

    private func restart() -> Int32 {
        do {
            let response = try SocketControlClient(socketURL: socketURL).send(.stop)
            guard response.ok else {
                if !response.message.isEmpty {
                    writeError(response.message)
                }
                return ExitCode.software
            }
            if !response.message.isEmpty {
                writeOutput(response.message)
            }
        } catch let error as SocketClientError where error.isUnavailable {
            if runningApplications.isEmpty {
                return start()
            }
            writeError("whisper_hotkey is running but its control socket is unavailable.")
            return ExitCode.unavailable
        } catch {
            writeError("Could not stop whisper_hotkey: \(error.localizedDescription)")
            return ExitCode.ioError
        }

        let deadline = Date().addingTimeInterval(5)
        repeat {
            if !controlServerIsReachable, runningApplications.isEmpty {
                return start()
            }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline

        writeError("whisper_hotkey did not finish stopping; restart was not attempted.")
        return ExitCode.unavailable
    }

    private func showLogs() -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "show",
            "--style", "compact",
            "--last", "1h",
            "--predicate", "subsystem == \"\(WhisperHotkeyPaths.bundleIdentifier)\"",
        ]
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? ExitCode.success : ExitCode.ioError
        } catch {
            writeError("Could not query the unified log: \(error.localizedDescription)")
            return ExitCode.ioError
        }
    }

    private func format(_ status: RuntimeStatus) -> String {
        var lines = [
            "Running: \(yesNo(status.running))",
            "Phase: \(status.phase.rawValue)",
            "Microphone: \(permission(status.microphoneGranted))",
            "Accessibility: \(permission(status.accessibilityGranted))",
            "Input Monitoring: \(permission(status.inputMonitoringGranted))",
            "Login Item: \(status.loginItemEnabled ? "enabled" : "disabled")",
            "Model: \(available(status.modelAvailable))",
            "Helper: \(available(status.helperAvailable))",
        ]
        if let hotkey = status.hotkey, !hotkey.isEmpty {
            let mode = status.hotkeyMode.map { " (\($0))" } ?? ""
            lines.append("Hotkey: \(hotkey)\(mode)")
        }
        if let lastError = status.lastError, !lastError.isEmpty {
            lines.append("Last error: \(lastError)")
        }
        return lines.joined(separator: "\n")
    }

    private func yesNo(_ value: Bool) -> String {
        value ? "yes" : "no"
    }

    private func permission(_ granted: Bool) -> String {
        granted ? "granted" : "needed"
    }

    private func available(_ value: Bool) -> String {
        value ? "available" : "missing"
    }

    private var runningApplications: [NSRunningApplication] {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: WhisperHotkeyPaths.bundleIdentifier
        )
    }

    private var controlServerIsReachable: Bool {
        (try? SocketControlClient(socketURL: socketURL, timeout: 0.25).send(.status)) != nil
    }

    private func parseErrorMessage(_ error: Error) -> String {
        switch error {
        case CLIParseError.missingCommand:
            "Missing command."
        case let CLIParseError.unknownCommand(command):
            "Unknown command: \(command)"
        case let CLIParseError.unexpectedArguments(arguments):
            "Unexpected arguments: \(arguments.joined(separator: " "))"
        default:
            "Invalid command."
        }
    }

    private var usage: String {
        """
        Usage: whisper_hotkey <command>

        Commands:
          start           Launch the installed app in the background
          stop            Stop the running agent
          restart         Restart the running agent
          status          Show runtime and setup status
          cancel          Cancel the current dictation
          setup           Open the one-time setup window
          enable-login    Enable the native Login Item
          disable-login   Disable the native Login Item
          logs            Show the last hour of transcript-free app logs
        """
    }
}

private enum SocketClientError: Error, LocalizedError {
    case pathTooLong
    case systemCall(String, Int32)
    case disconnected
    case oversizedResponse
    case malformedResponse

    var isUnavailable: Bool {
        switch self {
        case let .systemCall(operation, code):
            operation == "connect"
                && (code == ENOENT || code == ECONNREFUSED || code == EACCES)
        default:
            false
        }
    }

    var errorDescription: String? {
        switch self {
        case .pathTooLong:
            "The control socket path is too long."
        case let .systemCall(operation, code):
            "\(operation) failed: \(String(cString: strerror(code)))"
        case .disconnected:
            "The agent closed the control connection before responding."
        case .oversizedResponse:
            "The agent returned an oversized control response."
        case .malformedResponse:
            "The agent returned a malformed control response."
        }
    }
}

private struct SocketControlClient {
    let socketURL: URL
    var timeout: TimeInterval = 3

    func send(_ command: ControlCommand) throws -> ControlResponse {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw SocketClientError.systemCall("socket", errno)
        }
        defer {
            Darwin.close(descriptor)
        }

        setNoSigPipe(on: descriptor)
        setTimeout(timeout, on: descriptor)
        var address = try unixAddress(path: socketURL.path)
        let connectionResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(
                    descriptor,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
            }
        }
        guard connectionResult == 0 else {
            throw SocketClientError.systemCall("connect", errno)
        }

        var request = try JSONEncoder().encode(ControlRequest(command: command))
        request.append(0x0A)
        try write(request, to: descriptor)
        let response = try readLine(from: descriptor)

        do {
            return try JSONDecoder().decode(ControlResponse.self, from: response)
        } catch {
            throw SocketClientError.malformedResponse
        }
    }

    private func unixAddress(path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else {
            throw SocketClientError.pathTooLong
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 0)
            buffer.copyBytes(from: bytes)
        }
        return address
    }

    private func write(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }
            var offset = 0
            while offset < rawBuffer.count {
                let count = Darwin.send(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset,
                    0
                )
                if count > 0 {
                    offset += count
                } else if count < 0, errno == EINTR {
                    continue
                } else {
                    throw SocketClientError.systemCall("send", errno)
                }
            }
        }
    }

    private func readLine(from descriptor: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while data.count <= 65_536 {
            let count = Darwin.recv(descriptor, &buffer, buffer.count, 0)
            if count > 0 {
                data.append(contentsOf: buffer.prefix(Int(count)))
                if let newline = data.firstIndex(of: 0x0A) {
                    guard newline <= 65_536 else {
                        throw SocketClientError.oversizedResponse
                    }
                    var line = data[..<newline]
                    if line.last == 0x0D {
                        line = line.dropLast()
                    }
                    guard !line.isEmpty else {
                        throw SocketClientError.malformedResponse
                    }
                    return Data(line)
                }
                guard data.count <= 65_536 else {
                    throw SocketClientError.oversizedResponse
                }
            } else if count == 0 {
                throw SocketClientError.disconnected
            } else if errno != EINTR {
                throw SocketClientError.systemCall("recv", errno)
            }
        }
        throw SocketClientError.oversizedResponse
    }

    private func setNoSigPipe(on descriptor: Int32) {
        var enabled: Int32 = 1
        withUnsafePointer(to: &enabled) {
            _ = Darwin.setsockopt(
                descriptor,
                SOL_SOCKET,
                SO_NOSIGPIPE,
                $0,
                socklen_t(MemoryLayout<Int32>.size)
            )
        }
    }

    private func setTimeout(_ timeout: TimeInterval, on descriptor: Int32) {
        let bounded = max(0, timeout)
        let seconds = Int(bounded)
        var value = timeval(
            tv_sec: seconds,
            tv_usec: Int32((bounded - Double(seconds)) * 1_000_000)
        )
        withUnsafePointer(to: &value) {
            _ = Darwin.setsockopt(
                descriptor,
                SOL_SOCKET,
                SO_RCVTIMEO,
                $0,
                socklen_t(MemoryLayout<timeval>.size)
            )
            _ = Darwin.setsockopt(
                descriptor,
                SOL_SOCKET,
                SO_SNDTIMEO,
                $0,
                socklen_t(MemoryLayout<timeval>.size)
            )
        }
    }
}

private func writeOutput(_ message: String) {
    FileHandle.standardOutput.write(Data((message + "\n").utf8))
}

private func writeError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

let exitCode = Controller().run(arguments: Array(CommandLine.arguments.dropFirst()))
Darwin.exit(exitCode)
