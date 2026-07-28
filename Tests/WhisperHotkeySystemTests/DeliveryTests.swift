import XCTest
@testable import WhisperHotkeySystem

@MainActor
final class DeliveryTests: XCTestCase {
    func testMissingAccessibilityContextStillPastesImmediately() {
        let original = ClipboardSnapshot(items: [
            ClipboardItemSnapshot(representations: [
                ClipboardRepresentation(
                    type: "public.utf8-plain-text",
                    data: Data("original".utf8)
                ),
            ]),
        ])
        let pasteboard = DeliveryTestPasteboard(snapshot: original)
        let clipboard = ClipboardTransactionController(
            pasteboard: pasteboard,
            restorationDelay: 3_600
        )
        let poster = DeliveryTestPastePoster(result: true)
        let service = TextDeliveryService(
            clipboard: clipboard,
            pastePoster: poster
        )

        XCTAssertEqual(
            service.deliver(transcript: "  dictated text  ", context: nil),
            .inserted
        )
        XCTAssertEqual(poster.postCount, 1)
        XCTAssertEqual(pasteboard.replacedTexts, ["dictated text "])
        clipboard.completePendingRestoration()
        XCTAssertEqual(pasteboard.restoredSnapshots, [original])
    }

    func testPastePostFailureRestoresClipboardWithoutRetainingTranscript() {
        let original = ClipboardSnapshot(items: [])
        let pasteboard = DeliveryTestPasteboard(snapshot: original)
        let clipboard = ClipboardTransactionController(
            pasteboard: pasteboard,
            restorationDelay: 3_600
        )
        let poster = DeliveryTestPastePoster(result: false)
        let service = TextDeliveryService(
            clipboard: clipboard,
            pastePoster: poster
        )

        XCTAssertEqual(
            service.deliver(transcript: "dictated text", context: nil),
            .clipboardUnavailable
        )
        XCTAssertEqual(poster.postCount, 1)
        XCTAssertEqual(pasteboard.restoredSnapshots, [original])
    }

    func testCopyToClipboardPermanentlyReplacesExistingContents() {
        let original = ClipboardSnapshot(items: [])
        let pasteboard = DeliveryTestPasteboard(snapshot: original)
        let service = TextDeliveryService(
            clipboard: ClipboardTransactionController(pasteboard: pasteboard)
        )

        XCTAssertTrue(service.copyToClipboard("  last words  "))
        XCTAssertEqual(pasteboard.replacedTexts, ["last words"])
        XCTAssertTrue(pasteboard.restoredSnapshots.isEmpty)
    }

    func testReturnIsExplicitAndIndependentOfSuccessfulPaste() {
        let pasteboard = DeliveryTestPasteboard(
            snapshot: ClipboardSnapshot(items: [])
        )
        let returnPoster = DeliveryTestReturnPoster(result: true)
        let service = TextDeliveryService(
            clipboard: ClipboardTransactionController(pasteboard: pasteboard),
            pastePoster: DeliveryTestPastePoster(result: true),
            returnKeyPoster: returnPoster
        )

        XCTAssertEqual(
            service.deliver(transcript: "send this", context: nil),
            .inserted
        )
        XCTAssertEqual(returnPoster.postCount, 0)
        XCTAssertTrue(service.pressReturn())
        XCTAssertEqual(returnPoster.postCount, 1)
    }

    func testSyntheticReturnExplicitlyClearsEveryModifier() throws {
        let source = try XCTUnwrap(
            CGEventSource(stateID: .combinedSessionState)
        )
        let events = try XCTUnwrap(
            CGReturnKeyPoster.makeEvents(source: source)
        )
        let modifierFlags: CGEventFlags = [
            .maskCommand,
            .maskShift,
            .maskAlternate,
            .maskControl,
            .maskAlphaShift,
            .maskSecondaryFn,
        ]

        XCTAssertEqual(events.keyDown.type, .keyDown)
        XCTAssertEqual(events.keyUp.type, .keyUp)
        XCTAssertEqual(
            events.keyDown.getIntegerValueField(.keyboardEventKeycode),
            Int64(MacVirtualKey.returnKey)
        )
        XCTAssertEqual(
            events.keyUp.getIntegerValueField(.keyboardEventKeycode),
            Int64(MacVirtualKey.returnKey)
        )
        XCTAssertTrue(events.keyDown.flags.intersection(modifierFlags).isEmpty)
        XCTAssertTrue(events.keyUp.flags.intersection(modifierFlags).isEmpty)
    }
}

@MainActor
private final class DeliveryTestPastePoster: CommandPastePosting {
    private let result: Bool
    private(set) var postCount = 0

    init(result: Bool) {
        self.result = result
    }

    func postCommandV() -> Bool {
        postCount += 1
        return result
    }
}

@MainActor
private final class DeliveryTestReturnPoster: ReturnKeyPosting {
    private let result: Bool
    private(set) var postCount = 0

    init(result: Bool) {
        self.result = result
    }

    func postReturn() -> Bool {
        postCount += 1
        return result
    }
}

@MainActor
private final class DeliveryTestPasteboard: PasteboardAccess {
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
}
