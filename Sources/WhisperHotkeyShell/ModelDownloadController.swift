import AppKit
import CryptoKit
import Foundation
import WhisperHotkeyCore

/// Downloads a model that was not bundled with the install, showing progress
/// and verifying it against the same pinned digest the build pipeline uses.
@MainActor
public final class ModelDownloadController: NSObject {
    private let entry: DownloadableModel
    private let destination: URL
    private let fileManager: FileManager
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var completion: ((Result<URL, ModelDownloadError>) -> Void)?
    private var panel: ModelDownloadProgressPanel?

    public init(
        entry: DownloadableModel,
        fileManager: FileManager = .default
    ) {
        self.entry = entry
        destination = ModelDownloadCatalog.destinationURL(for: entry.model)
        self.fileManager = fileManager
        super.init()
    }

    /// Asks first, because this is a large transfer the user did not schedule.
    public func confirmAndStart(
        completion: @escaping (Result<URL, ModelDownloadError>) -> Void
    ) {
        let size = ModelDownloadCatalog.humanReadableSize(entry.byteCount)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "\(entry.model.menuTitle) is not installed."
        alert.informativeText = """
            This model was not included in the download because it does not \
            fit alongside the others. It can be downloaded now (\(size)) and \
            is verified against a pinned checksum before it is installed.
            """
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            completion(.failure(.cancelled))
            return
        }
        start(completion: completion)
    }

    public func start(
        completion: @escaping (Result<URL, ModelDownloadError>) -> Void
    ) {
        self.completion = completion
        let panel = ModelDownloadProgressPanel(
            title: "Downloading \(entry.model.menuTitle)",
            totalByteCount: entry.byteCount
        ) { [weak self] in
            self?.cancel()
        }
        panel.show()
        self.panel = panel

        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        let session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: nil
        )
        self.session = session
        let task = session.downloadTask(with: entry.url)
        self.task = task
        task.resume()
    }

    public func cancel() {
        task?.cancel()
        finish(.failure(.cancelled))
    }

    private func finish(_ result: Result<URL, ModelDownloadError>) {
        guard let completion else {
            return
        }
        self.completion = nil
        panel?.close()
        panel = nil
        session?.invalidateAndCancel()
        session = nil
        task = nil
        completion(result)
    }

    private func install(from location: URL) -> Result<URL, ModelDownloadError> {
        guard sha256(of: location) == entry.sha256 else {
            return .failure(.checksumMismatch)
        }
        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: location, to: destination)
        } catch {
            return .failure(.installFailed(error.localizedDescription))
        }
        return .success(destination)
    }

    private func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1024 * 1024),
              !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

extension ModelDownloadController: URLSessionDownloadDelegate {
    public nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let expected = totalBytesExpectedToWrite > 0
            ? totalBytesExpectedToWrite
            : nil
        Task { @MainActor [weak self] in
            self?.panel?.update(
                completedByteCount: totalBytesWritten,
                totalByteCount: expected
            )
        }
    }

    public nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The delegate's temporary file is removed when this returns, so it is
        // relocated synchronously before hopping to the main actor.
        let staged = location.deletingLastPathComponent()
            .appendingPathComponent(
                "whisper_hotkey-model-\(UUID().uuidString)"
            )
        let moved = (try? FileManager.default.moveItem(
            at: location,
            to: staged
        )) != nil
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            guard moved else {
                finish(.failure(.installFailed("The download could not be staged.")))
                return
            }
            let result = install(from: staged)
            try? FileManager.default.removeItem(at: staged)
            finish(result)
        }
    }

    public nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else {
            return
        }
        let isCancellation = (error as NSError).code == NSURLErrorCancelled
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            finish(.failure(
                isCancellation
                    ? .cancelled
                    : .transportFailed(error.localizedDescription)
            ))
        }
    }
}
