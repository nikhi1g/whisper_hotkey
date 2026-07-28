import XCTest
@testable import WhisperHotkeyCore

final class ContractsTests: XCTestCase {
    func testBusyPhasesAreExplicit() {
        XCTAssertTrue(DictationPhase.preparing.isBusy)
        XCTAssertTrue(DictationPhase.listening.isBusy)
        XCTAssertTrue(DictationPhase.transcribing.isBusy)
        XCTAssertTrue(DictationPhase.inserting.isBusy)
        XCTAssertFalse(DictationPhase.idle.isBusy)
        XCTAssertFalse(DictationPhase.failed.isBusy)
    }

    func testControlProtocolRoundTrips() throws {
        let request = ControlRequest(command: .disableLogin)
        let data = try JSONEncoder().encode(request)
        XCTAssertEqual(try JSONDecoder().decode(ControlRequest.self, from: data), request)
    }
}
