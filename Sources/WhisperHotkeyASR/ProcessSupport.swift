import Darwin
import Foundation

enum OwnedProcessTermination {
    static let defaultGrace: TimeInterval = 0.25

    static func terminate(
        _ process: Process,
        wait: Bool,
        grace: TimeInterval = defaultGrace
    ) {
        guard process.isRunning else { return }
        send(SIGTERM, to: process)

        let finish: @Sendable () -> Void = {
            waitForExit(process, timeout: grace)
            if process.isRunning {
                send(SIGKILL, to: process)
                waitForExit(process, timeout: grace)
            }
        }
        if wait {
            finish()
        } else {
            DispatchQueue.global(qos: .utility).async(execute: finish)
        }
    }

    private static func send(_ signal: Int32, to process: Process) {
        let pid = process.processIdentifier
        guard pid > 1 else { return }
        let target = getpgid(pid) == pid ? -pid : pid
        _ = Darwin.kill(target, signal)
    }

    private static func waitForExit(_ process: Process, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(max(0, timeout))
        while process.isRunning, Date() < deadline {
            usleep(10_000)
        }
        if !process.isRunning {
            process.waitUntilExit()
        }
    }
}

final class OwnedProcessController: @unchecked Sendable {
    struct Lease: Equatable, Sendable {
        fileprivate let identifier: UUID
    }

    private let lock = NSLock()
    private var process: Process?
    private var lease = Lease(identifier: UUID())
    private var cancelled = false

    func isCancelled(_ candidate: Lease) -> Bool {
        lock.withLock {
            cancelled || candidate != lease
        }
    }

    func beginDictation() -> Lease {
        let result: (Process?, Lease) = lock.withLock {
            let previous = process
            process = nil
            lease = Lease(identifier: UUID())
            cancelled = false
            return (previous, lease)
        }
        if let previous = result.0, previous.isRunning {
            OwnedProcessTermination.terminate(previous, wait: true)
        }
        return result.1
    }

    @discardableResult
    func install(_ candidate: Process, lease candidateLease: Lease) -> Bool {
        let accepted = lock.withLock {
            guard candidateLease == lease, !cancelled else {
                return false
            }
            process = candidate
            return true
        }
        if !accepted, candidate.isRunning {
            OwnedProcessTermination.terminate(candidate, wait: false)
        }
        return accepted
    }

    func clear(_ candidate: Process, lease candidateLease: Lease) {
        lock.withLock {
            if candidateLease == lease, process === candidate {
                process = nil
            }
        }
    }

    func cancel(_ candidateLease: Lease, wait: Bool = false) {
        let active: Process? = lock.withLock {
            guard candidateLease == lease else {
                return nil
            }
            cancelled = true
            return process
        }
        if let active, active.isRunning {
            OwnedProcessTermination.terminate(active, wait: wait)
        }
    }

    func finish(_ candidateLease: Lease, wait: Bool = false) {
        let active: Process? = lock.withLock {
            guard candidateLease == lease else {
                return nil
            }
            cancelled = true
            lease = Lease(identifier: UUID())
            let active = process
            process = nil
            return active
        }
        if let active, active.isRunning {
            OwnedProcessTermination.terminate(active, wait: wait)
        }
    }
}

final class LockedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let limit: Int

    init(limit: Int = 1_048_576) {
        self.limit = limit
    }

    func append(_ chunk: Data) {
        lock.withLock {
            guard data.count < limit else { return }
            data.append(chunk.prefix(limit - data.count))
        }
    }

    func snapshot() -> Data {
        lock.withLock { data }
    }
}

final class JSONLineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()
    private var lines: [String] = []
    private var reachedEOF = false

    func consume(_ data: Data) {
        lock.withLock {
            guard !data.isEmpty else {
                reachedEOF = true
                return
            }
            pending.append(data)
            while let newline = pending.firstIndex(of: 0x0A) {
                let lineData = pending[..<newline]
                pending.removeSubrange(...newline)
                if lineData.count <= 65_536 {
                    lines.append(
                        String(decoding: lineData, as: UTF8.self)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
            }
            if pending.count > 65_536 {
                pending.removeAll(keepingCapacity: false)
                reachedEOF = true
            }
        }
    }

    func pop() -> String? {
        lock.withLock {
            guard !lines.isEmpty else { return nil }
            return lines.removeFirst()
        }
    }

    var isFinished: Bool {
        lock.withLock { reachedEOF && lines.isEmpty }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
