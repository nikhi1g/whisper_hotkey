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

    @MainActor
    func testTemporaryPasteRestoresOriginalClipboard() {
        let original = textSnapshot("original")
        let pasteboard = FakePasteboard(snapshot: original)
        let controller = ClipboardTransactionController(
            pasteboard: pasteboard,
            restorationDelay: 3_600
        )

        XCTAssertTrue(controller.pasteTemporarily("transcript") { true })
        XCTAssertEqual(pasteboard.replacedTexts, ["transcript"])
        controller.completePendingRestoration()
        XCTAssertEqual(pasteboard.restoredSnapshots, [original])
    }

    @MainActor
    func testTemporaryPasteDoesNotOverwriteNewerClipboard() {
        let pasteboard = FakePasteboard(snapshot: textSnapshot("original"))
        let controller = ClipboardTransactionController(
            pasteboard: pasteboard,
            restorationDelay: 3_600
        )

        XCTAssertTrue(controller.pasteTemporarily("transcript") { true })
        pasteboard.simulateExternalChange()
        controller.completePendingRestoration()
        XCTAssertTrue(pasteboard.restoredSnapshots.isEmpty)
    }

    @MainActor
    func testFailedPastePostRestoresImmediately() {
        let original = textSnapshot("original")
        let pasteboard = FakePasteboard(snapshot: original)
        let controller = ClipboardTransactionController(pasteboard: pasteboard)

        XCTAssertFalse(controller.pasteTemporarily("transcript") { false })
        XCTAssertEqual(pasteboard.restoredSnapshots, [original])
    }

    @MainActor
    func testPermanentCopyCancelsPendingRestoration() {
        let pasteboard = FakePasteboard(snapshot: textSnapshot("original"))
        let controller = ClipboardTransactionController(
            pasteboard: pasteboard,
            restorationDelay: 3_600
        )

        XCTAssertTrue(controller.pasteTemporarily("transcript") { true })
        XCTAssertTrue(controller.copy("last dictation"))
        controller.completePendingRestoration()

        XCTAssertEqual(
            pasteboard.replacedTexts,
            ["transcript", "last dictation"]
        )
        XCTAssertTrue(pasteboard.restoredSnapshots.isEmpty)
    }

    private func textSnapshot(_ text: String) -> ClipboardSnapshot {
        ClipboardSnapshot(items: [
            ClipboardItemSnapshot(representations: [
                ClipboardRepresentation(
                    type: "public.utf8-plain-text",
                    data: Data(text.utf8)
                ),
            ]),
        ])
    }
}

@MainActor
private final class FakePasteboard: PasteboardAccess {
    private(set) var changeCount = 1
    private var snapshot: ClipboardSnapshot
    private(set) var replacedTexts: [String] = []
    private(set) var restoredSnapshots: [ClipboardSnapshot] = []

    init(snapshot: ClipboardSnapshot) {
        self.snapshot = snapshot
    }

    func snapshotReadableContents() -> ClipboardSnapshot {
        snapshot
    }

    func replaceContents(withPlainText text: String) -> Int? {
        replacedTexts.append(text)
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
