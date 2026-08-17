import Foundation
import XCTest
@testable import WhisperHotkeyCore

final class VoiceCommandParserTests: XCTestCase {
    func testModeCommandsMapToProfiles() {
        XCTAssertEqual(VoiceCommandParser.parse("mode clarity"), .setProfile(.clarity))
        XCTAssertEqual(VoiceCommandParser.parse("mode coding"), .setProfile(.coding))
        XCTAssertEqual(VoiceCommandParser.parse("mode verbatim"), .setProfile(.verbatim))
        XCTAssertEqual(VoiceCommandParser.parse("verbatim mode"), .setProfile(.verbatim))
    }

    func testActionCommandsMapToActions() {
        XCTAssertEqual(VoiceCommandParser.parse("scratch that"), .scratchLastSegment)
        XCTAssertEqual(VoiceCommandParser.parse("send"), .send)
        XCTAssertEqual(VoiceCommandParser.parse("cancel"), .cancel)
        XCTAssertEqual(VoiceCommandParser.parse("show original"), .showOriginal)
    }

    func testCommandsAreCaseInsensitive() {
        XCTAssertEqual(VoiceCommandParser.parse("MODE CLARITY"), .setProfile(.clarity))
        XCTAssertEqual(VoiceCommandParser.parse("Mode Coding"), .setProfile(.coding))
        XCTAssertEqual(VoiceCommandParser.parse("VERBATIM MODE"), .setProfile(.verbatim))
        XCTAssertEqual(VoiceCommandParser.parse("Scratch That"), .scratchLastSegment)
        XCTAssertEqual(VoiceCommandParser.parse("SEND"), .send)
        XCTAssertEqual(VoiceCommandParser.parse("Cancel"), .cancel)
        XCTAssertEqual(VoiceCommandParser.parse("Show Original"), .showOriginal)
    }

    func testCommandsAreTrimmed() {
        XCTAssertEqual(VoiceCommandParser.parse("  mode clarity  "), .setProfile(.clarity))
        XCTAssertEqual(VoiceCommandParser.parse("\tsend\n"), .send)
        XCTAssertEqual(VoiceCommandParser.parse("   show original   "), .showOriginal)
    }

    func testNonCommandTextReturnsNil() {
        XCTAssertNil(VoiceCommandParser.parse(""))
        XCTAssertNil(VoiceCommandParser.parse("   "))
        XCTAssertNil(VoiceCommandParser.parse("hello world"))
        XCTAssertNil(VoiceCommandParser.parse("mode"))
        XCTAssertNil(VoiceCommandParser.parse("mode clarity now"))
        XCTAssertNil(VoiceCommandParser.parse("clarity mode"))
        XCTAssertNil(VoiceCommandParser.parse("scratch"))
        XCTAssertNil(VoiceCommandParser.parse("show"))
        XCTAssertNil(VoiceCommandParser.parse("original"))
        XCTAssertNil(VoiceCommandParser.parse("cancel that"))
        XCTAssertNil(VoiceCommandParser.parse("send it"))
    }

    func testSendThatIsContentNotCommand() {
        XCTAssertNil(VoiceCommandParser.parse("send that"))
        XCTAssertNil(VoiceCommandParser.parse("Send That"))
        XCTAssertNil(VoiceCommandParser.parse("  send that  "))
    }
}
