import AppKit
import Foundation

public struct ClipboardRepresentation: Equatable, Sendable {
    public let type: String
    public let data: Data

    public init(type: String, data: Data) {
        self.type = type
        self.data = data
    }
}

public struct ClipboardItemSnapshot: Equatable, Sendable {
    public let representations: [ClipboardRepresentation]

    public init(representations: [ClipboardRepresentation]) {
        self.representations = representations
    }
}

public struct ClipboardSnapshot: Equatable, Sendable {
    public let items: [ClipboardItemSnapshot]

    public init(items: [ClipboardItemSnapshot]) {
        self.items = items
    }
}

@MainActor
public protocol PasteboardAccess: AnyObject {
    var changeCount: Int { get }
    func snapshotReadableContents() -> ClipboardSnapshot
    @discardableResult func replaceContents(withPlainText text: String) -> Int?
    @discardableResult func restore(_ snapshot: ClipboardSnapshot) -> Int
}

@MainActor
public final class SystemPasteboard: PasteboardAccess {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public var changeCount: Int {
        pasteboard.changeCount
    }

    public func snapshotReadableContents() -> ClipboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            ClipboardItemSnapshot(
                representations: item.types.compactMap { type in
                    item.data(forType: type).map {
                        ClipboardRepresentation(type: type.rawValue, data: $0)
                    }
                }
            )
        }
        return ClipboardSnapshot(items: items)
    }

    @discardableResult
    public func replaceContents(withPlainText text: String) -> Int? {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        guard item.setString(text, forType: .string),
              pasteboard.writeObjects([item])
        else {
            return nil
        }
        return pasteboard.changeCount
    }

    @discardableResult
    public func restore(_ snapshot: ClipboardSnapshot) -> Int {
        pasteboard.clearContents()
        let items: [NSPasteboardItem] = snapshot.items.map { savedItem in
            let item = NSPasteboardItem()
            for representation in savedItem.representations {
                item.setData(
                    representation.data,
                    forType: NSPasteboard.PasteboardType(representation.type)
                )
            }
            return item
        }
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
        return pasteboard.changeCount
    }
}

@MainActor
public final class ClipboardTransactionController {
    private struct PendingRestore {
        let snapshot: ClipboardSnapshot
        let ownedChangeCount: Int
    }

    private let pasteboard: PasteboardAccess
    private let restorationDelayNanoseconds: UInt64
    private var pendingRestore: PendingRestore?
    private var generation: UInt64 = 0

    public init(
        pasteboard: PasteboardAccess = SystemPasteboard(),
        restorationDelay: TimeInterval = 0.06
    ) {
        self.pasteboard = pasteboard
        restorationDelayNanoseconds = UInt64(max(0, restorationDelay) * 1_000_000_000)
    }

    /// Permanently replaces the clipboard, matching an ordinary Copy action.
    @discardableResult
    public func copy(_ text: String) -> Bool {
        generation &+= 1
        pendingRestore = nil
        return pasteboard.replaceContents(withPlainText: text) != nil
    }

    @discardableResult
    public func pasteTemporarily(
        _ text: String,
        postingPasteWith postPaste: () -> Bool
    ) -> Bool {
        generation &+= 1
        completePendingRestoration()

        let snapshot = pasteboard.snapshotReadableContents()
        guard let ownedChangeCount = pasteboard.replaceContents(withPlainText: text) else {
            pasteboard.restore(snapshot)
            return false
        }
        guard postPaste() else {
            if pasteboard.changeCount == ownedChangeCount {
                pasteboard.restore(snapshot)
            }
            return false
        }

        generation &+= 1
        let restoreGeneration = generation
        pendingRestore = PendingRestore(
            snapshot: snapshot,
            ownedChangeCount: ownedChangeCount
        )
        scheduleRestoration(generation: restoreGeneration)
        return true
    }

    /// Exposed for deterministic shutdown and focused tests. Restoration occurs
    /// only while the temporary pasteboard value is still owned.
    public func completePendingRestoration() {
        guard let pendingRestore else {
            return
        }
        self.pendingRestore = nil
        guard pasteboard.changeCount == pendingRestore.ownedChangeCount else {
            return
        }
        pasteboard.restore(pendingRestore.snapshot)
    }

    private func scheduleRestoration(generation restoreGeneration: UInt64) {
        let delay = restorationDelayNanoseconds
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self, restoreGeneration == generation else {
                return
            }
            completePendingRestoration()
        }
    }
}
