import Foundation

/// Errors raised when a bounded view cannot be borrowed from a session lease.
public enum WhisperAudioLeaseError: Error, Equatable, Sendable {
    case leaseFinished
    case invalidSpanBounds
    case spanTooLong
}

/// A read-only sample range into a canonical session recording.
///
/// A span never copies audio. Its lease holder keeps the canonical file alive
/// until every consumer releases the view, including consumers cancelled while
/// an asynchronous recognizer is still unwinding.
public final class WhisperAudioSpan: @unchecked Sendable {
    public let url: URL
    public let startSample: Int64
    public let endSample: Int64
    public let sampleRate: Int

    public var sampleCount: Int64 {
        endSample - startSample
    }

    public var duration: TimeInterval {
        Double(sampleCount) / Double(sampleRate)
    }

    private let holder: WhisperAudioLease.Holder

    init(
        url: URL,
        startSample: Int64,
        endSample: Int64,
        sampleRate: Int,
        holder: WhisperAudioLease.Holder
    ) {
        self.url = url
        self.startSample = startSample
        self.endSample = endSample
        self.sampleRate = sampleRate
        self.holder = holder
    }

    deinit {
        holder.release()
    }
}

/// Session-owned lifetime for a private canonical recording.
///
/// The lease owns the private root directory and tracks every consumer of the
/// canonical file. Providers only borrow holders; they never delete caller
/// audio. `finish()`/`cancel()` make the lease closed to new views, while
/// cleanup waits for all active holders and executes the root deletion once.
public final class WhisperAudioLease: @unchecked Sendable {
    public static let defaultMaximumSpanDuration: TimeInterval = 30

    public let directoryURL: URL
    public let canonicalURL: URL

    /// The default bound keeps verifier work proportional to an uncertain span
    /// rather than allowing an accidental whole-session copy or decode.
    public let maximumSpanDuration: TimeInterval

    private let storage: Storage
    private let canonicalResource: Storage.ResourceID

    public init(
        directoryURL: URL,
        canonicalURL: URL? = nil,
        fileManager: FileManager = .default,
        maximumSpanDuration: TimeInterval =
            WhisperAudioLease.defaultMaximumSpanDuration
    ) {
        self.directoryURL = directoryURL
        self.canonicalURL = canonicalURL
            ?? directoryURL.appendingPathComponent("dictation.wav")
        self.maximumSpanDuration = max(
            0,
            maximumSpanDuration.isFinite
                ? maximumSpanDuration
                : Self.defaultMaximumSpanDuration
        )
        let storage = Storage(
            rootURL: directoryURL,
            fileManager: fileManager,
            initiallyFinished: false
        )
        guard let canonicalResource = storage.register(
            directoryURL: directoryURL,
            canonical: true
        ) else {
            preconditionFailure("A new audio lease must be borrowable.")
        }
        self.storage = storage
        self.canonicalResource = canonicalResource
    }

    /// Creates a fresh private 0700 session directory.
    public static func create(
        in temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        fileManager: FileManager = .default,
        maximumSpanDuration: TimeInterval =
            WhisperAudioLease.defaultMaximumSpanDuration
    ) throws -> WhisperAudioLease {
        let directory = temporaryDirectory.appendingPathComponent(
            "whisper_hotkey-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            return WhisperAudioLease(
                directoryURL: directory,
                fileManager: fileManager,
                maximumSpanDuration: maximumSpanDuration
            )
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    deinit {
        finish()
    }

    public var isFinished: Bool {
        storage.isFinished
    }

    public var isCleaned: Bool {
        storage.isCleaned
    }

    /// Borrows the canonical file as one immutable file holder.
    internal func makeCanonicalFile(
        speechPresence: WhisperSpeechPresence = .unknown
    ) -> WhisperAudioFile {
        guard let holder = storage.acquire(canonicalResource) else {
            preconditionFailure("A canonical file cannot be borrowed after finish.")
        }
        return WhisperAudioFile(
            url: canonicalURL,
            directoryURL: directoryURL,
            storage: storage,
            resourceID: canonicalResource,
            speechPresence: speechPresence,
            maximumSpanDuration: maximumSpanDuration,
            holder: holder
        )
    }

    /// Creates a bounded private segment directory under this session root.
    /// Segment files remain mode 0600 and are retired independently as soon as
    /// their last holder releases, so Pause Mode cannot accumulate files.
    internal func makeChildFile() throws -> WhisperAudioFile {
        let directory = directoryURL.appendingPathComponent(
            "segment-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            let (resourceID, holder) = try storage.createChildResource(
                at: directory
            )
            let url = directory.appendingPathComponent("dictation.wav")
            return WhisperAudioFile(
                url: url,
                directoryURL: directory,
                storage: storage,
                resourceID: resourceID,
                speechPresence: .unknown,
                maximumSpanDuration: maximumSpanDuration,
                holder: holder
            )
        } catch {
            // The storage method removes a directory it created when
            // registration fails. This second attempt is harmless for the
            // lease-finished path and covers custom FileManager failures.
            try? storage.fileManager.removeItem(at: directory)
            throw error
        }
    }

    /// Creates an immutable sample-range view into the canonical WAV.
    public func makeSpan(
        startSample: Int64,
        endSample: Int64,
        sampleRate: Int
    ) throws -> WhisperAudioSpan {
        guard !isFinished else {
            throw WhisperAudioLeaseError.leaseFinished
        }
        guard sampleRate > 0,
              startSample >= 0,
              endSample > startSample,
              endSample >= 0
        else {
            throw WhisperAudioLeaseError.invalidSpanBounds
        }
        let sampleCount = endSample - startSample
        guard Double(sampleCount)
            <= maximumSpanDuration * Double(sampleRate)
        else {
            throw WhisperAudioLeaseError.spanTooLong
        }
        guard let holder = storage.acquire(canonicalResource) else {
            throw WhisperAudioLeaseError.leaseFinished
        }
        return WhisperAudioSpan(
            url: canonicalURL,
            startSample: startSample,
            endSample: endSample,
            sampleRate: sampleRate,
            holder: holder
        )
    }

    public func finish() {
        storage.finish()
    }

    public func cancel() {
        finish()
    }

    fileprivate func retire(_ resourceID: Storage.ResourceID) {
        storage.retire(resourceID)
    }

    fileprivate func acquire(_ resourceID: Storage.ResourceID)
        -> Holder?
    {
        storage.acquire(resourceID)
    }

    public final class Holder: @unchecked Sendable {
        private let storage: Storage
        private let resourceID: Storage.ResourceID
        private let lock = NSLock()
        private var released = false

        fileprivate init(
            storage: Storage,
            resourceID: Storage.ResourceID
        ) {
            self.storage = storage
            self.resourceID = resourceID
        }

        public func release() {
            let shouldRelease = lock.withLock {
                guard !released else { return false }
                released = true
                return true
            }
            if shouldRelease {
                storage.release(resourceID)
            }
        }

        deinit {
            release()
        }
    }

    final class Storage: @unchecked Sendable {
        struct ResourceID: Hashable, Sendable {
            let rawValue: UUID
        }

        private struct Resource {
            let directoryURL: URL
            let canonical: Bool
            var holders: Int
            var retired: Bool
            var deleted: Bool
        }

        let rootURL: URL
        let fileManager: FileManager
        private let lock = NSLock()
        private var resources: [ResourceID: Resource] = [:]
        private var finished: Bool
        private var rootDeleted = false

        init(
            rootURL: URL,
            fileManager: FileManager,
            initiallyFinished: Bool
        ) {
            self.rootURL = rootURL
            self.fileManager = fileManager
            finished = initiallyFinished
        }

        var isFinished: Bool {
            lock.withLock { finished }
        }

        var isCleaned: Bool {
            lock.withLock { rootDeleted }
        }

        func register(
            directoryURL: URL,
            canonical: Bool
        ) -> ResourceID? {
            lock.withLock {
                guard !finished, !rootDeleted else {
                    return nil
                }
                let id = ResourceID(rawValue: UUID())
                resources[id] = Resource(
                    directoryURL: directoryURL,
                    canonical: canonical,
                    holders: 0,
                    retired: false,
                    deleted: false
                )
                return id
            }
        }

        func acquire(_ resourceID: ResourceID) -> Holder? {
            let acquired = lock.withLock {
                guard !finished,
                      var resource = resources[resourceID],
                      !resource.deleted
                else {
                    return false
                }
                resource.holders += 1
                resources[resourceID] = resource
                return true
            }
            return acquired
                ? Holder(storage: self, resourceID: resourceID)
                : nil
        }

        /// Creates a child directory and reserves its first holder while the
        /// storage lock is held. This closes the race where `finish()` could
        /// otherwise remove the session root between directory creation and
        /// resource registration.
        func createChildResource(
            at directoryURL: URL
        ) throws -> (ResourceID, Holder) {
            try lock.withLock {
                guard !finished, !rootDeleted else {
                    throw WhisperAudioLeaseError.leaseFinished
                }
                try fileManager.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700]
                )
                let id = ResourceID(rawValue: UUID())
                resources[id] = Resource(
                    directoryURL: directoryURL,
                    canonical: false,
                    holders: 1,
                    retired: false,
                    deleted: false
                )
                return (id, Holder(storage: self, resourceID: id))
            }
        }

        func retire(_ resourceID: ResourceID) {
            let directoryToDelete: URL? = lock.withLock {
                guard var resource = resources[resourceID] else {
                    return nil
                }
                resource.retired = true
                let shouldDelete = !resource.canonical
                    && resource.holders == 0
                    && !resource.deleted
                    && !rootDeleted
                if shouldDelete {
                    resource.deleted = true
                    resources[resourceID] = resource
                    return resource.directoryURL
                }
                resources[resourceID] = resource
                return nil
            }
            delete(directoryToDelete)
        }

        func release(_ resourceID: ResourceID) {
            var directoryToDelete: URL?
            var rootToDelete: URL?
            lock.withLock {
                guard var resource = resources[resourceID],
                      resource.holders > 0
                else {
                    return
                }
                resource.holders -= 1
                if !resource.canonical,
                   resource.retired,
                   resource.holders == 0,
                   !resource.deleted,
                   !rootDeleted {
                    resource.deleted = true
                    directoryToDelete = resource.directoryURL
                }
                resources[resourceID] = resource
                if finished,
                   !rootDeleted,
                   resources.values.allSatisfy({ $0.holders == 0 }) {
                    rootDeleted = true
                    rootToDelete = rootURL
                }
            }
            delete(directoryToDelete)
            delete(rootToDelete)
        }

        func finish() {
            var rootToDelete: URL?
            lock.withLock {
                finished = true
                if !rootDeleted,
                   resources.values.allSatisfy({ $0.holders == 0 }) {
                    rootDeleted = true
                    rootToDelete = rootURL
                }
            }
            delete(rootToDelete)
        }

        private func delete(_ url: URL?) {
            guard let url else { return }
            try? fileManager.removeItem(at: url)
        }
    }
}

extension WhisperAudioLease {
    /// A non-owning copy of the canonical sample bounds for callers that need
    /// to pass a range through a provider-neutral contract.
    public struct SampleRange: Equatable, Sendable {
        public let startSample: Int64
        public let endSample: Int64

        public init(startSample: Int64, endSample: Int64) {
            self.startSample = startSample
            self.endSample = endSample
        }

        public var sampleCount: Int64 {
            endSample - startSample
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
