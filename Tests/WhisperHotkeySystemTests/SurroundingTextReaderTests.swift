import XCTest
@testable import WhisperHotkeySystem

final class SurroundingTextReaderTests: XCTestCase {
    func testBoundedRangeReadsAvoidFullValue() {
        let selection = NSRange(location: 1, length: 1)
        var requestedRanges: [NSRange] = []
        var fullValueWasRead = false

        let context = SurroundingTextReader.read(
            selectionRange: selection,
            boundedText: { range in
                requestedRanges.append(range)
                switch range {
                case selection:
                    return .value("b")
                case NSRange(location: 0, length: 1):
                    return .value("a")
                case NSRange(location: 2, length: 1):
                    return .value("c")
                default:
                    return .unavailable
                }
            },
            fullText: {
                fullValueWasRead = true
                return "abc"
            },
            selectedText: {
                XCTFail("Selected-text fallback should not be read")
                return nil
            }
        )

        XCTAssertEqual(
            context,
            SurroundingText(
                beforeSelection: "a",
                selectedText: "b",
                afterSelection: "c"
            )
        )
        XCTAssertEqual(
            requestedRanges,
            [
                selection,
                NSRange(location: 0, length: 1),
                NSRange(location: 2, length: 1),
            ]
        )
        XCTAssertFalse(fullValueWasRead)
    }

    func testUnavailableBoundedReadFallsBackToFullValue() {
        var fullValueReadCount = 0

        let context = SurroundingTextReader.read(
            selectionRange: NSRange(location: 1, length: 1),
            boundedText: { _ in .unavailable },
            fullText: {
                fullValueReadCount += 1
                return "abc"
            },
            selectedText: {
                XCTFail("Selected-text fallback should not be read")
                return nil
            }
        )

        XCTAssertEqual(
            context,
            SurroundingText(
                beforeSelection: "a",
                selectedText: "b",
                afterSelection: "c"
            )
        )
        XCTAssertEqual(fullValueReadCount, 1)
    }

    func testLegacySelectedTextFallbackRemainsAvailable() {
        let selection = NSRange(location: 1, length: 1)

        let context = SurroundingTextReader.read(
            selectionRange: selection,
            boundedText: { range in
                switch range {
                case NSRange(location: 0, length: 1):
                    return .value("a")
                case NSRange(location: 2, length: 1):
                    return .value("c")
                default:
                    return .unavailable
                }
            },
            fullText: { nil },
            selectedText: { "b" }
        )

        XCTAssertEqual(
            context,
            SurroundingText(
                beforeSelection: "a",
                selectedText: "b",
                afterSelection: "c"
            )
        )
    }

    func testBoundedReadTreatsNoValueAfterSelectionAsEndOfText() {
        var fullValueWasRead = false
        let selection = NSRange(location: 3, length: 0)

        let context = SurroundingTextReader.read(
            selectionRange: selection,
            boundedText: { range in
                switch range {
                case selection:
                    return .value("")
                case NSRange(location: 2, length: 1):
                    return .value("c")
                case NSRange(location: 3, length: 1):
                    return .noValue
                default:
                    return .unavailable
                }
            },
            fullText: {
                fullValueWasRead = true
                return "abc"
            },
            selectedText: { nil }
        )

        XCTAssertEqual(
            context,
            SurroundingText(
                beforeSelection: "c",
                selectedText: "",
                afterSelection: nil
            )
        )
        XCTAssertFalse(fullValueWasRead)
    }
}
