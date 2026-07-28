import Darwin
import Foundation
import WhisperHotkeyCore

public enum ControlTransportError: Error, LocalizedError, Sendable {
    case alreadyRunning(URL)
    case socketPathTooLong(URL)
    case invalidSocketNode(URL)
    case systemCall(String, Int32)
    case disconnected
    case requestTooLarge
    case malformedMessage

    public var errorDescription: String? {
        switch self {
        case let .alreadyRunning(url):
            "A control server is already listening at \(url.path)."
        case let .socketPathTooLong(url):
            "The control socket path is too long: \(url.path)"
        case let .invalidSocketNode(url):
            "Refusing to replace a non-socket item at \(url.path)."
        case let .systemCall(operation, code):
            "\(operation) failed: \(String(cString: strerror(code)))"
        case .disconnected:
            "The control connection closed before a complete response."
        case .requestTooLarge:
            "The control message exceeded the 64 KiB limit."
        case .malformedMessage:
            "The control peer sent malformed JSON."
        }
    }
}

public struct ControlClient: Sendable {
    public let socketURL: URL
    public let timeout: TimeInterval

    public init(
        socketURL: URL = WhisperHotkeyPaths.controlSocket,
        timeout: TimeInterval = 3
    ) {
        self.socketURL = socketURL
        self.timeout = timeout
    }

    public func send(_ command: ControlCommand) throws -> ControlResponse {
        try send(ControlRequest(command: command))
    }

    public func send(_ request: ControlRequest) throws -> ControlResponse {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw ControlTransportError.systemCall("socket", errno)
        }
        defer {
            Darwin.close(descriptor)
        }

        setNoSigPipe(descriptor)
        setTimeout(timeout, on: descriptor)
        var address = try makeUnixAddress(path: socketURL.path)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(
                    descriptor,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
            }
        }
        guard result == 0 else {
            throw ControlTransportError.systemCall("connect", errno)
        }

        var payload = try JSONEncoder().encode(request)
        payload.append(0x0A)
        try writeAll(payload, to: descriptor)
        let responseData = try readLine(from: descriptor)

        do {
            return try JSONDecoder().decode(ControlResponse.self, from: responseData)
        } catch {
            throw ControlTransportError.malformedMessage
        }
    }
}

public final class ControlServer: @unchecked Sendable {
    public typealias Handler = @Sendable (ControlRequest) async -> ControlResponse
    public typealias ResponseFlushedHandler = @Sendable (
        _ request: ControlRequest,
        _ response: ControlResponse
    ) async -> Void

    public let socketURL: URL

    private let handler: Handler
    private let onResponseFlushed: ResponseFlushedHandler?
    private let eventQueue = DispatchQueue(
        label: "local.whisperhotkey.control-server",
        qos: .utility
    )
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let stateLock = NSLock()
    private var listenerDescriptor: Int32 = -1
    private var listenerSource: (any DispatchSourceRead)?
    private var listenerCancellation: DispatchGroup?
    private var clientDescriptors: Set<Int32> = []
    private var running = false

    public init(
        socketURL: URL = WhisperHotkeyPaths.controlSocket,
        onResponseFlushed: ResponseFlushedHandler? = nil,
        handler: @escaping Handler
    ) {
        self.socketURL = socketURL
        self.onResponseFlushed = onResponseFlushed
        self.handler = handler
        eventQueue.setSpecific(key: queueKey, value: 1)
    }

    deinit {
        stop()
    }

    public var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return running
    }

    public func start() throws {
        stateLock.lock()
        guard !running else {
            stateLock.unlock()
            return
        }

        do {
            try prepareParentDirectory()
            try removeStaleSocketIfNeeded()

            let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard descriptor >= 0 else {
                throw ControlTransportError.systemCall("socket", errno)
            }

            do {
                setNoSigPipe(descriptor)
                var address = try makeUnixAddress(path: socketURL.path)
                let bindResult = withUnsafePointer(to: &address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.bind(
                            descriptor,
                            $0,
                            socklen_t(MemoryLayout<sockaddr_un>.size)
                        )
                    }
                }
                guard bindResult == 0 else {
                    throw ControlTransportError.systemCall("bind", errno)
                }

                guard Darwin.chmod(socketURL.path, S_IRUSR | S_IWUSR) == 0 else {
                    throw ControlTransportError.systemCall("chmod", errno)
                }
                guard Darwin.listen(descriptor, SOMAXCONN) == 0 else {
                    throw ControlTransportError.systemCall("listen", errno)
                }
                try setNonblocking(descriptor)
            } catch {
                Darwin.close(descriptor)
                Darwin.unlink(socketURL.path)
                throw error
            }

            let cancellation = DispatchGroup()
            cancellation.enter()
            let socketPath = socketURL.path
            let source = DispatchSource.makeReadSource(
                fileDescriptor: descriptor,
                queue: eventQueue
            )
            source.setEventHandler { [weak self] in
                self?.acceptAvailableConnections(listenerDescriptor: descriptor)
            }
            source.setCancelHandler {
                Darwin.shutdown(descriptor, SHUT_RDWR)
                Darwin.close(descriptor)
                Darwin.unlink(socketPath)
                cancellation.leave()
            }

            listenerDescriptor = descriptor
            listenerSource = source
            listenerCancellation = cancellation
            running = true
            source.activate()
            stateLock.unlock()
        } catch {
            stateLock.unlock()
            throw error
        }
    }

    public func stop() {
        stateLock.lock()
        guard running else {
            stateLock.unlock()
            return
        }

        running = false
        listenerDescriptor = -1
        let source = listenerSource
        let cancellation = listenerCancellation
        listenerSource = nil
        listenerCancellation = nil
        for descriptor in clientDescriptors {
            Darwin.shutdown(descriptor, SHUT_RDWR)
        }
        stateLock.unlock()

        guard let source else {
            Darwin.unlink(socketURL.path)
            return
        }
        source.cancel()
        if DispatchQueue.getSpecific(key: queueKey) == nil {
            cancellation?.wait()
        }
    }

    private func acceptAvailableConnections(listenerDescriptor: Int32) {
        while true {
            let client = Darwin.accept(listenerDescriptor, nil, nil)
            if client < 0 {
                if errno == EINTR {
                    continue
                }
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    return
                }
                return
            }

            guard setBlocking(client) else {
                Darwin.close(client)
                continue
            }

            setNoSigPipe(client)
            stateLock.lock()
            let shouldServe = running && self.listenerDescriptor == listenerDescriptor
            if shouldServe {
                clientDescriptors.insert(client)
            }
            stateLock.unlock()

            guard shouldServe else {
                Darwin.close(client)
                continue
            }

            Task.detached(priority: .utility) { [weak self] in
                guard let self else {
                    Darwin.shutdown(client, SHUT_RDWR)
                    Darwin.close(client)
                    return
                }
                await self.serve(client)
            }
        }
    }

    private func serve(_ descriptor: Int32) async {
        defer {
            finishServing(descriptor)
        }

        let request: ControlRequest?
        let response: ControlResponse
        do {
            let data = try readLine(from: descriptor)
            let decodedRequest = try JSONDecoder().decode(ControlRequest.self, from: data)
            request = decodedRequest
            response = await handler(decodedRequest)
        } catch {
            request = nil
            response = ControlResponse(
                ok: false,
                message: "Malformed control request."
            )
        }

        do {
            var payload = try JSONEncoder().encode(response)
            payload.append(0x0A)
            try writeAll(payload, to: descriptor)
            untrackClient(descriptor)
            if let request, let onResponseFlushed {
                await onResponseFlushed(request, response)
            }
        } catch {
            // The peer may have exited while an application action completed.
        }
    }

    private func finishServing(_ descriptor: Int32) {
        untrackClient(descriptor)
        Darwin.shutdown(descriptor, SHUT_RDWR)
        Darwin.close(descriptor)
    }

    private func untrackClient(_ descriptor: Int32) {
        stateLock.lock()
        clientDescriptors.remove(descriptor)
        stateLock.unlock()
    }

    private func prepareParentDirectory() throws {
        let directory = socketURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard Darwin.chmod(directory.path, S_IRWXU) == 0 else {
            throw ControlTransportError.systemCall("chmod", errno)
        }
    }

    private func removeStaleSocketIfNeeded() throws {
        var information = stat()
        guard Darwin.lstat(socketURL.path, &information) == 0 else {
            if errno == ENOENT {
                return
            }
            throw ControlTransportError.systemCall("lstat", errno)
        }

        guard information.st_mode & mode_t(S_IFMT) == mode_t(S_IFSOCK) else {
            throw ControlTransportError.invalidSocketNode(socketURL)
        }

        let probe = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard probe >= 0 else {
            throw ControlTransportError.systemCall("socket", errno)
        }
        defer {
            Darwin.close(probe)
        }

        var address = try makeUnixAddress(path: socketURL.path)
        let connectionResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(
                    probe,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
            }
        }
        if connectionResult == 0 {
            throw ControlTransportError.alreadyRunning(socketURL)
        }

        let connectionError = errno
        guard connectionError == ECONNREFUSED || connectionError == ENOENT else {
            throw ControlTransportError.systemCall("connect", connectionError)
        }
        guard Darwin.unlink(socketURL.path) == 0 || errno == ENOENT else {
            throw ControlTransportError.systemCall("unlink", errno)
        }
    }
}

private let maximumControlMessageSize = 65_536

private func setNonblocking(_ descriptor: Int32) throws {
    let flags = Darwin.fcntl(descriptor, F_GETFL)
    guard flags >= 0 else {
        throw ControlTransportError.systemCall("fcntl", errno)
    }
    guard Darwin.fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
        throw ControlTransportError.systemCall("fcntl", errno)
    }
}

private func setBlocking(_ descriptor: Int32) -> Bool {
    let flags = Darwin.fcntl(descriptor, F_GETFL)
    guard flags >= 0 else {
        return false
    }
    return Darwin.fcntl(descriptor, F_SETFL, flags & ~O_NONBLOCK) >= 0
}

private func makeUnixAddress(path: String) throws -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    address.sun_family = sa_family_t(AF_UNIX)

    let pathBytes = Array(path.utf8)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    guard pathBytes.count < capacity else {
        throw ControlTransportError.socketPathTooLong(URL(fileURLWithPath: path))
    }

    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
        buffer.initializeMemory(as: UInt8.self, repeating: 0)
        buffer.copyBytes(from: pathBytes)
    }
    return address
}

private func setNoSigPipe(_ descriptor: Int32) {
    var enabled: Int32 = 1
    _ = withUnsafePointer(to: &enabled) {
        Darwin.setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            $0,
            socklen_t(MemoryLayout<Int32>.size)
        )
    }
}

private func setTimeout(_ timeout: TimeInterval, on descriptor: Int32) {
    let boundedTimeout = max(0, timeout)
    let seconds = Int(boundedTimeout)
    let microseconds = Int32((boundedTimeout - Double(seconds)) * 1_000_000)
    var value = timeval(tv_sec: seconds, tv_usec: microseconds)

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

private func readLine(from descriptor: Int32) throws -> Data {
    var accumulated = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)

    while accumulated.count <= maximumControlMessageSize {
        let count = Darwin.recv(descriptor, &buffer, buffer.count, 0)
        if count > 0 {
            accumulated.append(contentsOf: buffer.prefix(Int(count)))
            if let newline = accumulated.firstIndex(of: 0x0A) {
                guard newline <= maximumControlMessageSize else {
                    throw ControlTransportError.requestTooLarge
                }
                var line = accumulated[..<newline]
                if line.last == 0x0D {
                    line = line.dropLast()
                }
                guard !line.isEmpty else {
                    throw ControlTransportError.malformedMessage
                }
                return Data(line)
            }
            guard accumulated.count <= maximumControlMessageSize else {
                throw ControlTransportError.requestTooLarge
            }
            continue
        }
        if count == 0 {
            throw ControlTransportError.disconnected
        }
        if errno == EINTR {
            continue
        }
        throw ControlTransportError.systemCall("recv", errno)
    }
    throw ControlTransportError.requestTooLarge
}

private func writeAll(_ data: Data, to descriptor: Int32) throws {
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
                continue
            }
            if count < 0, errno == EINTR {
                continue
            }
            if count == 0 {
                throw ControlTransportError.disconnected
            }
            throw ControlTransportError.systemCall("send", errno)
        }
    }
}
