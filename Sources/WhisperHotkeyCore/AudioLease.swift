import Foundation

public actor AudioLease {
    public let sessionID: UUID
    public let canonicalURL: URL
    private let fileManager: FileManager

    private var activeUsers: Int = 0
    private var cleanupRequested = false
    private var finalized = false
    private var derivedURLs: Set<URL> = []

    public init(
        sessionID: UUID = UUID(),
        canonicalURL: URL,
        fileManager: FileManager = .default
    ) {
        self.sessionID = sessionID
        self.canonicalURL = canonicalURL
        self.fileManager = fileManager
    }

    public func beginAccess() {
        activeUsers += 1
    }

    public func endAccess() {
        guard activeUsers > 0 else { return }
        activeUsers -= 1
        if cleanupRequested {
            cleanupIfNeeded()
        }
    }

    public func registerDerived(_ url: URL) {
        derivedURLs.insert(url)
    }

    public func requestCleanup() {
        cleanupRequested = true
        if activeUsers == 0 {
            cleanupIfNeeded()
        }
    }

    public func finish() {
        activeUsers = 0
        requestCleanup()
    }

    private func cleanupIfNeeded() {
        guard !finalized else { return }
        if activeUsers > 0 || !cleanupRequested { return }

        for url in derivedURLs {
            if fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
            }
        }
        if fileManager.fileExists(atPath: canonicalURL.path) {
            try? fileManager.removeItem(at: canonicalURL)
        }

        finalized = true
        derivedURLs.removeAll(keepingCapacity: false)
    }
}
