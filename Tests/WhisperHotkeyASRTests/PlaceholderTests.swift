import XCTest
@testable import WhisperHotkeyASR

final class ASRPlaceholderTests: XCTestCase {
    func testModuleLoads() {
        _ = WhisperHotkeyASRModule.self
    }
}
