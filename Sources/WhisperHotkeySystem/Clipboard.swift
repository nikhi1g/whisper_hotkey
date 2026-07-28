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

public enum ClipboardLeasePhase: Equatable, Sendable {
    case inactive
    case awaitingPaste
    case restorationPending
}

public enum ClipboardLeaseEffect: Equatable, Sendable {
    case none
    case scheduleRestoration
    case restoreNow
    case discard
}

public struct ClipboardLeaseStateMachine: Equatable, Sendable {
    public private(set) var phase: ClipboardLeasePhase = .inactive
    public private(set) var ownedChangeCount: Int?

    public init() {}

    public mutating func install(ownedChangeCount: Int) {
        phase = .awaitingPaste
        self.ownedChangeCount = ownedChangeCount
    }

    public mutating func manualPaste(currentChangeCount: Int) -> ClipboardLeaseEffect {
        guard phase == .awaitingPaste else {
            return .none
        }
        guard currentChangeCount == ownedChangeCount else {
            clear()
            return .discard
        }
        phase = .restorationPending
        return .scheduleRestoration
    }

    public mutating func copyOrCut() -> ClipboardLeaseEffect {
        guard phase != .inactive else {
            return .none
        }
        clear()
        return .discard
    }

    public mutating func finishRestoration(
        currentChangeCount: Int
    ) -> ClipboardLeaseEffect {
        guard phase == .restorationPending else {
            return .none
        }
        let stillOwned = currentChangeCount == ownedChangeCount
        clear()
        return stillOwned ? .restoreNow : .discard
    }

    public mutating func cancel(currentChangeCount: Int) -> ClipboardLeaseEffect {
        guard phase != .inactive else {
            return .none
        }
        let stillOwned = currentChangeCount == ownedChangeCount
        clear()
        return stillOwned ? .restoreNow : .discard
    }

    private mutating func clear() {
        phase = .inactive
        ownedChangeCount = nil
    }
}

@MainActor
public final class ClipboardTransactionController {
    public typealias LeaseStateHandler = @MainActor (ClipboardLeasePhase) -> Void

    private struct PendingDirectRestore {
        let snapshot: ClipboardSnapshot
        let ownedChangeCount: Int
        let generation: UInt64
    }

    private let pasteboard: PasteboardAccess
    private let restorationDelayNanoseconds: UInt64
    private var leaseMachine = ClipboardLeaseStateMachine()
    private var leaseSnapshot: ClipboardSnapshot?
    private var pendingDirectRestore: PendingDirectRestore?
    private var generation: UInt64 = 0

    public var onLeaseStateChange: LeaseStateHandler?

    public init(
        pasteboard: PasteboardAccess = SystemPasteboard(),
        restorationDelay: TimeInterval = 0.06
    ) {
        self.pasteboard = pasteboard
        restorationDelayNanoseconds = UInt64(max(0, restorationDelay) * 1_000_000_000)
    }

    public var leaseState: ClipboardLeasePhase {
        leaseMachine.phase
    }

    public var isLeaseActive: Bool {
        leaseMachine.phase != .inactive
    }

    @discardableResult
    public func installLease(_ text: String) -> Bool {
        generation &+= 1
        cancelLease()
        completeDirectRestoreIfOwned()

        let snapshot = pasteboard.snapshotReadableContents()
        guard let ownedChangeCount = pasteboard.replaceContents(withPlainText: text) else {
            pasteboard.restore(snapshot)
            return false
        }
        leaseSnapshot = snapshot
        leaseMachine.install(ownedChangeCount: ownedChangeCount)
        notifyLeaseState()
        return true
    }

    public func cancelLease() {
        let oldPhase = leaseMachine.phase
        guard oldPhase != .inactive else {
            return
        }
        let effect = leaseMachine.cancel(currentChangeCount: pasteboard.changeCount)
        if effect == .restoreNow, let leaseSnapshot {
            pasteboard.restore(leaseSnapshot)
        }
        self.leaseSnapshot = nil
        if oldPhase != leaseMachine.phase {
            notifyLeaseState()
        }
        generation &+= 1
    }

    public func manualPasteWillDispatch() {
        let oldPhase = leaseMachine.phase
        let effect = leaseMachine.manualPaste(currentChangeCount: pasteboard.changeCount)
        guard effect == .scheduleRestoration else {
            if oldPhase != leaseMachine.phase {
                leaseSnapshot = nil
                notifyLeaseState()
            }
            return
        }
        notifyLeaseState()
        scheduleLeaseRestoration()
    }

    public func copyOrCutWillDispatch() {
        let ownedChangeCounts = Set(
            [
                leaseMachine.phase == .inactive
                    ? nil
                    : leaseMachine.ownedChangeCount,
                pendingDirectRestore?.ownedChangeCount,
            ].compactMap { $0 }
        )
        guard !ownedChangeCounts.isEmpty else {
            return
        }

        generation &+= 1
        let reconciliationGeneration = generation
        guard ownedChangeCounts.contains(pasteboard.changeCount) else {
            discardClipboardObligationsForCopyOrCut()
            return
        }
        scheduleCopyOrCutReconciliation(
            generation: reconciliationGeneration,
            ownedChangeCounts: ownedChangeCounts
        )
    }

    @discardableResult
    public func pasteTemporarily(
        _ text: String,
        postingPasteWith postPaste: () -> Bool
    ) -> Bool {
        generation &+= 1
        cancelLease()
        completeDirectRestoreIfOwned()

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
        pendingDirectRestore = PendingDirectRestore(
            snapshot: snapshot,
            ownedChangeCount: ownedChangeCount,
            generation: restoreGeneration
        )
        scheduleDirectRestoration(generation: restoreGeneration)
        return true
    }

    /// Exposed for deterministic shutdown and focused tests. Restoration occurs
    /// only while the temporary pasteboard value is still owned.
    public func completePendingRestoration() {
        completeDirectRestoreIfOwned()
        finishLeaseRestoration()
    }

    private func scheduleLeaseRestoration() {
        generation &+= 1
        let restoreGeneration = generation
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            try? await Task.sleep(nanoseconds: restorationDelayNanoseconds)
            guard restoreGeneration == generation else {
                return
            }
            finishLeaseRestoration()
        }
    }

    private func scheduleDirectRestoration(generation restoreGeneration: UInt64) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            try? await Task.sleep(nanoseconds: restorationDelayNanoseconds)
            guard restoreGeneration == generation else {
                return
            }
            completeDirectRestoreIfOwned()
        }
    }

    private func scheduleCopyOrCutReconciliation(
        generation reconciliationGeneration: UInt64,
        ownedChangeCounts: Set<Int>
    ) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            try? await Task.sleep(nanoseconds: restorationDelayNanoseconds)
            guard reconciliationGeneration == generation else {
                return
            }
            guard ownedChangeCounts.contains(pasteboard.changeCount) else {
                discardClipboardObligationsForCopyOrCut()
                return
            }

            // A no-op copy/cut must not abandon the original clipboard. If a
            // restoration was already pending, complete it; otherwise retain
            // the one-paste lease for the next real paste or copy.
            completeDirectRestoreIfOwned()
            if leaseMachine.phase == .restorationPending {
                finishLeaseRestoration()
            }
        }
    }

    private func discardClipboardObligationsForCopyOrCut() {
        let oldPhase = leaseMachine.phase
        _ = leaseMachine.copyOrCut()
        leaseSnapshot = nil
        pendingDirectRestore = nil
        if oldPhase != leaseMachine.phase {
            notifyLeaseState()
        }
    }

    private func finishLeaseRestoration() {
        guard leaseMachine.phase == .restorationPending else {
            return
        }
        let oldPhase = leaseMachine.phase
        let effect = leaseMachine.finishRestoration(
            currentChangeCount: pasteboard.changeCount
        )
        if effect == .restoreNow, let leaseSnapshot {
            pasteboard.restore(leaseSnapshot)
        }
        leaseSnapshot = nil
        if oldPhase != leaseMachine.phase {
            notifyLeaseState()
        }
    }

    private func completeDirectRestoreIfOwned() {
        guard let pendingDirectRestore else {
            return
        }
        self.pendingDirectRestore = nil
        guard pasteboard.changeCount == pendingDirectRestore.ownedChangeCount else {
            return
        }
        pasteboard.restore(pendingDirectRestore.snapshot)
    }

    private func notifyLeaseState() {
        onLeaseStateChange?(leaseMachine.phase)
    }
}
