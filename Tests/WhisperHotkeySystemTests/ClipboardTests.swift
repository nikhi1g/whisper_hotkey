import XCTest
@testable import WhisperHotkeySystem

final class ClipboardTests: XCTestCase {
    func testSnapshotRetainsAllReadableRepresentations() {
        let snapshot = ClipboardSnapshot(items: [
            ClipboardItemSnapshot(representations: [
                ClipboardRepresentation(type: "public.utf8-plain-text", data: Data("hello".utf8)),
                ClipboardRepresentation(type: "public.html", data: Data("<b>hello</b>".utf8)),
            ]),
            ClipboardItemSnapshot(representations: [
                ClipboardRepresentation(type: "public.file-url", data: Data("file:///tmp/a".utf8)),
            ]),
        ])

        XCTAssertEqual(snapshot.items.count, 2)
        XCTAssertEqual(snapshot.items[0].representations.count, 2)
        XCTAssertEqual(snapshot.items[1].representations[0].type, "public.file-url")
    }

    func testManualPasteSchedulesOwnedRestoration() {
        var machine = ClipboardLeaseStateMachine()
        machine.install(ownedChangeCount: 7)

        XCTAssertEqual(machine.manualPaste(currentChangeCount: 7), .scheduleRestoration)
        XCTAssertEqual(machine.phase, .restorationPending)
        XCTAssertEqual(machine.finishRestoration(currentChangeCount: 7), .restoreNow)
        XCTAssertEqual(machine.phase, .inactive)
    }

    func testNewCopyCancelsLeaseWithoutRestoration() {
        var machine = ClipboardLeaseStateMachine()
        machine.install(ownedChangeCount: 7)

        XCTAssertEqual(machine.copyOrCut(), .discard)
        XCTAssertEqual(machine.phase, .inactive)
    }

    func testExternalClipboardOwnershipChangePreventsRestoration() {
        var machine = ClipboardLeaseStateMachine()
        machine.install(ownedChangeCount: 7)

        XCTAssertEqual(machine.manualPaste(currentChangeCount: 8), .discard)
        XCTAssertEqual(machine.phase, .inactive)
    }

    func testCancelRestoresOnlyWhenLeaseStillOwnsPasteboard() {
        var owned = ClipboardLeaseStateMachine()
        owned.install(ownedChangeCount: 7)
        XCTAssertEqual(owned.cancel(currentChangeCount: 7), .restoreNow)

        var changed = ClipboardLeaseStateMachine()
        changed.install(ownedChangeCount: 7)
        XCTAssertEqual(changed.cancel(currentChangeCount: 8), .discard)
    }

    @MainActor
    func testControllerRestoresFakePasteboardAfterManualPaste() {
        let original = ClipboardSnapshot(items: [
            ClipboardItemSnapshot(representations: [
                ClipboardRepresentation(
                    type: "public.utf8-plain-text",
                    data: Data("original".utf8)
                ),
            ]),
        ])
        let pasteboard = FakePasteboard(snapshot: original)
        let controller = ClipboardTransactionController(
            pasteboard: pasteboard,
            restorationDelay: 3_600
        )

        XCTAssertTrue(controller.installLease("transcript"))
        XCTAssertEqual(controller.leaseState, .awaitingPaste)
        controller.manualPasteWillDispatch()
        XCTAssertEqual(controller.leaseState, .restorationPending)
        controller.completePendingRestoration()

        XCTAssertEqual(controller.leaseState, .inactive)
        XCTAssertEqual(pasteboard.restoredSnapshots, [original])
    }

    @MainActor
    func testControllerDoesNotOverwriteNewerFakeClipboard() {
        let original = ClipboardSnapshot(items: [])
        let pasteboard = FakePasteboard(snapshot: original)
        let controller = ClipboardTransactionController(
            pasteboard: pasteboard,
            restorationDelay: 3_600
        )

        XCTAssertTrue(controller.installLease("transcript"))
        controller.manualPasteWillDispatch()
        pasteboard.simulateExternalChange()
        controller.completePendingRestoration()

        XCTAssertTrue(pasteboard.restoredSnapshots.isEmpty)
        XCTAssertEqual(controller.leaseState, .inactive)
    }
}

@MainActor
private final class FakePasteboard: PasteboardAccess {
    private(set) var changeCount = 1
    private var snapshot: ClipboardSnapshot
    private(set) var restoredSnapshots: [ClipboardSnapshot] = []

    init(snapshot: ClipboardSnapshot) {
        self.snapshot = snapshot
    }

    func snapshotReadableContents() -> ClipboardSnapshot {
        snapshot
    }

    func replaceContents(withPlainText text: String) -> Int? {
        snapshot = ClipboardSnapshot(items: [
            ClipboardItemSnapshot(representations: [
                ClipboardRepresentation(
                    type: "public.utf8-plain-text",
                    data: Data(text.utf8)
                ),
            ]),
        ])
        changeCount += 1
        return changeCount
    }

    func restore(_ snapshot: ClipboardSnapshot) -> Int {
        self.snapshot = snapshot
        restoredSnapshots.append(snapshot)
        changeCount += 1
        return changeCount
    }

    func simulateExternalChange() {
        changeCount += 1
    }
}
